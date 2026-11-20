import Foundation
import MapKit
import Testing
@testable import Anchor

// MARK: - Fixtures

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let usc = GeoPoint(lat: 34.0224, lng: -118.2851)

private func config(minutes: Int = 25) -> SessionConfig {
    SessionConfig(studyMinutes: minutes)
}

private func fresh(minutes: Int = 25) -> Session {
    Session.start(config: config(minutes: minutes), zone: Zone.circle(center: usc, radius: 25), at: t0)
}

/// A point `meters` due north of `p`.
private func north(of p: GeoPoint, meters: Double) -> GeoPoint {
    GeoPoint(lat: p.lat + meters / 111_195, lng: p.lng)
}

// MARK: - Geo

@Suite("Geofence")
struct GeofenceTests {
    @Test("distance between two points north-south matches meters")
    func distance() {
        let d = Geo.distanceMeters(usc, north(of: usc, meters: 100))
        #expect(abs(d - 100) < 0.5)
    }
}

// MARK: - Session clocks

@Suite("Session")
struct SessionTests {
    @Test("studying at the anchor counts down the study timer")
    func studies() {
        let s = fresh().advanced(to: t0.addingTimeInterval(60))
        #expect(s.studiedSeconds == 60)
        #expect(s.remainingSeconds == 24 * 60)
        #expect(s.phoneSeconds == 0)
    }

    @Test("phone time counts on the phone clock, not the study timer")
    func phoneDoesNotStudy() {
        let s = fresh()
            .settingPhone(true, at: t0.addingTimeInterval(10))
            .advanced(to: t0.addingTimeInterval(40))
        #expect(s.studiedSeconds == 10)
        #expect(s.phoneSeconds == 30)
        #expect(s.pickups == 1)
    }

    @Test("the phone clock never resets: off and back on resumes where it left off")
    func phoneClockResumes() {
        let s = fresh()
            .settingPhone(true, at: t0)
            .settingPhone(false, at: t0.addingTimeInterval(20))
            .settingPhone(true, at: t0.addingTimeInterval(100))
            .advanced(to: t0.addingTimeInterval(110))
        #expect(s.phoneSeconds == 30)
        #expect(s.studiedSeconds == 80)
        #expect(s.pickups == 2)
    }

    @Test("away from the anchor the phone is free and the study timer pauses")
    func awayPausesEverything() {
        let s = fresh()
            .settingPhone(true, at: t0)
            .settingAway(true, at: t0.addingTimeInterval(5))
            .advanced(to: t0.addingTimeInterval(65))
        #expect(s.phoneSeconds == 5)
        #expect(s.studiedSeconds == 0)
        #expect(s.awaySeconds == 60)
        #expect(s.isOnPhoneCounting == false)
    }

    @Test("picking the phone up while away is not a pickup")
    func awayPickupNotCounted() {
        let s = fresh()
            .settingAway(true, at: t0)
            .settingPhone(true, at: t0.addingTimeInterval(1))
        #expect(s.pickups == 0)
    }

    @Test("the session finishes exactly when the study time is reached")
    func finishes() {
        let s = fresh(minutes: 1).advanced(to: t0.addingTimeInterval(90))
        #expect(s.isComplete)
        #expect(s.studiedSeconds == 60)
        #expect(s.finishedAt == t0.addingTimeInterval(60))
        #expect(s.remainingSeconds == 0)
    }

    @Test("a finished session ignores later events")
    func finishedIsFrozen() {
        let done = fresh(minutes: 1).advanced(to: t0.addingTimeInterval(60))
        let later = done.settingPhone(true, at: t0.addingTimeInterval(70)).advanced(to: t0.addingTimeInterval(200))
        #expect(later == done)
    }

    @Test("time never runs backwards")
    func noNegativeTime() {
        let s = fresh().advanced(to: t0.addingTimeInterval(-30))
        #expect(s.studiedSeconds == 0)
    }

    @Test("advancing returns a new value and leaves the original unchanged")
    func immutable() {
        let a = fresh()
        _ = a.advanced(to: t0.addingTimeInterval(60))
        #expect(a.studiedSeconds == 0)
    }

    @Test("the longest single pickup is remembered")
    func longestStint() {
        let s = fresh()
            .settingPhone(true, at: t0)
            .settingPhone(false, at: t0.addingTimeInterval(40))
            .settingPhone(true, at: t0.addingTimeInterval(50))
            .advanced(to: t0.addingTimeInterval(60))
        #expect(s.longestStintSeconds == 40)
        #expect(s.stintSeconds == 10)
    }

    @Test("study timer projection: when the session will end if you stay off the phone")
    func projectedEnd() {
        let s = fresh(minutes: 25).advanced(to: t0.addingTimeInterval(300))
        #expect(s.projectedFinish(from: t0.addingTimeInterval(300)) == t0.addingTimeInterval(1500))
        #expect(s.settingPhone(true, at: t0.addingTimeInterval(300)).projectedFinish(from: t0.addingTimeInterval(300)) == nil)
    }

    @Test("iOS reports a lock ~10 s late: those seconds go back to the study timer")
    func lockLagRefunded() {
        let s = fresh()
            .settingPhone(true, at: t0.addingTimeInterval(100))
            .lockedPhone(at: t0.addingTimeInterval(130), unseenSeconds: 10)
        #expect(s.phoneSeconds == 20)
        #expect(s.studiedSeconds == 110)
        #expect(s.onPhone == false)
        #expect(s.pickups == 1)
    }

    @Test("locking with Anchor open is not a pickup at all")
    func lockFromAnchorNotAPickup() {
        let s = fresh()
            .settingPhone(true, at: t0.addingTimeInterval(100))
            .lockedPhone(at: t0.addingTimeInterval(110), unseenSeconds: 10)
        #expect(s.phoneSeconds == 0)
        #expect(s.studiedSeconds == 110)
        #expect(s.pickups == 0)
    }

    @Test("the refund only covers this pickup, never earlier phone time")
    func refundCappedToStint() {
        let s = fresh()
            .settingPhone(true, at: t0)
            .settingPhone(false, at: t0.addingTimeInterval(30))
            .settingPhone(true, at: t0.addingTimeInterval(40))
            .lockedPhone(at: t0.addingTimeInterval(44), unseenSeconds: 10)
        #expect(s.phoneSeconds == 30)
        #expect(s.studiedSeconds == 14)
    }

