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

/// Dropping an anchor anywhere: a circle of the chosen radius around where you stand.
enum AnchorRules {
    static let minRadiusMeters = 25.0
    static let maxRadiusMeters = 200.0
    static let defaultRadiusMeters = 25.0
    static let radiusStepMeters = 5.0
    /// An anchor reading worse than this is not trusted (the circle grows by the reading's full accuracy).
    static let maxAnchorAccuracyMeters = 65.0
    /// An anchor reading older than this is not trusted (walking, an older one could be well off).
    static let maxAnchorAgeSeconds = 10.0

    /// The radius the student picked, kept to 25-200 m in 5 m steps.
    static func clampedRadius(_ meters: Double) -> Double {
        let stepped = (meters / radiusStepMeters).rounded() * radiusStepMeters
        return min(max(stepped, minRadiusMeters), maxRadiusMeters)
    }

    static func isUsableAnchor(accuracy: Double, age: TimeInterval) -> Bool {
        accuracy >= 0 && accuracy <= maxAnchorAccuracyMeters && age <= maxAnchorAgeSeconds
    }
}
