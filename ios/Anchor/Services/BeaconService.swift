import CoreLocation
import os

/// Ranges study-area beacons for their distance while Anchor runs (on screen, in a session, or near a zone).
/// Monitoring for arrival is ZoneWatch's job; ranging is what says whether you're really in the area.
@MainActor
final class BeaconService: NSObject, CLLocationManagerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "beacons")

    var onSighting: ((AreaKey, BeaconProximity, Double) -> Void)?
    /// Every ranging report, beacons or not: proof ranging is still running.
    var onRanged: (() -> Void)?

    private let manager = CLLocationManager()
    private var areasByBeacon: [String: AreaKey] = [:]
    private var constraints: [CLBeaconIdentityConstraint] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    func startRanging(_ zones: [Zone]) {
        guard CLLocationManager.isRangingAvailable() else { return }
        let wanted = Dictionary(zones.flatMap { zone in
            zone.studyAreas.map { (Self.key($0.beacon.uuid, $0.beacon.major, $0.beacon.minor), AreaKey(zoneID: zone.id, areaID: $0.id)) }
        }, uniquingKeysWith: { first, _ in first })
        guard wanted != areasByBeacon else { return }
        stopRanging()
        areasByBeacon = wanted
        constraints = zones.flatMap(\.studyAreas).map {
            CLBeaconIdentityConstraint(uuid: $0.beacon.uuid, major: $0.beacon.major, minor: $0.beacon.minor)
        }
        constraints.forEach(manager.startRangingBeacons(satisfying:))
    }

    /// During a session, keep ranging with the screen locked (Anchor runs in the background then).
    func setBackground(_ on: Bool) {
        manager.allowsBackgroundLocationUpdates = on
        manager.showsBackgroundLocationIndicator = false
    }

    func stopRanging() {
        constraints.forEach(manager.stopRangingBeacons(satisfying:))
        constraints = []
        areasByBeacon = [:]
    }

    private nonisolated static func key(_ uuid: UUID, _ major: UInt16, _ minor: UInt16) -> String {
        "\(uuid.uuidString).\(major).\(minor)"
    }

    private nonisolated static func proximity(_ value: CLProximity) -> BeaconProximity {
        switch value {
        case .immediate: .immediate
        case .near: .near
        case .far: .far
        default: .unknown
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                                     satisfying constraint: CLBeaconIdentityConstraint) {
        let seen = beacons.map {
            (key: Self.key($0.uuid, $0.major.uint16Value, $0.minor.uint16Value), proximity: Self.proximity($0.proximity),
             accuracy: $0.accuracy)
        }
        MainActor.assumeIsolated {
            onRanged?()
            for beacon in seen {
                guard let area = areasByBeacon[beacon.key] else { continue }
                onSighting?(area, beacon.proximity, beacon.accuracy)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailRangingFor constraint: CLBeaconIdentityConstraint,
                                     error: Error) {
        Self.log.error("beacon ranging failed: \(error.localizedDescription, privacy: .public)")
    }
}
