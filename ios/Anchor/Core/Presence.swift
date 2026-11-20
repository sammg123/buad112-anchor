import Foundation

/// One location reading.
struct LocationFix: Equatable, Sendable {
    let point: GeoPoint
    /// Meters, as Core Location reports it (negative means invalid).
    let accuracy: Double
    let time: Date
}

/// Cleans up GPS the way location-sharing apps do: readings worse than 65 m are dropped, a jump nobody could walk
/// is rejected as a blunder, and the last 30 s are averaged with sharper readings counting more.
struct PresenceFilter: Equatable, Sendable {
    static let maxAccuracyMeters = 65.0
    static let windowSeconds = 30.0
    /// A new reading farther than this many accuracies (plus walking speed) from the average is a blunder.
    static let blunderFactor = 3.0
    static let maxWalkingSpeed = 3.0

    let fixes: [LocationFix]

    init(fixes: [LocationFix] = []) {
        self.fixes = fixes
    }

    func adding(_ fix: LocationFix) -> PresenceFilter {
        let recent = fixes.filter { $0.time <= fix.time && fix.time.timeIntervalSince($0.time) <= Self.windowSeconds }
        guard fix.accuracy >= 0, fix.accuracy <= Self.maxAccuracyMeters else { return PresenceFilter(fixes: recent) }
        if let average = Self.average(recent), let latest = recent.last {
            let jump = Geo.distanceMeters(average.point, fix.point)
            let allowed = Self.blunderFactor * max(fix.accuracy, average.accuracy)
                + Self.maxWalkingSpeed * fix.time.timeIntervalSince(latest.time)
            if jump > allowed { return PresenceFilter(fixes: recent) }
        }
        return PresenceFilter(fixes: recent + [fix])
    }

    /// The cleaned-up position, or nil with nothing usable yet.
    var smoothed: LocationFix? { Self.average(fixes) }

    /// Inverse-variance weighted average; the accuracy reported is the weighted average accuracy (conservative).
    private static func average(_ fixes: [LocationFix]) -> LocationFix? {
        guard let last = fixes.last else { return nil }
        let weights = fixes.map { 1 / max($0.accuracy * $0.accuracy, 1) }
        let total = weights.reduce(0, +)
        let lat = zip(fixes, weights).reduce(0) { $0 + $1.0.point.lat * $1.1 } / total
        let lng = zip(fixes, weights).reduce(0) { $0 + $1.0.point.lng * $1.1 } / total
        let accuracy = zip(fixes, weights).reduce(0) { $0 + $1.0.accuracy * $1.1 } / total
        return LocationFix(point: GeoPoint(lat: lat, lng: lng), accuracy: accuracy, time: last.time)
    }
}

/// Inside or outside the session's zone, with slack so the edge doesn't flicker:
/// - leaving takes being outside by more than the GPS accuracy (at least 15 m) for 15 s, and never starts while
///   the phone is sitting still (that is GPS drift, not walking);
/// - coming back takes being inside (or within a little slack of the edge) for 5 s.
struct ZonePresence: Equatable, Sendable {
    enum State: Equatable, Sendable { case inside, outside }

    static let leaveDwellSeconds = 15.0
    static let enterDwellSeconds = 5.0
    static let minLeaveMarginMeters = 15.0
    static let enterSlackMeters = 10.0

    let state: State
    /// When the change in progress started, if one is.
    let pendingSince: Date?

    static let inside = ZonePresence(state: .inside, pendingSince: nil)

    /// `depth` is meters to the zone's edge: positive inside, negative outside.
    func updated(depth: Double, accuracy: Double, isStationary: Bool, at now: Date) -> ZonePresence {
        switch state {
        case .inside:
            let clearlyOutside = depth <= -max(Self.minLeaveMarginMeters, accuracy)
            guard clearlyOutside, pendingSince != nil || !isStationary else { return .inside }
            let since = pendingSince ?? now
            return now.timeIntervalSince(since) >= Self.leaveDwellSeconds
                ? ZonePresence(state: .outside, pendingSince: nil)
                : ZonePresence(state: .inside, pendingSince: since)
        case .outside:
            let backInside = depth >= -min(accuracy * 0.5, Self.enterSlackMeters)
            guard backInside else { return ZonePresence(state: .outside, pendingSince: nil) }
            let since = pendingSince ?? now
            return now.timeIntervalSince(since) >= Self.enterDwellSeconds
                ? .inside
                : ZonePresence(state: .outside, pendingSince: since)
        }
    }
}
