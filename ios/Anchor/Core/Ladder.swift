import Foundation

/// The buzz schedule on the phone clock: every 15 s for the first minute, then every 5 s.
enum Ladder {
    static let slowStepSeconds = 15.0
    static let fastStepSeconds = 5.0
    static let fastAfterSeconds = 60.0
    /// iOS keeps at most 64 pending local notifications per app; a few are left for the done and away notices.
    static let maxPending = 60
    /// iOS reports a lock about this long after it happens (the data protection grace period).
    static let lockLagSeconds = 10.0
    /// A new pickup is never buzzed sooner than this, so locking right away (or locking with Anchor open)
    /// never buzzes.
    static let minFirstDelaySeconds = 12.0

    struct Buzz: Equatable, Sendable {
        let delay: TimeInterval
        let index: Int
        let title: String
        let body: String
    }

    /// The n-th buzz time on the phone clock (n from 1).
    static func time(ofBuzz n: Int) -> Double {
        let slowCount = Int(fastAfterSeconds / slowStepSeconds)
        if n <= slowCount { return Double(n) * slowStepSeconds }
        return fastAfterSeconds + Double(n - slowCount) * fastStepSeconds
    }

    /// How many buzz times the phone clock has reached.
    static func buzzCount(phoneSeconds: Double) -> Int {
        let s = max(0, phoneSeconds)
        if s < fastAfterSeconds { return Int((s / slowStepSeconds).rounded(.down)) }
        return Int(fastAfterSeconds / slowStepSeconds) + Int(((s - fastAfterSeconds) / fastStepSeconds).rounded(.down))
    }

    /// The next `limit` buzz times strictly after `phoneSeconds`.
    static func times(after phoneSeconds: Double, limit: Int) -> [Double] {
        let first = buzzCount(phoneSeconds: phoneSeconds) + 1
        return (0..<max(0, limit)).map { time(ofBuzz: first + $0) }
    }

    private static let lines = [
        "Lock it and the buzzing stops.",
        "The study timer is frozen while you scroll.",
        "This keeps going until you put it down.",
        "Want it to stop? Lock the phone or walk away.",
        "Your notes miss you.",
        "It only gets faster from here."
    ]

    /// The buzzes to schedule from where the phone clock is now. Buzz times sooner than the lock lag into this
    /// pickup are skipped.
    static func buzzes(phoneSeconds: Double, stintSeconds: Double, limit: Int) -> [Buzz] {
        let start = max(0, phoneSeconds)
        let earliest = start + max(0, minFirstDelaySeconds - max(0, stintSeconds))
        let count = min(max(0, limit), maxPending)
        let candidates = times(after: start, limit: count + 4).filter { $0 >= earliest }
        return candidates.prefix(count).map { at in
            let index = buzzCount(phoneSeconds: at)
            return Buzz(delay: at - start, index: index, title: "\(Format.clock(at)) on your phone",
                        body: lines[(index - 1 + lines.count) % lines.count])
        }
    }
}

/// What happens beyond the buzzes: a voice every 30 s, then an alarm from 2:00.
enum Escalation {
    static let voiceEverySeconds = 30.0
    static let alarmAfterSeconds = 120.0

    /// The 30 s mark the phone clock crossed between two readings, if any, before the alarm takes over.
    static func voiceMark(from previous: Double, to current: Double) -> Double? {
        guard current > previous else { return nil }
        let mark = (current / voiceEverySeconds).rounded(.down) * voiceEverySeconds
        guard mark > 0, mark > previous, mark < alarmAfterSeconds else { return nil }
        return mark
    }

    /// Sound only starts once a pickup has outlasted the lock lag, the same rule the buzzes follow.
    static func isArmed(stintSeconds: Double) -> Bool {
        stintSeconds >= Ladder.minFirstDelaySeconds
    }

    static func isAlarm(phoneSeconds: Double) -> Bool {
        phoneSeconds >= alarmAfterSeconds
    }

    static func spokenLine(seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let m = total / 60, s = total % 60
        let parts = [
            m > 0 ? "\(m) minute\(m == 1 ? "" : "s")" : nil,
            s > 0 ? "\(s) second\(s == 1 ? "" : "s")" : nil
        ].compactMap { $0 }
        return "\(parts.joined(separator: " ")) on your phone. Put it down."
    }
}
