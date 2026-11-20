import CoreLocation
import os

/// GPS. Precise Location is required. During a session it runs at navigation accuracy in the background, which also
/// keeps Anchor alive to see the phone lock and unlock; near a zone (iOS woke Anchor for it) it runs too, so the
/// exact outline can be checked. With Always access no blue location arrow shows; with While Using iOS shows it.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "location")

    var onFix: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var isInSession = false
    private var isNearZone = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Every reading: the filter decides what to keep.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// Zones need Precise Location; with it off iOS rounds you to a few kilometers.
    var isPrecise: Bool { manager.accuracyAuthorization == .fullAccuracy }

    /// Asks iOS to turn Precise Location on until Anchor is closed (the purpose string is in Info.plist).
    func requestPrecise() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "zones")
    }

    /// Always is what lets iOS wake Anchor at a zone when it isn't running.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// Updates while Anchor is on screen, for the map and the status line.
    func startForeground() { manager.startUpdatingLocation() }

    /// Asks for a fresh reading now (a still phone may not send one for a while).
    func refresh() {
        manager.stopUpdatingLocation()
        manager.startUpdatingLocation()
    }

    func startSession() {
        isInSession = true
        apply()
        // With Always access, relaunches Anchor if iOS ends it mid-session.
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    func stopSession() {
        isInSession = false
        manager.stopMonitoringSignificantLocationChanges()
        apply()
    }

    /// Near a zone (from the wake-up watch): keep reading GPS in the background until you leave its circle.
    func setNearZone(_ near: Bool) {
        isNearZone = near
        apply()
    }

    private func apply() {
        let background = isInSession || isNearZone
        // Navigation accuracy (the most battery) only during a session; near a zone, best is enough to notice arrival.
        manager.desiredAccuracy = isInSession ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        if background {
            // While Using needs a background activity session to keep updating, and iOS then shows its arrow.
            if backgroundSession == nil, manager.authorizationStatus != .authorizedAlways {
                backgroundSession = CLBackgroundActivitySession()
            }
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
        } else {
            backgroundSession?.invalidate()
            backgroundSession = nil
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations { onFix?(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.log.error("location error: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { onAuthorizationChange?(status) }
    }
}

extension CLLocation {
    var point: GeoPoint { GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude) }

    /// What the filter needs. iOS flags readings faked by software or produced by an accessory; the simulator's
    /// own simulated location is allowed in development.
    var reading: LocationReading {
        #if targetEnvironment(simulator)
        let spoofed = false
        #else
        let spoofed = (sourceInformation?.isSimulatedBySoftware ?? false) || (sourceInformation?.isProducedByAccessory ?? false)
        #endif
        return LocationReading(point: point, accuracy: horizontalAccuracy, time: timestamp, isSpoofed: spoofed)
    }
}