    @Test("a lock while away refunds nothing")
    func lockWhileAway() {
        let s = fresh()
            .settingAway(true, at: t0)
            .settingPhone(true, at: t0)
            .lockedPhone(at: t0.addingTimeInterval(30), unseenSeconds: 10)
        #expect(s.phoneSeconds == 0)
        #expect(s.studiedSeconds == 0)
        #expect(s.awaySeconds == 30)
    }

    @Test("a session survives a JSON round trip")
    func codable() throws {
        let s = fresh().settingPhone(true, at: t0.addingTimeInterval(3))
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Session.self, from: data) == s)
    }
}

// MARK: - Ladder

@Suite("Ladder")
struct LadderTests {
    @Test("buzzes every 15 s for the first minute, then every 5 s")
    func schedule() {
        #expect(Ladder.times(after: 0, limit: 7) == [15, 30, 45, 60, 65, 70, 75])
        #expect(Ladder.times(after: 47, limit: 3) == [60, 65, 70])
        #expect(Ladder.times(after: 60, limit: 2) == [65, 70])
    }

    @Test("buzz count is how many buzz times the phone clock has passed")
    func count() {
        #expect(Ladder.buzzCount(phoneSeconds: 0) == 0)
        #expect(Ladder.buzzCount(phoneSeconds: 14.9) == 0)
        #expect(Ladder.buzzCount(phoneSeconds: 15) == 1)
        #expect(Ladder.buzzCount(phoneSeconds: 60) == 4)
        #expect(Ladder.buzzCount(phoneSeconds: 79) == 7)
    }

    @Test("mid-pickup the buzz delays are the time to each buzz on the phone clock")
    func midPickup() {
        let buzzes = Ladder.buzzes(phoneSeconds: 47, stintSeconds: 30, limit: 3)
        #expect(buzzes.map(\.delay) == [13, 18, 23])
    }

    @Test("after the grace period the ladder picks up where the phone clock left off")
    func resumesWhereLeftOff() {
        #expect(Ladder.buzzes(phoneSeconds: 62, stintSeconds: 0, limit: 3).map(\.delay) == [3, 8, 13])
        #expect(Ladder.buzzes(phoneSeconds: 0, stintSeconds: 0, limit: 1).first?.delay == 15)
    }

    @Test("buzz text names the phone time")
    func text() {
        let b = Ladder.buzzes(phoneSeconds: 59, stintSeconds: 30, limit: 1)[0]
        #expect(b.title == "1:00 on your phone")
        #expect(!b.body.isEmpty)
    }

    @Test("never schedules more than iOS allows")
    func limit() {
        #expect(Ladder.buzzes(phoneSeconds: 0, stintSeconds: 99, limit: 500).count == Ladder.maxPending)
    }
}

// MARK: - Escalation

@Suite("Escalation")
struct EscalationTests {
    @Test("the voice speaks each time the phone clock crosses a 30 s mark")
    func voiceMarks() {
        #expect(Escalation.voiceMark(from: 29, to: 31) == 30)
        #expect(Escalation.voiceMark(from: 31, to: 59) == nil)
        #expect(Escalation.voiceMark(from: 0, to: 20) == nil)
    }

    @Test("the voice goes quiet once the siren takes over at 1:00")
    func voiceStopsAtAlarm() {
        #expect(Escalation.voiceMark(from: 59.5, to: 60.5) == nil)
        #expect(Escalation.voiceMark(from: 89, to: 91) == nil)
    }

    @Test("the siren runs from 1:00 on the phone")
    func alarm() {
        #expect(Escalation.alarmAfterSeconds == 60)
        #expect(!Escalation.isAlarm(phoneSeconds: 59.9))
        #expect(Escalation.isAlarm(phoneSeconds: 60))
    }

    @Test("voice and alarm start the moment the grace period is over")
    func armedRightAway() {
        #expect(Escalation.isArmed(stintSeconds: 0))
    }

    @Test("spoken lines say the time in words")
    func spoken() {
        #expect(Escalation.spokenLine(seconds: 30) == "30 seconds on your phone. Put it down.")
        #expect(Escalation.spokenLine(seconds: 90) == "1 minute 30 seconds on your phone. Put it down.")
        #expect(Escalation.spokenLine(seconds: 60) == "1 minute on your phone. Put it down.")
    }
}

// MARK: - Formatting and setup

@Suite("Format")
struct FormatTests {
    @Test("clock formats minutes and seconds, hours when needed")
    func clock() {
        #expect(Format.clock(0) == "0:00")
        #expect(Format.clock(65.9) == "1:05")
        #expect(Format.clock(3_725) == "1:02:05")
        #expect(Format.clock(-4) == "0:00")
    }

    @Test("study minutes step by 5 between 5 and 240")
    func minutes() {
        #expect(SetupInput.stepped(45, by: 5) == 50)
        #expect(SetupInput.stepped(5, by: -5) == 5)
        #expect(SetupInput.stepped(240, by: 5) == 240)
        #expect(SetupInput.presets == [25, 45, 60, 90])
    }
}

// MARK: - Vibration, volume, library mode

@Suite("Vibration and volume")
struct VibrationVolumeTests {
    @Test("nonstop vibration starts at 0:30 of phone time and keeps going")
    func continuousVibration() {
        #expect(Escalation.vibrateAfterSeconds == 30)
        #expect(!Escalation.isContinuousVibration(phoneSeconds: 29.9))
        #expect(Escalation.isContinuousVibration(phoneSeconds: 30))
        #expect(Escalation.isContinuousVibration(phoneSeconds: 600))
    }

    @Test("the annoyance list in Settings is in order and matches the real thresholds")
    func annoyanceList() {
        let steps = Escalation.annoyances(graceSeconds: 10, library: false)
        #expect(steps.map(\.startsAt) == steps.map(\.startsAt).sorted())
        #expect(steps.contains { $0.startsAt == Escalation.vibrateAfterSeconds })
        #expect(steps.contains { $0.startsAt == Escalation.alarmAfterSeconds })
        let quiet = Escalation.annoyances(graceSeconds: 10, library: true)
        #expect(!quiet.contains { $0.isSound })
    }

