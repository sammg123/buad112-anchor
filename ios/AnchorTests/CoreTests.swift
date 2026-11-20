import Foundation
import Testing
@testable import Anchor

// MARK: - Fixtures

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let usc = GeoPoint(lat: 34.0224, lng: -118.2851)

private func config(minutes: Int = 25, radius: Double = 25) -> SessionConfig {
    SessionConfig(studyMinutes: minutes, radiusMeters: radius, grayscale: false)
}

private func fresh(minutes: Int = 25) -> Session {
    Session.start(config: config(minutes: minutes), anchor: usc, anchorAccuracy: 10, at: t0)
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

    @Test("unlock distance is the chosen radius plus the worse accuracy, capped at 50 m")
    func unlockDistance() {
        #expect(AnchorRules.unlockDistance(radius: 25, anchorAccuracy: 10, fixAccuracy: 20) == 45)
        #expect(AnchorRules.unlockDistance(radius: 25, anchorAccuracy: 400, fixAccuracy: 5) == 75)
        #expect(AnchorRules.unlockDistance(radius: 100, anchorAccuracy: -1, fixAccuracy: -1) == 100)
    }

    @Test("the lock radius is 25 m at least, 200 m at most, in 5 m steps")
    func radiusClamp() {
        #expect(AnchorRules.defaultRadiusMeters == 25)
        #expect(AnchorRules.clampedRadius(10) == 25)
        #expect(AnchorRules.clampedRadius(37) == 35)
        #expect(AnchorRules.clampedRadius(38) == 40)
        #expect(AnchorRules.clampedRadius(900) == 200)
    }

    @Test("inside the unlock distance you are at the anchor; past it you are away")
    func zone() {
        #expect(AnchorRules.isAway(distance: 69.9, unlockDistance: 70) == false)
        #expect(AnchorRules.isAway(distance: 70.1, unlockDistance: 70) == true)
    }

    @Test("an anchor fix must be fresh and reasonably accurate")
    func anchorFix() {
        #expect(AnchorRules.isUsableAnchor(accuracy: 30, age: 5))
        #expect(!AnchorRules.isUsableAnchor(accuracy: 30, age: 31))
        #expect(!AnchorRules.isUsableAnchor(accuracy: 150, age: 1))
        #expect(!AnchorRules.isUsableAnchor(accuracy: -1, age: 1))
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
        #expect(SessionConfig(studyMinutes: 45, radiusMeters: 25, grayscale: false, library: true).isLibrary)
    }
}

// MARK: - Permission gate

@Suite("Permission gate")
struct PermissionGateTests {
    @Test("location and Motion & Fitness are both required; notifications are not")
    func required() {
        #expect(PermissionGate.isReady(location: true, motion: true, motionSupported: true))
        #expect(!PermissionGate.isReady(location: true, motion: false, motionSupported: true))
        #expect(!PermissionGate.isReady(location: false, motion: true, motionSupported: true))
    }

    @Test("a phone without a pedometer is not locked out")
    func unsupported() {
        #expect(PermissionGate.isReady(location: true, motion: false, motionSupported: false))
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
        #expect(SessionConfig(studyMinutes: 45, radiusMeters: 25, grayscale: false, grace: 30).graceSeconds == 30)
    }
}

// MARK: - Live Activity states

@Suite("Live Activity")
struct LiveActivityStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var session: Session {
        Session.start(config: SessionConfig(studyMinutes: 25, radiusMeters: 25, grayscale: false),
                      anchor: GeoPoint(lat: 34, lng: -118), anchorAccuracy: 10, at: t0)
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

@Suite("Zones")
struct ZoneTests {
    private let origin = GeoPoint(lat: 34.0218, lng: -118.2830)
    private var square: [GeoPoint] { [(-50, -50), (50, -50), (50, 50), (-50, 50)].map { offset(origin, $0.0, $0.1) } }
    /// An L: the top-right corner is cut out.
    private var ell: [GeoPoint] { [(0, 0), (100, 0), (100, 40), (40, 40), (40, 100), (0, 100)].map { offset(origin, $0.0, $0.1) } }

    @Test("a point is inside a square zone, or not")
    func insideSquare() {
        #expect(ZoneGeometry.contains(offset(origin, 0, 0), in: square))
        #expect(ZoneGeometry.contains(offset(origin, 49, 49), in: square))
        #expect(!ZoneGeometry.contains(offset(origin, 60, 0), in: square))
        #expect(!ZoneGeometry.contains(offset(origin, 0, -51), in: square))
    }

