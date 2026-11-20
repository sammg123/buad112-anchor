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
    /// The grace period and the instant screen-off notice already keep a quick lock from buzzing, so once a
    /// pickup counts the ladder carries on from where the phone clock left off.
    static let minFirstDelaySeconds = 0.0

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
    /// The siren starts at 1:00 of phone time (Sam, 11-20).
    static let alarmAfterSeconds = 60.0
    /// Nonstop vibration starts at 0:30 of phone time (Sam, 11-20).
    static let vibrateAfterSeconds = 30.0

    static func isContinuousVibration(phoneSeconds: Double) -> Bool {
        phoneSeconds >= vibrateAfterSeconds
    }

    /// The grace period only lasts until you've used up a minute of phone time (Sam, 11-20: "anytime after a
    /// minute of screen time the sirens and the vibrations should be continuously going off"). From then on every
    /// unlock outside Anchor counts at once, so the siren and nonstop vibration start the instant you pick it up.
    static func graceSeconds(configured: Double, phoneSeconds: Double) -> Double {
        phoneSeconds >= alarmAfterSeconds ? 0 : configured
    }

    /// One row of the annoyance list in Settings. `startsAt` is phone time after the grace period.
    struct Annoyance: Equatable, Sendable, Identifiable {
        let startsAt: Double
        let title: String
        let detail: String
        let symbol: String
        let isSound: Bool
        var id: String { title }
    }

    /// Every annoyance in the order it kicks in, from the same constants the session uses.
    static func annoyances(graceSeconds: Double, library: Bool) -> [Annoyance] {
        let all = [
            Annoyance(startsAt: 0, title: "Island turns red",
                      detail: "After your \(Int(graceSeconds)) s grace, the study clock stops and you get one buzz.",
                      symbol: "circle.fill", isSound: false),
            Annoyance(startsAt: Ladder.slowStepSeconds, title: "Notification every 15 s",
                      detail: "Your phone time in a banner, with a vibration.", symbol: "bell.badge.fill", isSound: false),
            Annoyance(startsAt: vibrateAfterSeconds, title: "Nonstop vibration",
                      detail: "The phone vibrates without a break until you lock it.", symbol: "iphone.radiowaves.left.and.right",
                      isSound: false),
            Annoyance(startsAt: voiceEverySeconds, title: "A voice reads your phone time",
                      detail: "Out loud, over whatever is playing, even on silent.", symbol: "speaker.wave.3.fill", isSound: true),
            Annoyance(startsAt: alarmAfterSeconds, title: "Siren, and no more grace",
                      detail: "Loops until you lock the phone or open Anchor. From here on, every unlock sirens and vibrates instantly.",
                      symbol: "light.beacon.max.fill", isSound: true),
            Annoyance(startsAt: Ladder.fastAfterSeconds, title: "Notification every 5 s",
                      detail: "Three times as often.", symbol: "bell.and.waves.left.and.right.fill", isSound: false)
        ]
        return all.filter { !(library && $0.isSound) }.sorted { $0.startsAt < $1.startsAt }
    }

    /// The 30 s mark the phone clock crossed between two readings, if any, before the alarm takes over.
    static func voiceMark(from previous: Double, to current: Double) -> Double? {
        guard current > previous else { return nil }
        let mark = (current / voiceEverySeconds).rounded(.down) * voiceEverySeconds
        guard mark > 0, mark > previous, mark < alarmAfterSeconds else { return nil }
        return mark
    }

    /// Sound starts the moment a pickup counts (after the grace period), the same rule the buzzes follow.
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

/// The volume floor during a session (outside library mode): 3 of the 16 volume notches.
enum VolumeRule {
    static let floor: Float = 3.0 / 16

    /// The volume to force back to, or nil when the current one is fine.
    static func corrected(_ volume: Float) -> Float? {
        volume < floor - 0.001 ? floor : nil
    }
}
