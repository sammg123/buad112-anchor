import CoreLocation
import os

/// iOS 17's CLMonitor: wakes Anchor, even when it isn't running (Location: Always), when you come near a zone's
/// building or into range of a study area's beacon. What actually locks is then decided by live GPS and ranging.
actor ZoneWatch {
    enum Event: Sendable {
        case nearZone(id: String, isNear: Bool)
        case areaInRange(AreaKey, inRange: Bool)
    }

    static let shared = ZoneWatch()

    private static let log = Logger(subsystem: "com.sammg123.anchor", category: "zones")
    /// Only one monitor with a given name may be open in a process (opening a second crashes), so this actor opens
    /// it once and keeps it. Letters and digits only: CLMonitor rejects "anchor.zones" or "anchor-zones" with
    /// "Monitor name is not valid".
    private static let name = "AnchorZones"

    private var opening: Task<CLMonitor, Never>?
    private var listening: Task<Void, Never>?
    /// Watch updates run one after another, so two at once can't add the same condition twice.
    private var updating: Task<Void, Never>?

    /// Watches a circle around each zone and each study area's beacon. Condition ids carry their parameters, so a
    /// changed zone replaces its old condition instead of keeping it.
    func watch(_ zones: [Zone], onEvent: @escaping @Sendable (Event) -> Void) async {
        let previous = updating
        let update = Task { await previous?.value; await sync(zones, onEvent: onEvent) }
        updating = update
        await update.value
    }

    private func sync(_ zones: [Zone], onEvent: @escaping @Sendable (Event) -> Void) async {
        let monitor = await open()
        let wanted = Self.conditions(for: zones)
        let existing = Set(await monitor.identifiers)
        for id in existing where wanted[id] == nil { await monitor.remove(id) }
        for (id, condition) in wanted where !existing.contains(id) {
            await monitor.add(condition, identifier: id, assuming: .unsatisfied)
        }
        guard listening == nil else { return }
        listening = Task {
            do {
                for try await event in await monitor.events {
                    if let parsed = Self.parse(event.identifier, satisfied: event.state == .satisfied) { onEvent(parsed) }
                }
            } catch {
                Self.log.error("zone watch stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func open() async -> CLMonitor {
        if let opening { return await opening.value }
        let task = Task { await CLMonitor(Self.name) }
        opening = task
        return await task.value
    }

    private static func conditions(for zones: [Zone]) -> [String: any CLCondition] {
        var all: [String: any CLCondition] = [:]
        for zone in zones {
            let circle = zone.enclosingCircle
            let radius = zone.wakeRadiusMeters
            let id = "zone|\(zone.id)|\(String(format: "%.5f,%.5f,%.0f", circle.center.lat, circle.center.lng, radius))"
            all[id] = CLMonitor.CircularGeographicCondition(center: circle.center.coordinate, radius: radius)
            for area in zone.studyAreas {
                let b = area.beacon
                all["area|\(zone.id)|\(area.id)|\(b.uuid.uuidString).\(b.major).\(b.minor)"] =
                    CLMonitor.BeaconIdentityCondition(uuid: b.uuid, major: b.major, minor: b.minor)
            }
        }
        return all
    }

    private static func parse(_ identifier: String, satisfied: Bool) -> Event? {
        let parts = identifier.split(separator: "|").map(String.init)
        switch parts.first {
        case "zone" where parts.count >= 2: return .nearZone(id: parts[1], isNear: satisfied)
        case "area" where parts.count >= 3: return .areaInRange(AreaKey(zoneID: parts[1], areaID: parts[2]), inRange: satisfied)
        default: return nil
        }
    }
}
