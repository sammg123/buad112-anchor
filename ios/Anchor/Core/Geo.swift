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

    static func isAway(distance: Double, unlockDistance: Double) -> Bool {
        distance > unlockDistance
    }

    /// Core Location reports a negative accuracy for an invalid fix.
    static func isUsableAnchor(accuracy: Double, age: TimeInterval) -> Bool {
        accuracy >= 0 && accuracy <= maxAnchorAccuracyMeters && age <= maxAnchorAgeSeconds
    }
}
