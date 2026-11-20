import Foundation

/// A beacon's identity, as an iBeacon broadcasts it.
struct BeaconID: Codable, Hashable, Sendable {
    let uuid: UUID
    let major: UInt16
    let minor: UInt16
}

/// One study area inside a zone's building. GPS can't tell rooms or floors apart, so each area is found by its
/// Bluetooth beacon instead.
struct StudyArea: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// For people reading the list; floors never change the in/out decision.
    let floor: Int?
    let beacon: BeaconID
}

/// A no-phone zone, Lime-style: a building's outline on the map (flat; floors don't count) and the study areas
/// inside it. With study areas listed, only those areas lock the phone (the lobby and café stay free); with none,
/// the whole building does.
struct Zone: Codable, Equatable, Sendable, Identifiable {
    /// Extra room around the outline for the circle iOS watches, so arrival is noticed before you're at the door.
    static let wakeMarginMeters = 30.0
    /// iOS doesn't reliably notice arrivals in circles smaller than this.
    static let minWakeRadiusMeters = 100.0

    let id: String
    let name: String
    let polygon: [GeoPoint]
    let studyAreas: [StudyArea]

    init(id: String, name: String, polygon: [GeoPoint], studyAreas: [StudyArea] = []) {
        self.id = id
        self.name = name
        self.polygon = polygon
        self.studyAreas = studyAreas
    }

    /// Zones saved inside sessions before study areas existed have no `studyAreas`; they load as whole buildings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        polygon = try container.decode([GeoPoint].self, forKey: .polygon)
        studyAreas = try container.decodeIfPresent([StudyArea].self, forKey: .studyAreas) ?? []
    }

    var usesWholeBuilding: Bool { studyAreas.isEmpty }

    func area(_ id: String?) -> StudyArea? { studyAreas.first { $0.id == id } }

    /// The smallest circle around the whole outline.
    var enclosingCircle: (center: GeoPoint, radius: Double) { ZoneGeometry.enclosingCircle(polygon) }

    var center: GeoPoint { enclosingCircle.center }

    /// The circle iOS watches to wake Anchor on arrival: the smallest circle around the outline, plus 30 m.
    var wakeRadiusMeters: Double { max(Self.minWakeRadiusMeters, enclosingCircle.radius + Self.wakeMarginMeters) }

    func contains(_ point: GeoPoint) -> Bool { ZoneGeometry.contains(point, in: polygon) }

    /// Meters to the nearest edge: positive inside, negative outside.
    func depth(of point: GeoPoint) -> Double { ZoneGeometry.depth(of: point, in: polygon) }

    static let droppedAnchorID = "dropped-anchor"

    /// A spot from "Drop anchor here", not a zone from the zones file.
    var isDroppedAnchor: Bool { id == Self.droppedAnchorID }

    /// "Drop anchor here": your radius around where you stand, widened by that reading's full accuracy, so a
    /// rough anchor can't put the edge right under you.
    static func droppedAnchor(center: GeoPoint, radius: Double, anchorAccuracy: Double) -> Zone {
        let margin = min(max(anchorAccuracy, 0), AnchorRules.maxAnchorAccuracyMeters)
        return circle(center: center, radius: radius + margin)
    }

    /// A circle zone (a dropped anchor, or a session saved before zones).
    static func circle(id: String = droppedAnchorID, name: String = "Your spot", center: GeoPoint,
                       radius: Double, segments: Int = 48) -> Zone {
        let points = (0..<segments).map { i -> GeoPoint in
            let a = Double(i) / Double(segments) * 2 * .pi
            return ZoneGeometry.point(from: center, east: radius * sin(a), north: radius * cos(a))
        }
        return Zone(id: id, name: name, polygon: points)
    }
}

/// How a reading's accuracy circle sits against an outline.
enum CircleFit: Equatable, Sendable {
    case mostlyInside
    /// Partly in, partly out: says nothing either way.
    case straddling
    case fullyOutside
}

/// Flat geometry for zone-sized areas: points are projected to meters around a reference, which is exact enough
/// for anything the size of a campus.
enum ZoneGeometry {
    /// A reading counts as inside when more than this share of its accuracy circle is inside the outline.
    static let mostlyInsideShare = 0.5

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

    /// Treats a reading as a circle of its accuracy: mostly inside, wholly outside, or neither.
    static func fit(center: GeoPoint, radius: Double, in polygon: [GeoPoint]) -> CircleFit {
        let r = max(radius, 1)
        let d = depth(of: center, in: polygon)
        if d <= -r { return .fullyOutside }
        if d >= r { return .mostlyInside }
        return insideShare(center: center, radius: r, in: polygon) > mostlyInsideShare ? .mostlyInside : .straddling
    }

