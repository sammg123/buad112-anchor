import Foundation

/// A point on Earth in degrees.
struct GeoPoint: Codable, Equatable, Sendable {
    let lat: Double
    let lng: Double
}

enum Geo {
    static let earthRadiusMeters = 6_371_008.8

    /// Great-circle distance (haversine), in meters.
    static func distanceMeters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let toRad = { (deg: Double) in deg * .pi / 180 }
        let dLat = toRad(b.lat - a.lat)
        let dLng = toRad(b.lng - a.lng)
        let h = pow(sin(dLat / 2), 2) + cos(toRad(a.lat)) * cos(toRad(b.lat)) * pow(sin(dLng / 2), 2)
        return 2 * earthRadiusMeters * asin(min(1, h.squareRoot()))
    }
}

/// The place rules: Stop stays locked within the chosen radius of the anchor, plus GPS slack.
enum AnchorRules {
    static let minRadiusMeters = 25.0
    static let maxRadiusMeters = 200.0
    static let defaultRadiusMeters = 25.0
    static let radiusStepMeters = 5.0
    static let maxAccuracyMarginMeters = 50.0
    /// An anchor fix worse than this is not trusted.
    static let maxAnchorAccuracyMeters = 100.0
    /// An anchor fix older than this is not trusted.
    static let maxAnchorAgeSeconds = 30.0

    /// The radius the student picked, kept to 25-200 m in 5 m steps.
    static func clampedRadius(_ meters: Double) -> Double {
        let stepped = (meters / radiusStepMeters).rounded() * radiusStepMeters
        return min(max(stepped, minRadiusMeters), maxRadiusMeters)
    }

    /// How far you must be from the anchor before Stop unlocks: the radius plus the worse GPS accuracy, capped,
    /// so GPS drift while you sit still never frees the phone.
    static func unlockDistance(radius: Double, anchorAccuracy: Double, fixAccuracy: Double) -> Double {
        let worse = max(0, anchorAccuracy, fixAccuracy)
        return clampedRadius(radius) + min(worse, maxAccuracyMarginMeters)
    }

    /// GPS is only trusted on its own when it is this sharp; indoors it usually is not.
    static let sharpGpsAccuracyMeters = 20.0

    /// Away when your steps put you outside the circle, or when a sharp GPS fix does. Without step data, the GPS
    /// rule with its slack decides.
    static func isAwayCombined(motion: DeadReckoning?, gpsDistance: Double?, gpsAccuracy: Double?,
                               radius: Double) -> Bool {
        let r = clampedRadius(radius)
        guard let motion else {
            guard let gpsDistance, let gpsAccuracy, gpsAccuracy >= 0 else { return false }
            return gpsDistance > unlockDistance(radius: r, anchorAccuracy: 0, fixAccuracy: gpsAccuracy)
        }
        if motion.isOutside(radius: r) { return true }
        guard let gpsDistance, let gpsAccuracy, gpsAccuracy >= 0, gpsAccuracy <= sharpGpsAccuracyMeters else {
            return false
        }
        return gpsDistance > r + gpsAccuracy
    }

    static func isAway(distance: Double, unlockDistance: Double) -> Bool {
        distance > unlockDistance
    }

    /// Core Location reports a negative accuracy for an invalid fix.
    static func isUsableAnchor(accuracy: Double, age: TimeInterval) -> Bool {
        accuracy >= 0 && accuracy <= maxAnchorAccuracyMeters && age <= maxAnchorAgeSeconds
    }
}
