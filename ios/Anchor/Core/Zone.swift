import Foundation

/// A no-phone zone: a flat outline on the map (floors don't count). Inside it Anchor is locked; outside every
/// zone you're free.
struct Zone: Codable, Equatable, Sendable, Identifiable {
    /// iOS wakes Anchor on arrival using a circle around the zone; it doesn't watch circles smaller than this well.
    static let minWakeRadiusMeters = 100.0
    /// Extra room around the outline for the wake circle, so arrival is noticed before you're at the door.
    static let wakeMarginMeters = 30.0

    let id: String
    let name: String
    let polygon: [GeoPoint]

    /// The middle of the outline (the average of its corners).
    var center: GeoPoint {
        let n = Double(max(polygon.count, 1))
        return GeoPoint(lat: polygon.reduce(0) { $0 + $1.lat } / n, lng: polygon.reduce(0) { $0 + $1.lng } / n)
    }

    /// The circle iOS watches to wake Anchor when you arrive.
    var wakeRadiusMeters: Double {
        let farthest = polygon.map { Geo.distanceMeters(center, $0) }.max() ?? 0
        return max(Self.minWakeRadiusMeters, farthest + Self.wakeMarginMeters)
    }

    func contains(_ point: GeoPoint) -> Bool { ZoneGeometry.contains(point, in: polygon) }

    /// Meters to the nearest edge: positive inside, negative outside.
    func depth(of point: GeoPoint) -> Double { ZoneGeometry.depth(of: point, in: polygon) }

    /// "Drop anchor here": a circle of the chosen radius around where you stand.
    static func circle(id: String = "dropped-anchor", name: String = "Your spot", center: GeoPoint,
                       radius: Double, segments: Int = 48) -> Zone {
        let points = (0..<segments).map { i -> GeoPoint in
            let a = Double(i) / Double(segments) * 2 * .pi
            return ZoneGeometry.point(from: center, east: radius * sin(a), north: radius * cos(a))
        }
        return Zone(id: id, name: name, polygon: points)
    }
}

/// Flat geometry for zone-sized areas: points are projected to meters around a reference, which is exact enough
/// for anything the size of a campus.
enum ZoneGeometry {
    private static let metersPerDegree = Geo.earthRadiusMeters * .pi / 180

    /// `point` in meters east and north of `origin`.
    static func meters(_ point: GeoPoint, from origin: GeoPoint) -> (x: Double, y: Double) {
        let x = (point.lng - origin.lng) * metersPerDegree * cos(origin.lat * .pi / 180)
        let y = (point.lat - origin.lat) * metersPerDegree
        return (x, y)
    }

    /// The point `east` and `north` meters from `origin`.
    static func point(from origin: GeoPoint, east: Double, north: Double) -> GeoPoint {
        GeoPoint(lat: origin.lat + north / metersPerDegree,
                 lng: origin.lng + east / (metersPerDegree * cos(origin.lat * .pi / 180)))
    }

    /// Ray casting: a ray from the point crosses the outline an odd number of times when the point is inside.
    static func contains(_ point: GeoPoint, in polygon: [GeoPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        let corners = polygon.map { meters($0, from: point) }
        var inside = false
        var j = corners.count - 1
        for i in corners.indices {
            let a = corners[i], b = corners[j]
            if (a.y > 0) != (b.y > 0), 0 < (b.x - a.x) * (0 - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Meters from the point to the nearest edge: positive inside the outline, negative outside.
    static func depth(of point: GeoPoint, in polygon: [GeoPoint]) -> Double {
        guard polygon.count >= 3 else { return -.infinity }
        let corners = polygon.map { meters($0, from: point) }
        var nearest = Double.infinity
        var j = corners.count - 1
        for i in corners.indices {
            nearest = min(nearest, distanceToSegment(a: corners[j], b: corners[i]))
            j = i
        }
        return contains(point, in: polygon) ? nearest : -nearest
    }

    /// Distance from the origin to the segment a-b, in the same units.
    private static func distanceToSegment(a: (x: Double, y: Double), b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared)) : 0
        let px = a.x + t * dx, py = a.y + t * dy
        return (px * px + py * py).squareRoot()
    }
}

/// The zones file: `{"version": 1, "zones": [{"id", "name", "polygon": [[lat, lng], ...]}]}`. Bundled for now;
/// the same shape can come from a server later.
enum ZoneCatalog {
    enum Problem: Error, Equatable {
        case empty
        case badOutline(String)
    }

    private struct File: Decodable {
        let version: Int
        let zones: [Record]
    }

    private struct Record: Decodable {
        let id: String
        let name: String
        let polygon: [[Double]]
    }

    static func decode(_ data: Data) throws -> [Zone] {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard !file.zones.isEmpty else { throw Problem.empty }
        return try file.zones.map { record in
            let points = record.polygon.compactMap { pair in
                pair.count == 2 && pair.allSatisfy(\.isFinite) ? GeoPoint(lat: pair[0], lng: pair[1]) : nil
            }
            guard points.count == record.polygon.count, points.count >= 3 else { throw Problem.badOutline(record.id) }
            return Zone(id: record.id, name: record.name, polygon: points)
        }
    }
}

/// Where zones come from. Bundled today; a server-backed store can replace it without touching the rest.
protocol ZoneStore: Sendable {
    func zones() throws -> [Zone]
}

struct BundledZoneStore: ZoneStore {
    func zones() throws -> [Zone] {
        guard let url = Bundle.main.url(forResource: "zones", withExtension: "json") else { return [] }
        return try ZoneCatalog.decode(Data(contentsOf: url))
    }
}
