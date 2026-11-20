import Foundation
import Observation

/// Where you are relative to every zone: cleaned-up GPS against each building outline, plus which study-area
/// beacon is close. The rules themselves are pure (Core/Presence.swift, Core/LocationFilter.swift); this only holds
/// the latest of each.
@MainActor
@Observable
final class ZoneTracker {
    private(set) var zones: [Zone]
    private(set) var filter = LocationFilter()
    /// The last reading the filter used; its accuracy is the circle checked against the outlines.
    private(set) var lastUsed: LocationReading?
    private(set) var buildings: [String: BuildingPresence] = [:]
    private(set) var areas = AreaPresence()
    /// The running session's zone when it isn't in the zones file (a session saved before zones).
    var extraZone: Zone?

    init(zones: [Zone]) {
        self.zones = zones
    }

    var estimate: LocationEstimate? { filter.estimate }

    /// Everything checked: the zones file plus a legacy session's circle.
    var allZones: [Zone] {
        guard let extraZone, !zones.contains(where: { $0.id == extraZone.id }) else { return zones }
        return zones + [extraZone]
    }

    /// Takes a reading if it passes the filter, and updates every building with it.
    @discardableResult
    func received(_ reading: LocationReading, at now: Date) -> ReadingVerdict {
        let verdict = LocationFilter.verdict(for: reading, at: now)
        guard verdict == .use else { return verdict }
        let next = filter.adding(reading)
        guard let estimate = next.estimate, next != filter else { return verdict }
        filter = next
        lastUsed = reading
        buildings = Dictionary(uniqueKeysWithValues: allZones.map { zone in
            let fit = ZoneGeometry.fit(center: estimate.point, radius: reading.accuracy, in: zone.polygon)
            return (zone.id, (buildings[zone.id] ?? .unknown).updated(with: fit, at: now))
        })
        return verdict
    }

    /// A faked reading during a session: you're treated as still in that zone.
    func spoofed(in zoneID: String, at now: Date) {
        buildings = buildings.merging([zoneID: (buildings[zoneID] ?? .unknown).spoofed(at: now)]) { $1 }
    }

    func sighted(_ key: AreaKey, proximity: BeaconProximity, accuracy: Double, at now: Date) {
        areas = areas.sighted(key, proximity: proximity, accuracy: accuracy, at: now)
    }

    func building(_ zoneID: String, at now: Date) -> BuildingPresence.State {
        buildings[zoneID]?.state(at: now) ?? .unknown
    }

    func lock(for zone: Zone, at now: Date) -> ZoneLock {
        ZoneRules.lock(zone: zone, building: building(zone.id, at: now), areaID: areas.current(in: zone.id, at: now))
    }

    /// The first zone that locks right now, with its study area.
    func lockingZone(at now: Date) -> (zone: Zone, area: StudyArea?)? {
        for zone in zones {
            if case .locked(let areaID) = lock(for: zone, at: now) { return (zone, zone.area(areaID)) }
        }
        return nil
    }

    func place(at now: Date) -> PlaceStatus {
        ZoneRules.place(zones: zones, buildings: buildings.mapValues { $0.displayState(at: now) },
                        areaIn: { self.areas.current(in: $0, at: now) })
    }

    /// Meters from the cleaned-up position to the zone's edge: positive inside, negative outside.
    func depth(in zone: Zone) -> Double? {
        estimate.map { zone.depth(of: $0.point) }
    }

    /// The circle to draw around you: the cleaned-up position, as uncertain as the worse of it and the last reading.
    var accuracyCircle: (center: GeoPoint, radius: Double)? {
        guard let estimate else { return nil }
        return (estimate.point, max(estimate.accuracy, lastUsed?.accuracy ?? 0))
    }
}
