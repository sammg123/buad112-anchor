import CoreLocation
import os

/// GPS for the anchor. During a session it keeps running in the background, which also keeps Anchor alive to see
/// the phone lock and unlock. With Always access no blue location arrow shows (Sam 11-20: the island shows the
/// anchor, not iOS's arrow); with While Using, iOS requires the arrow and shows it anyway.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "location")

    var onFix: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    /// A zone's wake circle was entered (iOS relaunches Anchor for this when Location is Always).
    var onEnterZone: ((String) -> Void)?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Every reading: the presence filter averages and cleans them up itself.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// Zones need Precise Location; with it off iOS rounds you to a few kilometers.
    var isPrecise: Bool { manager.accuracyAuthorization == .fullAccuracy }

    /// Asks iOS to turn Precise Location on (for this use) when the student switched it off.
    func requestPrecise() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "zones")
    }

    /// iOS shows this as a later "Change to Always Allow?" prompt; background tracking works without it.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// Updates while Anchor is on screen, for the cover's distance readout and dropping the anchor.
    func startForeground() { manager.startUpdatingLocation() }

    /// A sitting phone gets no new fixes past the distance filter; restarting asks for a fresh one now.
    func refresh() {
        manager.stopUpdatingLocation()
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    /// Asks iOS to watch a circle around each zone and wake Anchor on arrival, even when it isn't running.
    /// iOS watches at most 20 per app; the exact outline is then checked with live GPS.
    func watch(zones: [Zone]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let wanted = Set(zones.prefix(20).map(\.id))
        for region in manager.monitoredRegions where !wanted.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        for zone in zones.prefix(20) {
            let radius = min(zone.wakeRadiusMeters, manager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: zone.center.coordinate, radius: radius, identifier: zone.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    func startSession() {
        // While Using needs a background activity session to keep updating, and iOS then shows its arrow.
        // Always needs neither, so the Dynamic Island keeps Anchor's own badge.
        backgroundSession = manager.authorizationStatus == .authorizedAlways ? nil : CLBackgroundActivitySession()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
        // With Always access, relaunches Anchor if iOS ends it mid-session.
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    func stopSession() {
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated { onFix?(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        MainActor.assumeIsolated { onEnterZone?(id) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {
        Self.log.error("zone watch failed: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.log.error("location error: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { onAuthorizationChange?(status) }
    }
}
