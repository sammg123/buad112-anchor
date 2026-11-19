import Foundation
import Testing
@testable import Anchor

// MARK: - Fixtures

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let usc = GeoPoint(lat: 34.0224, lng: -118.2851)

private func config(minutes: Int = 25, tuition: Double = 27_000) -> SessionConfig {
    SessionConfig(courseName: "BUAD 112", studyMinutes: minutes, tuitionPerYear: tuition, grayscale: false)
}

private func fresh(minutes: Int = 25, tuition: Double = 27_000) -> Session {
    Session.start(config: config(minutes: minutes, tuition: tuition), anchor: usc, anchorAccuracy: 10, at: t0)
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

    @Test("unlock distance is the radius plus the worse accuracy, capped at 50 m")
    func unlockDistance() {
        #expect(AnchorRules.unlockDistance(anchorAccuracy: 10, fixAccuracy: 20) == 70)
        #expect(AnchorRules.unlockDistance(anchorAccuracy: 400, fixAccuracy: 5) == 100)
        #expect(AnchorRules.unlockDistance(anchorAccuracy: -1, fixAccuracy: -1) == 50)
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

    @Test("tuition cost is phone minutes times tuition per class minute")
    func cost() {
        // $27,000 a year / 27,000 class minutes = $1 a minute
        let s = fresh(tuition: 27_000).settingPhone(true, at: t0).advanced(to: t0.addingTimeInterval(90))
        #expect(abs(s.costDollars - 1.5) < 0.0001)
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
    @Test("one step every 15 seconds on the phone")
    func levels() {
        #expect(Ladder.level(phoneSeconds: 0) == 0)
        #expect(Ladder.level(phoneSeconds: 14.9) == 0)
        #expect(Ladder.level(phoneSeconds: 15) == 1)
        #expect(Ladder.level(phoneSeconds: 61) == 4)
    }

    @Test("buzzes are scheduled at the next step boundaries from where the phone clock is")
    func schedule() {
        let buzzes = Ladder.buzzes(phoneSeconds: 47, tuitionPerYear: 27_000, limit: 3)
        #expect(buzzes.map(\.delay) == [13, 28, 43])
        #expect(buzzes.map(\.level) == [4, 5, 6])
    }

    @Test("the first buzz comes right away on a fresh pickup")
    func firstBuzzImmediate() {
        let buzzes = Ladder.buzzes(phoneSeconds: 0, tuitionPerYear: 27_000, limit: 2)
        #expect(buzzes.first?.delay == Ladder.firstBuzzDelay)
        #expect(Ladder.firstBuzzDelay > Ladder.lockLagSeconds)
        #expect(buzzes.first?.level == 1)
    }

    @Test("a later pickup is never buzzed sooner than one step in, so a quick lock never buzzes")
    func laterPickupWaitsOneStep() {
        let buzzes = Ladder.buzzes(phoneSeconds: 14, stintSeconds: 0, tuitionPerYear: 0, limit: 3)
        #expect(buzzes.first!.delay >= Ladder.firstBuzzDelay)
        #expect(buzzes.map(\.level) == [2, 3, 4])
        #expect(buzzes.map(\.delay) == [16, 31, 46])
    }

    @Test("mid-pickup the ladder keeps its step boundaries")
    func midStintKeepsBoundaries() {
        let buzzes = Ladder.buzzes(phoneSeconds: 47, stintSeconds: 20, tuitionPerYear: 0, limit: 2)
        #expect(buzzes.map(\.delay) == [13, 28])
    }

    @Test("buzz text names the phone time and the tuition it cost")
    func buzzText() {
        let b = Ladder.buzzes(phoneSeconds: 59, tuitionPerYear: 27_000, limit: 1)[0]
        #expect(b.body.contains("1:00"))
        #expect(b.body.contains("$1.00"))
        #expect(!b.title.isEmpty)
    }

    @Test("never schedules more than iOS allows")
    func limitRespected() {
        #expect(Ladder.buzzes(phoneSeconds: 0, tuitionPerYear: 0, limit: 500).count == Ladder.maxPending)
    }

    @Test("every step has its own line; past the last one the top line repeats")
    func linesEscalate() {
        let lines = (0..<20).map { Ladder.line(level: $0).title }
        #expect(Set(lines.prefix(Ladder.lineCount)).count == Ladder.lineCount)
        #expect(lines[19] == lines[Ladder.lineCount - 1])
    }
}

// MARK: - Formatting and grade

@Suite("Format")
struct FormatTests {
    @Test("clock formats minutes and seconds, hours when needed")
    func clock() {
        #expect(Format.clock(0) == "0:00")
        #expect(Format.clock(65.9) == "1:05")
        #expect(Format.clock(3_725) == "1:02:05")
        #expect(Format.clock(-4) == "0:00")
    }

    @Test("money has two decimals and thousands separators")
    func money() {
        #expect(Format.money(1.5) == "$1.50")
        #expect(Format.money(1234.5) == "$1,234.50")
    }

    @Test("grade drops as the share of phone time rises")
    func grade() {
        #expect(Grade.letter(studied: 1500, phone: 0) == "A+")
        #expect(Grade.letter(studied: 1500, phone: 60) == "A")
        #expect(Grade.letter(studied: 1500, phone: 300) == "C")
        #expect(Grade.letter(studied: 600, phone: 600) == "F")
        #expect(Grade.letter(studied: 0, phone: 0) == "—")
    }
}

// MARK: - Setup validation

@Suite("Setup")
struct SetupTests {
    @Test("study minutes and tuition are parsed and clamped")
    func parse() {
        #expect(SetupInput.minutes("25") == 25)
        #expect(SetupInput.minutes("0") == nil)
        #expect(SetupInput.minutes("241") == nil)
        #expect(SetupInput.minutes("abc") == nil)
        #expect(SetupInput.tuition("$68,000") == 68_000)
        #expect(SetupInput.tuition("") == 0)
        #expect(SetupInput.tuition("9999999") == nil)
    }

    @Test("course name is trimmed and falls back to a default")
    func course() {
        #expect(SetupInput.course("  ") == "BUAD 112")
        #expect(SetupInput.course(" Econ 203 ") == "Econ 203")
        #expect(SetupInput.course(String(repeating: "x", count: 60)).count == 40)
    }
}
