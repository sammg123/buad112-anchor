import Foundation

/// The annoyance ladder: one step every 15 seconds on the phone at the anchor, each step a buzz.
enum Ladder {
    static let stepSeconds = 15.0
    /// iOS keeps at most 64 pending local notifications per app; a few are left for the done and away notices.
    static let maxPending = 60
    /// iOS reports a lock about this long after it happens (the data protection grace period).
    static let lockLagSeconds = 10.0
    /// A fresh pickup is first buzzed one step in, after the lock lag, so locking with Anchor open never buzzes.
    static var firstBuzzDelay: Double { stepSeconds }

    struct Buzz: Equatable, Sendable {
        let delay: TimeInterval
        let level: Int
        let title: String
        let body: String
    }

    struct Line: Sendable {
        let title: String
        let body: String
    }

    static func level(phoneSeconds: Double) -> Int {
        Int((max(0, phoneSeconds) / stepSeconds).rounded(.down))
    }

    /// Blunt about the phone, never cruel about the person. Every buzz adds the phone time and what it cost.
    private static let lines: [Line] = [
        Line(title: "Anchor sees you", body: "You're on your phone at your study spot."),
        Line(title: "Still on your phone", body: "Lock it and the buzzing stops."),
        Line(title: "Your notes miss you", body: "The study timer is frozen while you scroll."),
        Line(title: "Your exam is not on TikTok", body: "That's class you paid for."),
        Line(title: "Bzzt", body: "Lock the phone and this all stops."),
        Line(title: "Still here. Still buzzing.", body: "Every 15 seconds until you put it down."),
        Line(title: "That's real tuition", body: "Scrolled away, 15 seconds at a time."),
        Line(title: "Your group chat can wait", body: "Your study timer can't. It's frozen."),
        Line(title: "Bzzt. Bzzt.", body: "Want it to stop? Lock the phone or walk 50 m away."),
        Line(title: "This is the annoying part", body: "It does not get less annoying."),
        Line(title: "Put. It. Down.", body: "You chose this spot to study. So study."),
        Line(title: "Anchor is not going away", body: "Lock the phone.")
    ]

    static var lineCount: Int { lines.count }

    static func line(level: Int) -> Line {
        lines[min(max(0, level), lines.count - 1)]
    }

    /// The buzzes to schedule from where the phone clock is now, at each upcoming step. A step that would land
    /// sooner than one step into this pickup is skipped, so locking right away never buzzes.
    static func buzzes(phoneSeconds: Double, stintSeconds: Double = .greatestFiniteMagnitude, tuitionPerYear: Double, limit: Int) -> [Buzz] {
        let count = min(max(0, limit), maxPending)
        let start = max(0, phoneSeconds)
        let earliest = max(0, firstBuzzDelay - max(0, stintSeconds))
        let next = level(phoneSeconds: start) + 1
        let firstLevel = Double(next) * stepSeconds - start < earliest ? next + 1 : next
        return (0..<count).map { i in
            let lvl = firstLevel + i
            let at = Double(lvl) * stepSeconds
            let delay = at - start
            let cost = at / 60 * tuitionPerYear / Session.classMinutesPerYear
            let template = line(level: lvl)
            let stats = "\(Format.clock(at)) on your phone · \(Format.money(cost)) of tuition"
            return Buzz(delay: delay, level: lvl, title: template.title, body: template.body + "\n" + stats)
        }
    }
}