    @Test("volume can't go below 3 of 16 notches")
    func volumeFloor() {
        #expect(VolumeRule.floor == 3.0 / 16)
        #expect(VolumeRule.corrected(0) == VolumeRule.floor)
        #expect(VolumeRule.corrected(0.12) == VolumeRule.floor)
        #expect(VolumeRule.corrected(0.19) == nil)
        #expect(VolumeRule.corrected(1) == nil)
    }

    @Test("library mode is off unless chosen, and old saved settings still load")
    func libraryDefault() throws {
        let old = #"{"studyMinutes":45,"radiusMeters":25,"grayscale":false}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SessionConfig.self, from: old)
        #expect(!config.isLibrary)
        #expect(SessionConfig(studyMinutes: 45, library: true).isLibrary)
    }
}

// MARK: - Permission gate

@Suite("Permission gate")
struct PermissionGateTests {
    @Test("location and Precise Location are required; Motion & Fitness and notifications are not")
    func required() {
        #expect(PermissionGate.isReady(location: true, precise: true))
        #expect(!PermissionGate.isReady(location: true, precise: false))
        #expect(!PermissionGate.isReady(location: false, precise: true))
    }
}

// MARK: - Glance grace

@Suite("Glance grace")
struct GlanceGraceTests {
    @Test("the grace after unlocking is free, so checking the Lock Screen never counts")
    func grace() {
        let unlocked = Date(timeIntervalSince1970: 1_000)
        #expect(!PickupRule.isOnPhone(outsideAnchorSince: unlocked, now: unlocked.addingTimeInterval(9.9), grace: 10))
        #expect(PickupRule.isOnPhone(outsideAnchorSince: unlocked, now: unlocked.addingTimeInterval(10), grace: 10))
        #expect(!PickupRule.isOnPhone(outsideAnchorSince: unlocked, now: unlocked.addingTimeInterval(25), grace: 30))
        #expect(PickupRule.isOnPhone(outsideAnchorSince: unlocked, now: unlocked, grace: 0))
        #expect(!PickupRule.isOnPhone(outsideAnchorSince: nil, now: unlocked, grace: 0))
    }

    @Test("the grace is 0 to 60 s in 5 s steps, 10 s unless chosen, and old settings still load")
    func setting() throws {
        #expect(PickupRule.defaultGraceSeconds == 10)
        #expect(PickupRule.steppedGrace(10, by: 5) == 15)
        #expect(PickupRule.steppedGrace(0, by: -5) == 0)
        #expect(PickupRule.steppedGrace(60, by: 5) == 60)
        let old = #"{"studyMinutes":45,"radiusMeters":25,"grayscale":false}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(SessionConfig.self, from: old).graceSeconds == 10)
        #expect(SessionConfig(studyMinutes: 45, grace: 30).graceSeconds == 30)
    }
}

// MARK: - Live Activity states

@Suite("Live Activity")
struct LiveActivityStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var session: Session {
        Session.start(config: SessionConfig(studyMinutes: 25),
                      zone: Zone.circle(center: GeoPoint(lat: 34, lng: -118), radius: 25), at: t0)
    }

    @Test("in the grace period it is gray, counts the grace down, and the study clock keeps going")
    func grace() {
        let now = t0.addingTimeInterval(60)
        let state = LiveActivityController.state(for: session.advanced(to: now), at: now,
                                                 graceEndsAt: now.addingTimeInterval(7))
        #expect(state.mode == .grace)
        #expect(state.graceEndsAt == now.addingTimeInterval(7))
        #expect(state.studyEndsAt == now.addingTimeInterval(24 * 60))
        #expect(state.phoneZeroAt == nil)
    }

    @Test("on the phone it is red and the study clock is frozen")
    func onPhone() {
        let now = t0.addingTimeInterval(60)
        let s = session.settingPhone(true, at: now)
        let state = LiveActivityController.state(for: s, at: now, graceEndsAt: nil)
        #expect(state.mode == .onPhone)
        #expect(state.studyEndsAt == nil)
        #expect(state.graceEndsAt == nil)
    }

    @Test("no grace while studying in Anchor")
    func studying() {
        let state = LiveActivityController.state(for: session, at: t0, graceEndsAt: nil)
        #expect(state.mode == .studying)
    }
}


// MARK: - Zones

/// A point `east`/`north` meters from `origin`, the same flat projection the zones use.
private func offset(_ origin: GeoPoint, _ east: Double, _ north: Double) -> GeoPoint {
    ZoneGeometry.point(from: origin, east: east, north: north)
}

private let campus = GeoPoint(lat: 34.0218, lng: -118.2830)
/// 100 m square centered on `campus`.
private let square: [GeoPoint] = [(-50, -50), (50, -50), (50, 50), (-50, 50)].map { offset(campus, $0.0, $0.1) }
private let beaconUUID = UUID(uuidString: "D0236BD0-F73D-463D-930C-7803C1B2E8A3")!
private let room = StudyArea(id: "room-2", name: "Study Room 2", floor: 1,
                             beacon: BeaconID(uuid: beaconUUID, major: 1, minor: 2))
private let library = Zone(id: "lib", name: "Library", polygon: square, studyAreas: [room])
private let hall = Zone(id: "hall", name: "Hall", polygon: square)

@Suite("Zone outlines")
struct ZoneOutlineTests {
    /// An L: the top-right corner is cut out.
    private let ell = [(0, 0), (100, 0), (100, 40), (40, 40), (40, 100), (0, 100)].map { offset(campus, Double($0.0), Double($0.1)) }

    @Test("a point is inside or outside the outline, right up to the edge")
    func pointInPolygon() {
        #expect(ZoneGeometry.contains(campus, in: square))
        #expect(ZoneGeometry.contains(offset(campus, 49.5, 0), in: square))
        #expect(!ZoneGeometry.contains(offset(campus, 50.5, 0), in: square))
        #expect(ZoneGeometry.contains(offset(campus, 0, -49.5), in: square))
        #expect(!ZoneGeometry.contains(offset(campus, 0, -50.5), in: square))
        #expect(!ZoneGeometry.contains(offset(campus, 60, 60), in: square))
    }

    @Test("concave outlines work: the notch of an L is outside")
    func concave() {
        #expect(ZoneGeometry.contains(offset(campus, 20, 80), in: ell))
        #expect(ZoneGeometry.contains(offset(campus, 70, 20), in: ell))
        #expect(!ZoneGeometry.contains(offset(campus, 70, 70), in: ell))
    }