    @Test("concave outlines work: the notch of an L is outside")
    func concave() {
        #expect(ZoneGeometry.contains(offset(origin, 20, 80), in: ell))
        #expect(ZoneGeometry.contains(offset(origin, 70, 20), in: ell))
        #expect(!ZoneGeometry.contains(offset(origin, 70, 70), in: ell))
    }

    @Test("depth is meters to the nearest edge: positive inside, negative outside")
    func depth() {
        #expect(abs(ZoneGeometry.depth(of: offset(origin, 0, 0), in: square) - 50) < 0.5)
        #expect(abs(ZoneGeometry.depth(of: offset(origin, 45, 0), in: square) - 5) < 0.5)
        #expect(abs(ZoneGeometry.depth(of: offset(origin, 60, 0), in: square) + 10) < 0.5)
        #expect(abs(ZoneGeometry.depth(of: offset(origin, 70, 70), in: ell) + 30) < 0.5)
    }

    @Test("a dropped anchor is a circle zone of the chosen radius")
    func circle() {
        let zone = Zone.circle(center: origin, radius: 25)
        #expect(abs(zone.depth(of: origin) - 25) < 0.5)
        #expect(abs(zone.depth(of: offset(origin, 30, 0)) + 5) < 0.5)
    }

    @Test("the wake circle iOS watches covers the whole zone, and is at least 100 m")
    func wakeCircle() {
        let zone = Zone(id: "sq", name: "Square", polygon: square)
        #expect(zone.wakeRadiusMeters >= 100)
        #expect(square.allSatisfy { Geo.distanceMeters(zone.center, $0) < zone.wakeRadiusMeters })
    }

    @Test("Leavey Library ships in zones.json, and its outline holds the building")
    func leavey() throws {
        let url = try #require(Bundle.main.url(forResource: "zones", withExtension: "json"))
        let zones = try ZoneCatalog.decode(Data(contentsOf: url))
        let leavey = try #require(zones.first { $0.id == "usc-leavey-library" })
        #expect(leavey.polygon.count >= 10)
        #expect(leavey.contains(GeoPoint(lat: 34.02175, lng: -118.28290)))
        #expect(!leavey.contains(GeoPoint(lat: 34.02300, lng: -118.28290)))
    }

    @Test("zones.json with no zones or a broken outline is refused")
    func badCatalog() {
        #expect(throws: ZoneCatalog.Problem.self) { try ZoneCatalog.decode(Data(#"{"version":1,"zones":[{"id":"x","name":"X","polygon":[[34,-118],[34.1,-118]]}]}"#.utf8)) }
    }
}

// MARK: - Presence

@Suite("Presence")
struct PresenceTests {
    private let origin = GeoPoint(lat: 34.0218, lng: -118.2830)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func fix(_ east: Double, _ north: Double, acc: Double, at seconds: Double) -> LocationFix {
        LocationFix(point: offset(origin, east, north), accuracy: acc, time: t0.addingTimeInterval(seconds))
    }
    private func east(of p: GeoPoint) -> Double { (p.lng - origin.lng) * .pi / 180 * Geo.earthRadiusMeters * cos(origin.lat * .pi / 180) }

    @Test("fixes worse than 65 m are thrown away")
    func dropsBad() {
        #expect(PresenceFilter().adding(fix(0, 0, acc: 80, at: 0)).smoothed == nil)
        #expect(PresenceFilter().adding(fix(0, 0, acc: -1, at: 0)).smoothed == nil)
    }

    @Test("recent fixes are averaged, the sharper ones counting more")
    func averages() throws {
        let even = PresenceFilter().adding(fix(0, 0, acc: 10, at: 0)).adding(fix(10, 0, acc: 10, at: 1))
        #expect(abs(east(of: try #require(even.smoothed).point) - 5) < 0.2)
        let weighted = PresenceFilter().adding(fix(0, 0, acc: 5, at: 0)).adding(fix(20, 0, acc: 20, at: 1))
        #expect(abs(east(of: try #require(weighted.smoothed).point) - 1.18) < 0.2)
    }

    @Test("fixes older than 30 s fall out of the average")
    func window() throws {
        let f = PresenceFilter().adding(fix(0, 0, acc: 10, at: 0)).adding(fix(20, 0, acc: 10, at: 31))
        #expect(abs(east(of: try #require(f.smoothed).point) - 20) < 0.2)
    }

