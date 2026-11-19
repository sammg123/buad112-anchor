import CoreLocation
import os

/// GPS for the anchor. During a session it keeps running in the background (blue pill in the status bar),
/// which also keeps Anchor alive to see the phone lock and unlock.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "location")

    var onFix: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

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

    func startSession() {
        backgroundSession = CLBackgroundActivitySession()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.log.error("location error: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { onAuthorizationChange?(status) }
    }
}
