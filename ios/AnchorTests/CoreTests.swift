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

    @Test("a new pickup is never buzzed before the lock lag has passed, so a quick lock never buzzes")
    func newPickupWaits() {
        let buzzes = Ladder.buzzes(phoneSeconds: 62, stintSeconds: 0, limit: 3)
        #expect(buzzes.first!.delay > Ladder.lockLagSeconds)
        #expect(buzzes.map(\.delay) == [13, 18, 23])
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
        #expect(Escalation.voiceMark(from: 59.5, to: 60.5) == 60)
        #expect(Escalation.voiceMark(from: 0, to: 20) == nil)
    }

    @Test("the voice goes quiet once the alarm takes over")
    func voiceStopsAtAlarm() {
        #expect(Escalation.voiceMark(from: 119, to: 121) == nil)
        #expect(Escalation.voiceMark(from: 89, to: 91) == 90)
    }

    @Test("the alarm runs from 2:00 on the phone")
    func alarm() {
        #expect(!Escalation.isAlarm(phoneSeconds: 119))
        #expect(Escalation.isAlarm(phoneSeconds: 120))
    }

    @Test("voice and alarm wait out the lock lag of each pickup, so locking the phone never sets them off")
    func armedAfterLockLag() {
        #expect(!Escalation.isArmed(stintSeconds: 0))
        #expect(!Escalation.isArmed(stintSeconds: Ladder.lockLagSeconds))
        #expect(Escalation.isArmed(stintSeconds: Ladder.minFirstDelaySeconds))
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
