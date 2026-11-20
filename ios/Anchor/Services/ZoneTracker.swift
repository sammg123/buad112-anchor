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
    /// The running session's place when it isn't in the zones file: a dropped anchor's circle.
    private(set) var extraZone: Zone?

    init(zones: [Zone]) {
        self.zones = zones
    }

    var estimate: LocationEstimate? { filter.estimate }

    /// Replaces the zone list (your areas changed). Zones still listed keep what's known about them; a new one
    /// is checked against your current position right away instead of waiting for the next reading.
    func setZones(_ zones: [Zone], at now: Date = Date()) {
        self.zones = zones
        let ids = Set(allZones.map(\.id))
        let kept = buildings.filter { ids.contains($0.key) }
        guard let here = freshEstimate(at: now) else {
            buildings = kept
            return
        }
        let margin = LocationFilter.margin(estimateAccuracy: here.accuracy)
        let added = allZones.filter { kept[$0.id] == nil }.map { zone in
            (zone.id, BuildingPresence.unknown.updated(with: ZoneGeometry.fit(center: here.point, radius: margin, in: zone.polygon), at: now))
        }
        buildings = kept.merging(added) { old, _ in old }
    }

    /// Tracks a dropped anchor's circle (or nothing). A new spot starts fresh: whatever was known about the last
    /// one is forgotten.
    func setExtraZone(_ zone: Zone?) {
        let next = zone.flatMap { extra in zones.contains { $0.id == extra.id } ? nil : extra }
        // Only places outside the zones file start fresh; a real zone keeps what's known about its building.
        let stale = Set([extraZone?.id, next?.id].compactMap { $0 })
        buildings = buildings.filter { !stale.contains($0.key) }
        extraZone = next
    }

    /// The cleaned-up position, only if it's from the last 10 s.
    func freshEstimate(at now: Date) -> LocationEstimate? {
        estimate.flatMap { now.timeIntervalSince($0.time) <= Self.freshSeconds ? $0 : nil }
    }

    private static let freshSeconds = 10.0

    /// Everything checked: the zones file plus a legacy session's circle.
    var allZones: [Zone] {
        guard let extraZone, !zones.contains(where: { $0.id == extraZone.id }) else { return zones }
        return zones + [extraZone]
    }

    /// Takes a reading if it passes the filter, and updates every building with it.
    @discardableResult
    func received(_ reading: LocationReading, at now: Date) -> ReadingVerdict {
        let verdict = LocationFilter.verdict(for: reading, at: now)
        if verdict == .tooInaccurate, LocationFilter.isExitEvidence(accuracy: reading.accuracy) {
            buildings = Dictionary(uniqueKeysWithValues: allZones.map { zone in
                let fit = ZoneGeometry.fit(center: reading.point, radius: reading.accuracy, in: zone.polygon)
                return (zone.id, (buildings[zone.id] ?? .unknown).updatedRough(with: fit, at: now))
            })
        }
        guard verdict == .use else { return verdict }
        let next = filter.adding(reading)
        guard let estimate = next.estimate, next != filter else { return verdict }
        filter = next
        lastUsed = reading
        let margin = LocationFilter.margin(estimateAccuracy: estimate.accuracy)
        buildings = Dictionary(uniqueKeysWithValues: allZones.map { zone in
            let fit = ZoneGeometry.fit(center: estimate.point, radius: margin, in: zone.polygon)
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

    /// Ranging reported (possibly no beacons at all).
    func ranged(at now: Date) {
        areas = areas.ranged(at: now)
    }

    func building(_ zoneID: String, at now: Date) -> BuildingPresence.State {
        buildings[zoneID]?.state(at: now) ?? .unknown
    }

    func lock(for zone: Zone, at now: Date) -> ZoneLock {
        ZoneRules.lock(zone: zone, building: building(zone.id, at: now), areaID: areas.current(in: zone.id, at: now),
                       rangingLive: areas.isRangingLive(at: now))
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

    /// Meters from the cleaned-up position to the zone's edge: positive inside, negative outside. Nil without a
    /// position from the last 10 s.
    func depth(in zone: Zone, at now: Date) -> Double? {
        freshEstimate(at: now).map { zone.depth(of: $0.point) }
    }

    /// The circle to draw around you: the cleaned-up position and the margin used at edges.
    var accuracyCircle: (center: GeoPoint, radius: Double)? {
        guard let estimate else { return nil }
        return (estimate.point, LocationFilter.margin(estimateAccuracy: estimate.accuracy))
    }
}