    @Test("depth is meters to the nearest edge: positive inside, negative outside")
    func depth() {
        #expect(abs(ZoneGeometry.depth(of: campus, in: square) - 50) < 0.5)
        #expect(abs(ZoneGeometry.depth(of: offset(campus, 45, 0), in: square) - 5) < 0.5)
        #expect(abs(ZoneGeometry.depth(of: offset(campus, 60, 0), in: square) + 10) < 0.5)
        #expect(abs(ZoneGeometry.depth(of: offset(campus, 70, 70), in: ell) + 30) < 0.5)
    }

    @Test("the wake circle is the smallest circle around the outline plus 30 m, never under 100 m")
    func wakeCircle() {
        let circle = ZoneGeometry.enclosingCircle(square)
        #expect(abs(circle.radius - 50 * 2.squareRoot()) < 0.5)
        #expect(Geo.distanceMeters(circle.center, campus) < 0.5)
        #expect(abs(hall.wakeRadiusMeters - (50 * 2.squareRoot() + 30)) < 0.5)
        let small = [(-10, -10), (10, -10), (10, 10)].map { offset(campus, Double($0.0), Double($0.1)) }
        #expect(Zone(id: "s", name: "S", polygon: small).wakeRadiusMeters == Zone.minWakeRadiusMeters)
        #expect(square.allSatisfy { Geo.distanceMeters(hall.center, $0) <= hall.wakeRadiusMeters })
    }

    @Test("Leavey Library ships in Zones.json with its real outline and study areas")
    func leavey() throws {
        let zones = try BundledZoneStore().zones()
        let leavey = try #require(zones.first { $0.id == "usc-leavey-library" })
        #expect(leavey.polygon.count >= 10)
        #expect(leavey.contains(GeoPoint(lat: 34.02175, lng: -118.28290)))
        #expect(!leavey.contains(GeoPoint(lat: 34.02300, lng: -118.28290)))
        #expect(!leavey.studyAreas.isEmpty)
    }

