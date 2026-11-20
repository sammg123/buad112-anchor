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
