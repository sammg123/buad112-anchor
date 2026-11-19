import Foundation

/// What the student chose on the cover before starting.
struct SessionConfig: Codable, Equatable, Sendable {
    let studyMinutes: Int
    /// Stop stays locked inside this circle (25 m at least), plus GPS slack.
    let radiusMeters: Double
    /// Run the "Anchor Gray" shortcut at the start and "Anchor Color" at the end.
    let grayscale: Bool
}

/// One study session. A value: every change returns a new Session.
///
/// Three clocks, and only one moves at a time:
/// - study: at the anchor and off the phone,
/// - phone: at the anchor and on the phone (it never resets during a session),
/// - away: past the Stop unlock distance; the phone is free there and nothing else counts.
struct Session: Codable, Equatable, Sendable {
    let config: SessionConfig
    let anchor: GeoPoint
    let anchorAccuracy: Double
    let startedAt: Date
    let lastTick: Date
    let studiedSeconds: Double
    let phoneSeconds: Double
    /// Phone time in the current pickup only.
    let stintSeconds: Double
    let longestStintSeconds: Double
    let awaySeconds: Double
    let onPhone: Bool
    let away: Bool
    let pickups: Int
    let finishedAt: Date?

    static func start(config: SessionConfig, anchor: GeoPoint, anchorAccuracy: Double, at now: Date) -> Session {
        Session(config: config, anchor: anchor, anchorAccuracy: anchorAccuracy, startedAt: now, lastTick: now,
                studiedSeconds: 0, phoneSeconds: 0, stintSeconds: 0, longestStintSeconds: 0, awaySeconds: 0, onPhone: false, away: false, pickups: 0,
                finishedAt: nil)
    }

    var targetSeconds: Double { Double(config.studyMinutes) * 60 }
    var remainingSeconds: Double { max(0, targetSeconds - studiedSeconds) }
    var isComplete: Bool { finishedAt != nil }
    /// The phone clock (and the buzzing) only runs at the anchor.
    var isOnPhoneCounting: Bool { onPhone && !away && !isComplete }
    var isStudying: Bool { !onPhone && !away && !isComplete }

    /// Move the clocks up to `now`. A finished session never changes.
    func advanced(to now: Date) -> Session {
        guard !isComplete else { return self }
        let dt = max(0, now.timeIntervalSince(lastTick))
        let tickTime = max(now, lastTick)
        if isStudying, studiedSeconds + dt >= targetSeconds {
            let needed = targetSeconds - studiedSeconds
            let doneAt = lastTick.addingTimeInterval(needed)
            return copy(lastTick: doneAt, studiedSeconds: targetSeconds, finishedAt: .some(doneAt))
        }
        return copy(
            lastTick: tickTime,
            studiedSeconds: studiedSeconds + (isStudying ? dt : 0),
            phoneSeconds: phoneSeconds + (isOnPhoneCounting ? dt : 0),
            stintSeconds: stintSeconds + (isOnPhoneCounting ? dt : 0),
            longestStintSeconds: max(longestStintSeconds, stintSeconds + (isOnPhoneCounting ? dt : 0)),
            awaySeconds: awaySeconds + (away ? dt : 0)
        )
    }

    func settingPhone(_ value: Bool, at now: Date) -> Session {
        let current = advanced(to: now)
        guard !current.isComplete, current.onPhone != value else { return current }
        let isPickup = value && !current.away
        return current.copy(
            stintSeconds: value ? 0 : current.stintSeconds,
            onPhone: value,
            pickups: current.pickups + (isPickup ? 1 : 0)
        )
    }

    /// The phone was locked `unseenSeconds` before iOS said so. Those seconds of this pickup go back to the
    /// study timer, and a pickup that fits entirely inside them (locking with Anchor open) is not a pickup.
    func lockedPhone(at now: Date, unseenSeconds: Double) -> Session {
        let current = advanced(to: now)
        guard !current.isComplete, current.onPhone else { return current }
        let refund = min(max(0, unseenSeconds), current.stintSeconds, current.remainingSeconds)
        let wasLag = current.stintSeconds > 0 && current.stintSeconds <= unseenSeconds
        return current.copy(
            studiedSeconds: current.studiedSeconds + refund,
            phoneSeconds: current.phoneSeconds - refund,
            stintSeconds: 0,
            longestStintSeconds: current.longestStintSeconds == current.stintSeconds
                ? current.stintSeconds - refund : current.longestStintSeconds,
            onPhone: false,
            pickups: current.pickups - (wasLag ? 1 : 0)
        )
    }

    func settingAway(_ value: Bool, at now: Date) -> Session {
        let current = advanced(to: now)
        guard !current.isComplete, current.away != value else { return current }
        return current.copy(away: value)
    }

    /// When the timer will hit zero if nothing changes, or nil while the study clock is stopped.
    func projectedFinish(from now: Date) -> Date? {
        let current = advanced(to: now)
        guard current.isStudying else { return nil }
        return now.addingTimeInterval(current.remainingSeconds)
    }

    private func copy(
        lastTick: Date? = nil,
        studiedSeconds: Double? = nil,
        phoneSeconds: Double? = nil,
        stintSeconds: Double? = nil,
        longestStintSeconds: Double? = nil,
        awaySeconds: Double? = nil,
        onPhone: Bool? = nil,
        away: Bool? = nil,
        pickups: Int? = nil,
        finishedAt: Date?? = nil
    ) -> Session {
        Session(
            config: config, anchor: anchor, anchorAccuracy: anchorAccuracy, startedAt: startedAt,
            lastTick: lastTick ?? self.lastTick,
            studiedSeconds: studiedSeconds ?? self.studiedSeconds,
            phoneSeconds: phoneSeconds ?? self.phoneSeconds,
            stintSeconds: stintSeconds ?? self.stintSeconds,
            longestStintSeconds: longestStintSeconds ?? self.longestStintSeconds,
            awaySeconds: awaySeconds ?? self.awaySeconds,
            onPhone: onPhone ?? self.onPhone,
            away: away ?? self.away,
            pickups: pickups ?? self.pickups,
            finishedAt: finishedAt ?? self.finishedAt
        )
    }
}
