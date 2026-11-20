import Foundation

/// Areas you draw yourself on the map: tap dots, they join into an outline, and inside it the phone is locked
/// (the whole area, like a zone with no study areas).
enum DrawnArea {
    static let minPoints = 3
    static let maxPoints = 60
    /// About a 10 m square: anything smaller is lost in GPS error.
    static let minSquareMeters = 100.0
    static let idPrefix = "mine-"
    private static let fallbackName = "My area"

    enum Problem: Error, Equatable {
        case tooFewPoints
        case tooManyPoints
        case crossesItself
        case tooSmall
    }

    /// Why the outline can't be saved, or nil when it can.
    static func problem(with points: [GeoPoint]) -> Problem? {
        if points.count < minPoints { return .tooFewPoints }
        if points.count > maxPoints { return .tooManyPoints }
        if crossesItself(points) { return .crossesItself }
        if squareMeters(points) < minSquareMeters { return .tooSmall }
        return nil
    }

    /// The outline's area (shoelace formula, flat projection).
    static func squareMeters(_ points: [GeoPoint]) -> Double {
        guard let origin = points.first, points.count >= 3 else { return 0 }
        let p = points.map { ZoneGeometry.meters($0, from: origin) }
        let twice = p.indices.reduce(0.0) { sum, i in
            let a = p[i], b = p[(i + 1) % p.count]
            return sum + a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    /// Whether any two edges that don't share a corner cross.
    static func crossesItself(_ points: [GeoPoint]) -> Bool {
        guard let origin = points.first, points.count >= 4 else { return false }
        let p = points.map { ZoneGeometry.meters($0, from: origin) }
        let n = p.count
        for i in 0..<n {
            for j in (i + 1)..<n where j != i + 1 && !(i == 0 && j == n - 1) {
                if segmentsCross(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) { return true }
            }
        }
        return false
    }

    static func zone(named name: String, points: [GeoPoint], id: String) -> Zone {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Zone(id: id, name: trimmed.isEmpty ? fallbackName : String(trimmed.prefix(40)), polygon: points)
    }

    /// Adds a tapped corner where it makes the shortest outline without crossing (so corners tapped out of order
    /// still make the shape you meant), or at the end with fewer than 3. If no place avoids a crossing, the whole
    /// outline is untangled.
    static func inserting(_ point: GeoPoint, into points: [GeoPoint]) -> [GeoPoint] {
        // A second tap on a corner you already have isn't a new corner.
        if points.contains(where: { Geo.distanceMeters($0, point) < duplicateMeters }) { return points }
        guard points.count >= 3 else { return points + [point] }
        let candidates = (0..<points.count).map { i -> [GeoPoint] in
            Array(points[...i]) + [point] + Array(points[(i + 1)...])
        }
        let clean = candidates.filter { !crossesItself($0) }
        if let best = clean.min(by: { perimeter($0) < perimeter($1) }) { return best }
        return untangled(points + [point])
    }

    /// Taps closer than this to an existing corner are the same corner.
    static let duplicateMeters = 1.0

    /// The same corners in an order that can't cross: by angle around their middle.
    static func untangled(_ points: [GeoPoint]) -> [GeoPoint] {
        guard points.count >= 3 else { return points }
        let middle = GeoPoint(lat: points.reduce(0) { $0 + $1.lat } / Double(points.count),
                              lng: points.reduce(0) { $0 + $1.lng } / Double(points.count))
        return points.sorted {
            let a = ZoneGeometry.meters($0, from: middle), b = ZoneGeometry.meters($1, from: middle)
            return atan2(a.y, a.x) < atan2(b.y, b.x)
        }
    }

    private static func perimeter(_ points: [GeoPoint]) -> Double {
        points.indices.reduce(0) { $0 + Geo.distanceMeters(points[$1], points[($1 + 1) % points.count]) }
    }

    /// Zones from the zones file offered as your own areas (once), so you can edit or delete them like any other.
    static func seeded(from bundled: [Zone], into existing: [Zone]) -> [Zone] {
        let added = bundled
            .map { zone(named: $0.name, points: $0.polygon, id: idPrefix + $0.id) }
            .filter { new in !existing.contains { $0.id == new.id } }
        return existing + added
    }

    /// Your area under a point you held or tapped: the smallest one, where yours overlap. Library zones aren't
    /// yours to edit.
    static func area(at point: GeoPoint, in zones: [Zone]) -> Zone? {
        zones.filter { $0.isUserArea && $0.contains(point) }.min { squareMeters($0.polygon) < squareMeters($1.polygon) }
    }

    /// The same area with its corners moved, if the new outline is still valid.
    static func reshaped(_ zone: Zone, to points: [GeoPoint]) -> Result<Zone, Problem> {
        if let problem = problem(with: points) { return .failure(problem) }
        return .success(Zone(id: zone.id, name: zone.name, polygon: points))
    }

    /// Letters, digits and dashes only, so iOS can watch it.
    static func newID() -> String {
        idPrefix + UUID().uuidString.prefix(8).lowercased()
    }

    /// "My area 1", "My area 2", … the first one not already used.
    static func defaultName(existing: [Zone]) -> String {
        let used = Set(existing.map(\.name))
        return (1...).lazy.map { "\(fallbackName) \($0)" }.first { !used.contains($0) } ?? fallbackName
    }

    private typealias Point = (x: Double, y: Double)

    private static func segmentsCross(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
        func side(_ p: Point, _ q: Point, _ r: Point) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}

extension Zone {
    /// Drawn by you, not from the zones file.
    var isUserArea: Bool { id.hasPrefix(DrawnArea.idPrefix) }
}

extension ZoneRules {
    /// During a session every area locks, not just the one it started in: away only when your own place says
    /// free and no other area holds you. Nil: not enough to go on.
    static func sessionAway(own: ZoneLock, others: [ZoneLock]) -> Bool? {
        if case .locked = own { return false }
        if others.contains(where: { if case .locked = $0 { return true } else { return false } }) { return false }
        if case .free = own { return true }
        return nil
    }

    /// iOS watches at most 20 conditions per app (a zone is one, each study area one more): keep zones in order
    /// (the zones file first, then your areas) while they fit.
    static func watchable(_ zones: [Zone], limit: Int = ZoneCatalog.maxWatched) -> [Zone] {
        var used = 0
        return zones.filter { zone in
            let cost = 1 + zone.studyAreas.count
            guard used + cost <= limit else { return false }
            used += cost
            return true
        }
    }
}