    /// The share of the circle inside the outline, from 60 points spread evenly over its area
    /// (four rings, each with points in proportion to its area).
    static func insideShare(center: GeoPoint, radius: Double, in polygon: [GeoPoint]) -> Double {
        var inside = 0, total = 0
        for ring in 1...4 {
            let r = radius * (Double(ring) - 0.5) / 4
            let count = 6 * ring
            for k in 0..<count {
                let a = (Double(k) + 0.5) / Double(count) * 2 * .pi
                total += 1
                if contains(point(from: center, east: r * sin(a), north: r * cos(a)), in: polygon) { inside += 1 }
            }
        }
        return Double(inside) / Double(total)
    }

    /// The smallest circle holding every point (incremental Welzl; exact, and quick for outlines this size).
    static func enclosingCircle(_ points: [GeoPoint]) -> (center: GeoPoint, radius: Double) {
        guard let origin = points.first else { return (GeoPoint(lat: 0, lng: 0), 0) }
        let p = points.map { meters($0, from: origin) }
        var circle = Circle(x: p[0].x, y: p[0].y, r: 0)
        for i in p.indices where !circle.holds(p[i]) {
            circle = Circle(x: p[i].x, y: p[i].y, r: 0)
            for j in 0..<i where !circle.holds(p[j]) {
                circle = Circle.through(p[i], p[j])
                for k in 0..<j where !circle.holds(p[k]) {
                    circle = Circle.through(p[i], p[j], p[k])
                }
            }
        }
        return (point(from: origin, east: circle.x, north: circle.y), circle.r)
    }

    private struct Circle {
        let x: Double, y: Double, r: Double

        func holds(_ p: (x: Double, y: Double)) -> Bool { hypot(p.x - x, p.y - y) <= r + 1e-6 }

        static func through(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Circle {
            Circle(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, r: hypot(a.x - b.x, a.y - b.y) / 2)
        }

        static func through(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double),
                            _ c: (x: Double, y: Double)) -> Circle {
            let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
            guard abs(d) > 1e-9 else {
                // In a line: the circle on the farthest pair.
                return [through(a, b), through(a, c), through(b, c)].max { $0.r < $1.r }!
            }
            let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
            let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
            let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
            return Circle(x: ux, y: uy, r: hypot(a.x - ux, a.y - uy))
        }
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

/// The zones file (Zones.json):
/// `{"version": 1, "zones": [{"id", "name", "polygon": [[lat, lng], ...],
///   "studyAreas": [{"id", "name", "floor", "beacon": {"uuid", "major", "minor"}}]}]}`.
/// Bundled for now; the same shape can come from a server later (see `ZoneStore`).
enum ZoneCatalog {
    /// iOS watches at most 20 conditions per app: one per zone plus one per study area.
    static let maxWatched = 20

    enum Problem: Error, Equatable {
        case empty
        case tooManyToWatch
        case badID(String)
        case badOutline(String)
        case duplicateArea(String)
        case duplicateBeacon(String)
    }

    private struct File: Decodable {
        let version: Int
        let zones: [Record]
    }

    private struct Record: Decodable {
        let id: String
        let name: String
        let polygon: [[Double]]
        let studyAreas: [StudyArea]?
    }

    static func decode(_ data: Data) throws -> [Zone] {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard !file.zones.isEmpty else { throw Problem.empty }
        let zones = try file.zones.map(zone(from:))
        guard zones.count + zones.reduce(0, { $0 + $1.studyAreas.count }) <= maxWatched else { throw Problem.tooManyToWatch }
        if let bad = (zones.map(\.id) + zones.flatMap { $0.studyAreas.map(\.id) }).first(where: { !isSafeID($0) }) {
            throw Problem.badID(bad)
        }
        var beacons = Set<BeaconID>()
        for area in zones.flatMap(\.studyAreas) where !beacons.insert(area.beacon).inserted {
            throw Problem.duplicateBeacon(area.id)
        }
        return zones
    }

    /// Ids end up inside the watch's condition names: letters, digits, "-" and "_" only.
    private static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func zone(from record: Record) throws -> Zone {
        let points = record.polygon.compactMap { pair -> GeoPoint? in
            guard pair.count == 2, abs(pair[0]) <= 90, abs(pair[1]) <= 180 else { return nil }
            return GeoPoint(lat: pair[0], lng: pair[1])
        }
        guard points.count == record.polygon.count, points.count >= 3 else { throw Problem.badOutline(record.id) }
        let areas = record.studyAreas ?? []
        if let repeated = Dictionary(grouping: areas, by: \.id).first(where: { $0.value.count > 1 }) {
            throw Problem.duplicateArea(repeated.key)
        }
        return Zone(id: record.id, name: record.name, polygon: points, studyAreas: areas)
    }
}

/// Where zones come from. Bundled today; a server-backed store can replace it without touching the rest.
protocol ZoneStore: Sendable {
    func zones() throws -> [Zone]
}

struct BundledZoneStore: ZoneStore {
    enum Problem: Error { case missingFile }

    func zones() throws -> [Zone] {
        guard let url = Bundle.main.url(forResource: "Zones", withExtension: "json") else { throw Problem.missingFile }
        return try ZoneCatalog.decode(Data(contentsOf: url))
    }
}