    @Test("a sudden jump no one could walk is rejected as a GPS blunder")
    func blunder() throws {
        let f = PresenceFilter()
            .adding(fix(0, 0, acc: 10, at: 0)).adding(fix(0, 0, acc: 10, at: 1)).adding(fix(0, 0, acc: 10, at: 2))
            .adding(fix(200, 0, acc: 15, at: 3))
        #expect(abs(east(of: try #require(f.smoothed).point)) < 0.5)
    }

    @Test("leaving needs to be clearly outside, past the GPS accuracy, for 15 s")
    func leaves() {
        let a = ZonePresence.inside.updated(depth: -20, accuracy: 10, isStationary: false, at: t0)
        #expect(a.state == .inside)
        #expect(a.updated(depth: -20, accuracy: 10, isStationary: false, at: t0.addingTimeInterval(16)).state == .outside)
    }

    @Test("near the edge, inside the GPS slack, you stay in")
    func edgeSlack() {
        var p = ZonePresence.inside
        for s in stride(from: 0.0, through: 60, by: 1) {
            p = p.updated(depth: -10, accuracy: 25, isStationary: false, at: t0.addingTimeInterval(s))
        }
        #expect(p.state == .inside)
    }

    @Test("sitting still, GPS drift can never take you out")
    func stationaryDrift() {
        var p = ZonePresence.inside
        for s in stride(from: 0.0, through: 120, by: 1) {
            p = p.updated(depth: -30, accuracy: 20, isStationary: true, at: t0.addingTimeInterval(s))
        }
        #expect(p.state == .inside)
    }

    @Test("a brief dip outside starts the 15 s over")
    func briefDip() {
        let p = ZonePresence.inside
            .updated(depth: -20, accuracy: 10, isStationary: false, at: t0)
            .updated(depth: 3, accuracy: 10, isStationary: false, at: t0.addingTimeInterval(5))
            .updated(depth: -20, accuracy: 10, isStationary: false, at: t0.addingTimeInterval(10))
            .updated(depth: -20, accuracy: 10, isStationary: false, at: t0.addingTimeInterval(20))
        #expect(p.state == .inside)
    }

    @Test("walking back in counts after 5 s inside")
    func returns() {
        let out = ZonePresence(state: .outside, pendingSince: nil)
        let a = out.updated(depth: 5, accuracy: 10, isStationary: false, at: t0)
        #expect(a.state == .outside)
        #expect(a.updated(depth: 5, accuracy: 10, isStationary: false, at: t0.addingTimeInterval(6)).state == .inside)
    }
}

// MARK: - Zone review fixes

@Suite("Zone review fixes")
struct ZoneReviewTests {
    private let origin = GeoPoint(lat: 34.0218, lng: -118.2830)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func fix(_ east: Double, acc: Double = 10, at seconds: Double) -> LocationFix {
        LocationFix(point: offset(origin, east, 0), accuracy: acc, time: t0.addingTimeInterval(seconds))
    }

    @Test("a reading older than 15 s decides nothing")
    func stale() {
        let f = PresenceFilter().adding(fix(0, at: 0))
        #expect(f.smoothed(at: t0.addingTimeInterval(10)) != nil)
        #expect(f.smoothed(at: t0.addingTimeInterval(16)) == nil)
    }

    @Test("a reading that arrives out of order is ignored, not allowed to wipe the window")
    func outOfOrder() {
        let f = PresenceFilter().adding(fix(0, at: 10)).adding(fix(0, at: 11)).adding(fix(0, at: 5))
        #expect(f.fixes.count == 2)
    }

    @Test("walking steadily is never mistaken for a GPS jump")
    func walkingAccepted() {
        var f = PresenceFilter()
        for s in 0..<40 { f = f.adding(fix(Double(s) * 1.5, acc: 5, at: Double(s))) }
        #expect(f.fixes.last?.time == t0.addingTimeInterval(39))
        #expect(f.fixes.count >= 30)
    }

    @Test("zones with impossible coordinates are refused")
    func badCoordinates() {
        #expect(throws: ZoneCatalog.Problem.self) {
            try ZoneCatalog.decode(Data(#"{"version":1,"zones":[{"id":"x","name":"X","polygon":[[134,-118],[34.1,-118],[34.1,-118.1]]}]}"#.utf8))
        }
    }
}