    @Test("a zones file with no zones, a broken outline, or a beacon used twice is refused")
    func badCatalog() {
        #expect(throws: ZoneCatalog.Problem.self) {
            try ZoneCatalog.decode(Data(#"{"version":1,"zones":[{"id":"x","name":"X","polygon":[[34,-118],[34.1,-118]]}]}"#.utf8))
        }
        #expect(throws: ZoneCatalog.Problem.self) {
            try ZoneCatalog.decode(Data(#"{"version":1,"zones":[{"id":"x","name":"X","polygon":[[134,-118],[34.1,-118],[34.1,-118.1]]}]}"#.utf8))
        }
        let beacon = #"{"uuid":"D0236BD0-F73D-463D-930C-7803C1B2E8A3","major":1,"minor":1}"#
        let twice = #"{"version":1,"zones":[{"id":"x","name":"X","polygon":[[34,-118],[34.1,-118],[34.1,-118.1]],"studyAreas":[{"id":"a","name":"A","beacon":"# + beacon + #"},{"id":"b","name":"B","beacon":"# + beacon + #"}]}]}"#
        #expect(throws: ZoneCatalog.Problem.duplicateBeacon("b")) { try ZoneCatalog.decode(Data(twice.utf8)) }
    }
}

// MARK: - Accuracy circles and the exit rule

@Suite("Inside or outside")
struct InsideOutsideTests {
    @Test("a reading counts as inside when its accuracy circle is mostly inside")
    func mostlyInside() {
        #expect(ZoneGeometry.fit(center: campus, radius: 20, in: square) == .mostlyInside)
        // 8 m in from the edge with a 10 m circle: only a sliver pokes out.
        #expect(ZoneGeometry.fit(center: offset(campus, 42, 0), radius: 10, in: square) == .mostlyInside)
        // Right on the edge: half in, half out, so neither.
        #expect(ZoneGeometry.fit(center: offset(campus, 50, 0), radius: 10, in: square) == .straddling)
        // 3 m out with a 10 m circle: mostly out but not wholly.
        #expect(ZoneGeometry.fit(center: offset(campus, 53, 0), radius: 10, in: square) == .straddling)
    }

    @Test("a reading counts as outside only when its whole circle is outside")
    func fullyOutside() {
        #expect(ZoneGeometry.fit(center: offset(campus, 61, 0), radius: 10, in: square) == .fullyOutside)
        #expect(ZoneGeometry.fit(center: offset(campus, 59, 0), radius: 10, in: square) == .straddling)
    }

    @Test("leaving takes 3 outside readings in a row and 10 s, whichever is later")
    func exitRule() {
        let inside = BuildingPresence.unknown.updated(with: .mostlyInside, at: t0)
        #expect(inside.state == .inside)
        // Three readings in 2 s: not 10 s yet.
        let quick = [1.0, 2, 3].reduce(inside) { $0.updated(with: .fullyOutside, at: t0.addingTimeInterval($1)) }
        #expect(quick.state == .inside)
        #expect(quick.updated(with: .fullyOutside, at: t0.addingTimeInterval(11)).state == .outside)
        // Two readings over 20 s: not 3 readings yet.
        let slow = inside.updated(with: .fullyOutside, at: t0.addingTimeInterval(1))
            .updated(with: .fullyOutside, at: t0.addingTimeInterval(21))
        #expect(slow.state == .inside)
        #expect(slow.updated(with: .fullyOutside, at: t0.addingTimeInterval(22)).state == .outside)
    }

    @Test("the status line says outside from the first wholly-outside reading; leaving still waits")
    func displayState() {
        let p = BuildingPresence.unknown.updated(with: .fullyOutside, at: t0)
        #expect(p.state(at: t0) == .unknown)
        #expect(p.displayState(at: t0) == .outside)
    }

    @Test("a reading that straddles the edge breaks the run of outside readings")
    func straddleResets() {
        let p = BuildingPresence.unknown.updated(with: .mostlyInside, at: t0)
            .updated(with: .fullyOutside, at: t0.addingTimeInterval(1))
            .updated(with: .fullyOutside, at: t0.addingTimeInterval(6))
            .updated(with: .straddling, at: t0.addingTimeInterval(8))
            .updated(with: .fullyOutside, at: t0.addingTimeInterval(12))
        #expect(p.state == .inside)
        #expect(p.outsideRun == 1)
    }

    @Test("with no reading for 30 s it no longer claims to know, and an old run doesn't count")
    func stale() {
        let p = BuildingPresence.unknown.updated(with: .mostlyInside, at: t0)
        #expect(p.state(at: t0.addingTimeInterval(29)) == .inside)
        #expect(p.state(at: t0.addingTimeInterval(31)) == .unknown)
        let old = p.updated(with: .fullyOutside, at: t0.addingTimeInterval(1))
            .updated(with: .fullyOutside, at: t0.addingTimeInterval(2))
        #expect(old.updated(with: .fullyOutside, at: t0.addingTimeInterval(100)).state == .unknown)
    }
}

// MARK: - Cleaning up readings

@Suite("Location filter")
struct LocationFilterTests {
    private func reading(_ east: Double, acc: Double = 5, at s: Double = 0, spoofed: Bool = false) -> LocationReading {
        LocationReading(point: offset(campus, east, 0), accuracy: acc, time: t0.addingTimeInterval(s), isSpoofed: spoofed)
    }

    @Test("readings worse than 20 m, older than 5 s, or invalid are thrown out")
    func badReadings() {
        let now = t0.addingTimeInterval(1)
        #expect(LocationFilter.verdict(for: reading(0, acc: 20, at: 1), at: now) == .use)
        #expect(LocationFilter.verdict(for: reading(0, acc: 21, at: 1), at: now) == .tooInaccurate)
        #expect(LocationFilter.verdict(for: reading(0, acc: -1, at: 1), at: now) == .invalid)
        #expect(LocationFilter.verdict(for: reading(0, at: -4.9), at: now) == .tooOld)
        #expect(LocationFilter.verdict(for: reading(0, at: -3.9), at: now) == .use)
    }

    @Test("spoofed readings are never used, however sharp")
    func spoofedReadings() {
        #expect(LocationFilter.verdict(for: reading(0, acc: 3, at: 0, spoofed: true), at: t0) == .spoofed)
    }

    @Test("sitting still, the estimate settles tighter than any single reading")
    func settles() throws {
        let f = (0..<30).reduce(LocationFilter()) { f, s in f.adding(reading(s.isMultiple(of: 2) ? 4 : -4, acc: 10, at: Double(s))) }
        let estimate = try #require(f.estimate)
        #expect(estimate.accuracy < 10)
        #expect(abs(ZoneGeometry.meters(estimate.point, from: campus).x) < 2)
    }

    @Test("sharper readings pull harder")
    func weighted() throws {
        let f = LocationFilter().adding(reading(0, acc: 5, at: 0)).adding(reading(20, acc: 20, at: 0))
        #expect(ZoneGeometry.meters(try #require(f.estimate).point, from: campus).x < 2)
    }

    @Test("walking, the estimate keeps up instead of trailing behind")
    func keepsUp() throws {
        let f = (0..<40).reduce(LocationFilter()) { f, s in f.adding(reading(Double(s) * 1.4, acc: 5, at: Double(s))) }
        let east = ZoneGeometry.meters(try #require(f.estimate).point, from: campus).x
        #expect(abs(east - 39 * 1.4) < 4)
    }

    @Test("a reading older than the estimate is ignored")
    func outOfOrder() {
        let f = LocationFilter().adding(reading(0, at: 10))
        #expect(f.adding(reading(30, at: 5)) == f)
    }
}

// MARK: - Beacons and how it all combines

@Suite("Beacons")
struct BeaconTests {
    @Test("in a study area when its beacon is immediate, near, or far but closer than 8 m")
    func thresholds() {
        #expect(BeaconRules.isClose(.immediate, accuracy: 0.3))
        #expect(BeaconRules.isClose(.near, accuracy: 2))
        #expect(BeaconRules.isClose(.far, accuracy: 7.9))
        #expect(!BeaconRules.isClose(.far, accuracy: 8))
        #expect(!BeaconRules.isClose(.far, accuracy: -1))
        #expect(!BeaconRules.isClose(.unknown, accuracy: 1))
    }

    @Test("you've left a study area after 15 s with no close reading")
    func lost() {
        let key = AreaKey(zoneID: "lib", areaID: "room-2")
        let seen = AreaPresence().sighted(key, proximity: .near, accuracy: 2, at: t0)
        #expect(seen.current(in: "lib", at: t0.addingTimeInterval(15)) == "room-2")
        #expect(seen.current(in: "lib", at: t0.addingTimeInterval(15.1)) == nil)
        let farAway = seen.sighted(key, proximity: .far, accuracy: 12, at: t0.addingTimeInterval(10))
        #expect(farAway.current(in: "lib", at: t0.addingTimeInterval(16)) == nil)
        #expect(seen.current(in: "other", at: t0) == nil)
    }

    @Test("study-area beacon in the building locks; the lobby and outside are free")
    func combination() {
        #expect(ZoneRules.lock(zone: library, building: .inside, areaID: "room-2", rangingLive: true) == .locked(areaID: "room-2"))
        #expect(ZoneRules.lock(zone: library, building: .inside, areaID: nil, rangingLive: true) == .free)
        #expect(ZoneRules.lock(zone: library, building: .outside, areaID: "room-2", rangingLive: true) == .free)
        #expect(ZoneRules.lock(zone: library, building: .outside, areaID: nil, rangingLive: true) == .free)
        // Indoors GPS often can't prove you're in: a close beacon is enough unless GPS is sure you're out.
        #expect(ZoneRules.lock(zone: library, building: .unknown, areaID: "room-2", rangingLive: true) == .locked(areaID: "room-2"))
        #expect(ZoneRules.lock(zone: library, building: .inside, areaID: "not-here", rangingLive: true) == .free)
    }

    @Test("a zone with no study areas is the whole building")
    func wholeBuilding() {
        #expect(ZoneRules.lock(zone: hall, building: .inside, areaID: nil, rangingLive: true) == .locked(areaID: nil))
        #expect(ZoneRules.lock(zone: hall, building: .outside, areaID: nil, rangingLive: true) == .free)
        #expect(ZoneRules.lock(zone: hall, building: .unknown, areaID: nil, rangingLive: true) == .undecided)
    }

    @Test("the status line: study area, building but not a study area, or outside")
    func place() {
        let zones = [library, hall]
        #expect(ZoneRules.place(zones: zones, buildings: ["lib": .inside], areaIn: { _ in "room-2" }) == .inStudyArea(library, room))
        #expect(ZoneRules.place(zones: zones, buildings: ["lib": .inside], areaIn: { _ in nil }) == .inBuilding(library))
        #expect(ZoneRules.place(zones: zones, buildings: ["hall": .inside], areaIn: { _ in nil }) == .inZone(hall))
        #expect(ZoneRules.place(zones: zones, buildings: ["lib": .outside, "hall": .outside], areaIn: { _ in nil }) == .outside)
        #expect(ZoneRules.place(zones: zones, buildings: [:], areaIn: { _ in nil }) == .locating)
    }

    @Test("a spoofed reading keeps you in the zone")
    func spoofKeepsYouIn() {
        let out = BuildingPresence(state: .outside, outsideRun: 5, outsideSince: t0, lastReadingAt: t0)
        let after = out.spoofed(at: t0.addingTimeInterval(1))
        #expect(after.state == .inside)
        #expect(ZoneRules.lock(zone: hall, building: after.state(at: t0.addingTimeInterval(1)), areaID: nil, rangingLive: true) == .locked(areaID: nil))
    }
}

// MARK: - Saved sessions

@Suite("Saved sessions")
struct SavedSessionTests {
    @Test("a session saved before zones (a dropped anchor with a radius) still loads, as a circle")
    func preZones() throws {
        let json = #"""
        {"config":{"studyMinutes":45,"radiusMeters":30,"grayscale":false,"library":true,"grace":10},
         "anchor":{"lat":34.0224,"lng":-118.2851},"anchorAccuracy":12,"startedAt":800000000,"lastTick":800000060,
         "studiedSeconds":60,"phoneSeconds":0,"stintSeconds":0,"longestStintSeconds":0,"awaySeconds":0,
         "onPhone":false,"away":false,"pickups":0}
        """#
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(session.zone == nil)
        #expect(session.config.zoneID == nil)
        #expect(session.spoofedReadings == 0)
        #expect(abs(session.area.depth(of: session.anchor) - 30) < 0.5)
    }

    @Test("a session saved by the first zones build (no study areas yet) still loads as a whole building")
    func firstZonesBuild() throws {
        let json = #"""
        {"config":{"studyMinutes":45,"radiusMeters":25,"grayscale":false},
         "zone":{"id":"usc-leavey-library","name":"Leavey Library","polygon":[{"lat":34.0219,"lng":-118.2829},{"lat":34.0217,"lng":-118.2824},{"lat":34.0215,"lng":-118.2826}]},
         "anchor":{"lat":34.0217,"lng":-118.2826},"anchorAccuracy":0,"startedAt":800000000,"lastTick":800000060,
         "studiedSeconds":60,"phoneSeconds":0,"stintSeconds":0,"longestStintSeconds":0,"awaySeconds":0,
         "onPhone":false,"away":false,"pickups":0}
        """#
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(session.zone?.usesWholeBuilding == true)
    }

    @Test("a session remembers its zone and study area, and counts spoofed readings")
    func zoneAndArea() throws {
        let config = SessionConfig(studyMinutes: 25, zoneID: "lib", areaID: "room-2")
        let session = Session.start(config: config, zone: library, at: t0).countingSpoof()
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        #expect(back.config.zoneID == "lib")
        #expect(back.config.areaID == "room-2")
        #expect(back.placeName == "Library · Study Room 2")
        #expect(back.spoofedReadings == 1)
    }
}

// MARK: - Review fixes (zones and beacons)

@Suite("Zone and beacon review fixes")
struct ZoneBeaconReviewTests {
    @Test("no beacon only frees you while ranging is actually reporting; if iOS goes quiet, nothing changes")
    func rangingSilence() {
        #expect(ZoneRules.lock(zone: library, building: .unknown, areaID: nil, rangingLive: true) == .free)
        #expect(ZoneRules.lock(zone: library, building: .unknown, areaID: nil, rangingLive: false) == .undecided)
        #expect(ZoneRules.lock(zone: library, building: .inside, areaID: nil, rangingLive: false) == .undecided)
        // GPS sure you're outside still frees you, ranging or not.
        #expect(ZoneRules.lock(zone: library, building: .outside, areaID: nil, rangingLive: false) == .free)
    }

    @Test("ranging is live for 5 s after its last report, empty reports included")
    func rangingLive() {
        let ranged = AreaPresence().ranged(at: t0)
        #expect(ranged.isRangingLive(at: t0.addingTimeInterval(5)))
        #expect(!ranged.isRangingLive(at: t0.addingTimeInterval(5.1)))
        #expect(!AreaPresence().isRangingLive(at: t0))
    }

    @Test("a rough reading counts toward leaving only when its whole circle is outside")
    func roughExitEvidence() {
        let inside = BuildingPresence.unknown.updated(with: .mostlyInside, at: t0)
        #expect(LocationFilter.isExitEvidence(accuracy: 40))
        #expect(!LocationFilter.isExitEvidence(accuracy: 80))
        #expect(!LocationFilter.isExitEvidence(accuracy: -1))
        let rough = [1.0, 6, 11].reduce(inside) { $0.updatedRough(with: .fullyOutside, at: t0.addingTimeInterval($1)) }
        #expect(rough.state == .outside)
        #expect(inside.updatedRough(with: .straddling, at: t0.addingTimeInterval(1)) == inside)
        #expect(inside.updatedRough(with: .mostlyInside, at: t0.addingTimeInterval(1)) == inside)
    }

    @Test("the status line's early 'outside' goes stale like everything else")
    func displayStale() {
        let p = BuildingPresence.unknown.updated(with: .fullyOutside, at: t0)
        #expect(p.displayState(at: t0.addingTimeInterval(31)) == .unknown)
    }

    @Test("a zones file iOS couldn't watch (over 20 zones and areas) or with unsafe ids is refused")
    func watchLimits() {
        let areas = (0..<20).map { #"{"id":"a\#($0)","name":"A","beacon":{"uuid":"D0236BD0-F73D-463D-930C-7803C1B2E8A3","major":1,"minor":\#($0)}}"# }
        let tooMany = #"{"version":1,"zones":[{"id":"x","name":"X","polygon":[[34,-118],[34.1,-118],[34.1,-118.1]],"studyAreas":["# + areas.joined(separator: ",") + "]}]}"
        #expect(throws: ZoneCatalog.Problem.tooManyToWatch) { try ZoneCatalog.decode(Data(tooMany.utf8)) }
        let pipe = #"{"version":1,"zones":[{"id":"x|y","name":"X","polygon":[[34,-118],[34.1,-118],[34.1,-118.1]]}]}"#
        #expect(throws: ZoneCatalog.Problem.badID("x|y")) { try ZoneCatalog.decode(Data(pipe.utf8)) }
    }
}

// MARK: - Dropped anchors

@Suite("Dropped anchor")
struct DroppedAnchorTests {
    @Test("the lock radius is 25 to 200 m in 5 m steps, 25 by default")
    func radius() {
        #expect(AnchorRules.defaultRadiusMeters == 25)
        #expect(AnchorRules.clampedRadius(10) == 25)
        #expect(AnchorRules.clampedRadius(37) == 35)
        #expect(AnchorRules.clampedRadius(38) == 40)
        #expect(AnchorRules.clampedRadius(900) == 200)
    }

    @Test("an anchor needs a reading within 65 m and 10 s")
    func usableAnchor() {
        #expect(AnchorRules.isUsableAnchor(accuracy: 30, age: 5))
        #expect(AnchorRules.isUsableAnchor(accuracy: 65, age: 10))
        #expect(!AnchorRules.isUsableAnchor(accuracy: 30, age: 11))
        #expect(!AnchorRules.isUsableAnchor(accuracy: 66, age: 1))
        #expect(!AnchorRules.isUsableAnchor(accuracy: -1, age: 1))
    }

    @Test("the spot is exactly your radius around the anchor")
    func circle() {
        let spot = Zone.droppedAnchor(center: campus, radius: 25)
        #expect(spot.isDroppedAnchor)
        #expect(spot.usesWholeBuilding)
        #expect(abs(spot.depth(of: campus) - 25) < 0.5)
    }

    @Test("the edge margin: at least 8 m, more when the GPS is rougher")
    func margin() {
        #expect(LocationFilter.margin(estimateAccuracy: 3, readingAccuracy: 5) == 8)
        #expect(LocationFilter.margin(estimateAccuracy: 3, readingAccuracy: 20) == 15)
        #expect(LocationFilter.margin(estimateAccuracy: 12, readingAccuracy: 10) == 12)
    }

    @MainActor
    @Test("sitting 8 m inside an area, GPS drifting 13 m outward with 10 m readings doesn't free you")
    func drift() {
        let tracker = ZoneTracker(zones: [])
        let spot = Zone.droppedAnchor(center: campus, radius: 25)
        tracker.setExtraZone(spot)
        for s in 0..<30 {
            let time = t0.addingTimeInterval(Double(s))
            // You're 17 m out from the anchor (8 m inside the edge); GPS says 30 m (5 m outside).
            tracker.received(LocationReading(point: offset(campus, 30, 0), accuracy: 10, time: time, isSpoofed: false), at: time)
        }
        #expect(tracker.building(spot.id, at: t0.addingTimeInterval(29)) != .outside)
    }

    @MainActor
    @Test("with steady 5 m GPS, a 25 m spot frees you about 33 m out, not 46")
    func unlockDistance() {
        func state(atMeters meters: Double) -> BuildingPresence.State {
            let tracker = ZoneTracker(zones: [])
            let spot = Zone.droppedAnchor(center: campus, radius: 25)
            tracker.setExtraZone(spot)
            for s in 0..<15 {
                let time = t0.addingTimeInterval(Double(s))
                tracker.received(LocationReading(point: offset(campus, meters, 0), accuracy: 5, time: time, isSpoofed: false), at: time)
            }
            return tracker.building(spot.id, at: t0.addingTimeInterval(14))
        }
        #expect(state(atMeters: 31) != .outside)
        #expect(state(atMeters: 34) == .outside)
        #expect(state(atMeters: 20) == .inside)
    }

    @Test("a dropped-anchor session keeps its circle and radius, and the Lock Screen shows no place name")
    func session() throws {
        let config = SessionConfig(studyMinutes: 25, radiusMeters: 40)
        let started = Session.start(config: config, zone: Zone.droppedAnchor(center: campus, radius: 40), at: t0)
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(started))
        #expect(back.config.radiusMeters == 40)
        #expect(back.isDroppedAnchor)
        #expect(back.lockScreenPlace == nil)
        #expect(Session.start(config: config, zone: library, at: t0).lockScreenPlace == "Library")
    }

    @Test("leaving your spot needs your whole accuracy circle outside it, like any zone")
    func leaving() {
        let spot = Zone.droppedAnchor(center: campus, radius: 25)
        #expect(ZoneGeometry.fit(center: offset(campus, 30, 0), radius: 10, in: spot.polygon) == .straddling)
        #expect(ZoneGeometry.fit(center: offset(campus, 36, 0), radius: 10, in: spot.polygon) == .fullyOutside)
    }

    @MainActor
    @Test("starting in a real zone keeps what's known about that building")
    func zoneKeepsPresence() {
        let tracker = ZoneTracker(zones: [hall])
        tracker.received(LocationReading(point: campus, accuracy: 5, time: t0, isSpoofed: false), at: t0)
        #expect(tracker.building("hall", at: t0) == .inside)
        tracker.setExtraZone(hall)
        #expect(tracker.building("hall", at: t0) == .inside)
        #expect(tracker.extraZone == nil)
    }

    @MainActor
    @Test("a new spot starts fresh: the last spot's in/out doesn't carry over")
    func freshSpot() {
        let tracker = ZoneTracker(zones: [])
        let first = Zone.droppedAnchor(center: campus, radius: 25)
        tracker.setExtraZone(first)
        tracker.received(LocationReading(point: offset(campus, 300, 0), accuracy: 5, time: t0, isSpoofed: false), at: t0)
        #expect(tracker.buildings[first.id] != nil)
        tracker.setExtraZone(Zone.droppedAnchor(center: offset(campus, 300, 0), radius: 25))
        #expect(tracker.buildings[first.id] == nil)
    }
}

// MARK: - Map zoom

@Suite("Map zoom")
struct MapZoomTests {
    @Test("each tap halves or doubles what the map shows")
    func steps() {
        #expect(MapZoom.span(400, zoomingIn: true) == 200)
        #expect(MapZoom.span(400, zoomingIn: false) == 800)
    }

    @Test("zoom stops at about a room's width and a city's")
    func limits() {
        #expect(MapZoom.span(70, zoomingIn: true) == MapZoom.minSpanMeters)
        #expect(MapZoom.span(30_000, zoomingIn: false) == MapZoom.maxSpanMeters)
        #expect(!MapZoom.canZoom(span: MapZoom.minSpanMeters, zoomingIn: true))
        #expect(MapZoom.canZoom(span: MapZoom.minSpanMeters, zoomingIn: false))
        #expect(!MapZoom.canZoom(span: MapZoom.maxSpanMeters, zoomingIn: false))
    }

    @Test("while following you, a zoom is kept as a scale on the framing, within the same limits")
    func followScale() {
        #expect(MapZoom.scale(1, base: 400, zoomingIn: true) == 0.5)
        #expect(MapZoom.scale(1, base: 400, zoomingIn: false) == 2)
        #expect(MapZoom.scale(0.25, base: 400, zoomingIn: true) == MapZoom.minSpanMeters / 400)
    }
}

@Suite("Map zoom regions")
struct MapZoomRegionTests {
    private let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.02, longitude: -118.28),
                                            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.003))

    @Test("the width in meters accounts for latitude")
    func width() {
        #expect(abs(MapZoom.spanMeters(of: region) - 0.003 * 111_195 * cos(34.02 * .pi / 180)) < 0.01)
    }

    @Test("zooming keeps the map's shape and, by default, its center")
    func keepsShape() {
        let zoomed = MapZoom.region(region, spanMeters: MapZoom.spanMeters(of: region) / 2)
        #expect(abs(zoomed.span.latitudeDelta - 0.002) < 1e-9)
        #expect(abs(zoomed.span.longitudeDelta - 0.0015) < 1e-9)
        #expect(zoomed.center.latitude == region.center.latitude)
    }

    @Test("with the sheet over the bottom, the point in the open top part stays put")
    func keepsFocus() {
        let old = MapZoom.spanMeters(of: region)
        let zoomed = MapZoom.region(region, spanMeters: old / 2, focusShare: 0.45)
        let focusBefore = region.center.latitude + old * 0.45 / 111_195
        let focusAfter = zoomed.center.latitude + (old / 2) * 0.45 / 111_195
        #expect(abs(focusBefore - focusAfter) < 1e-9)
    }
}

// MARK: - Drawn areas

@Suite("Drawn areas")
struct DrawnAreaTests {
    private func pts(_ list: [(Double, Double)]) -> [GeoPoint] { list.map { offset(campus, $0.0, $0.1) } }

    @Test("an area needs at least 3 dots, can't cross itself, and isn't tiny")
    func validation() {
        #expect(DrawnArea.problem(with: pts([(0, 0), (40, 0)])) == .tooFewPoints)
        // A bow tie: the outline crosses itself.
        #expect(DrawnArea.problem(with: pts([(0, 0), (40, 40), (40, 0), (0, 40)])) == .crossesItself)
        #expect(DrawnArea.problem(with: pts([(0, 0), (3, 0), (0, 3)])) == .tooSmall)
        #expect(DrawnArea.problem(with: pts([(0, 0), (40, 0), (40, 30), (0, 30)])) == nil)
        // Concave is fine.
        #expect(DrawnArea.problem(with: pts([(0, 0), (60, 0), (60, 20), (20, 20), (20, 50), (0, 50)])) == nil)
    }

    @Test("area in square meters")
    func size() {
        #expect(abs(DrawnArea.squareMeters(pts([(0, 0), (40, 0), (40, 30), (0, 30)])) - 1200) < 5)
    }

    @Test("a saved area is a whole-area zone with a watchable id and your name")
    func zone() {
        let zone = DrawnArea.zone(named: "  Desk by the window ", points: pts([(0, 0), (40, 0), (40, 30)]), id: "mine-abc123")
        #expect(zone.isUserArea)
        #expect(zone.usesWholeBuilding)
        #expect(zone.name == "Desk by the window")
        #expect(DrawnArea.zone(named: "", points: pts([(0, 0), (40, 0), (40, 30)]), id: "mine-x").name == "My area")
        #expect(DrawnArea.newID().allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
    }

    @Test("new areas are named My area 1, 2, … skipping names in use")
    func names() {
        let one = DrawnArea.zone(named: "My area 1", points: pts([(0, 0), (40, 0), (40, 30)]), id: "mine-1")
        #expect(DrawnArea.defaultName(existing: []) == "My area 1")
        #expect(DrawnArea.defaultName(existing: [one]) == "My area 2")
    }

    @Test("saved areas survive a relaunch")
    func stored() throws {
        let defaults = try #require(UserDefaults(suiteName: "anchor.tests.areas"))
        defaults.removePersistentDomain(forName: "anchor.tests.areas")
        let store = SessionStore(defaults: defaults)
        let area = DrawnArea.zone(named: "Desk", points: pts([(0, 0), (40, 0), (40, 30)]), id: "mine-1")
        store.saveUserZones([area])
        #expect(store.loadUserZones() == [area])
    }

    @Test("iOS watches at most 20 things: the library's zones and areas first, then yours in order")
    func watchLimit() {
        let mine = (0..<25).map { DrawnArea.zone(named: "A\($0)", points: pts([(0, 0), (40, 0), (40, 30)]), id: "mine-\($0)") }
        let fitted = ZoneRules.watchable([library] + mine)
        #expect(fitted.first == library)
        #expect(fitted.count + fitted.reduce(0) { $0 + $1.studyAreas.count } <= 20)
        #expect(fitted.count == 1 + 18)
    }
}

@Suite("New areas")
struct NewAreaTests {
    @MainActor
    @Test("a newly saved area knows you're in it right away, without waiting for another reading")
    func immediate() {
        let tracker = ZoneTracker(zones: [])
        let now = Date()
        tracker.received(LocationReading(point: campus, accuracy: 5, time: now, isSpoofed: false), at: now)
        let area = DrawnArea.zone(named: "Desk", points: square, id: "mine-1")
        tracker.setZones([area], at: now)
        #expect(tracker.building(area.id, at: now) == .inside)
        #expect(tracker.lockingZone(at: now)?.zone == area)
    }
}
