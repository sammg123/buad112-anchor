import CoreMotion
import Observation
import os

/// Whether the phone is sitting still, from iOS's own motion activity (the classifier behind the Fitness app).
/// Used only to ignore GPS drift: sitting still, you can't have walked out of a zone. It can't be used to fake
/// leaving, because leaving still has to show up in GPS.
@MainActor
@Observable
final class ActivityMonitor {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "activity")

    private(set) var isStationary = false
    @ObservationIgnored private let manager = CMMotionActivityManager()
    @ObservationIgnored private var isRunning = false

    static var isSupported: Bool { CMMotionActivityManager.isActivityAvailable() }
    static var isAuthorized: Bool { CMMotionActivityManager.authorizationStatus() == .authorized }
    static var isDenied: Bool {
        let status = CMMotionActivityManager.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Asking for recent activity is what makes iOS show the Motion & Fitness prompt.
    func requestPermission() async -> Bool {
        guard Self.isSupported else { return false }
        let now = Date()
        return await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { @Sendable _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func start() {
        guard !isRunning, Self.isSupported, Self.isAuthorized else { return }
        isRunning = true
        manager.startActivityUpdates(to: .main) { @Sendable [weak self] activity in
            guard let activity else { return }
            let still = activity.stationary && activity.confidence != .low
            MainActor.assumeIsolated { self?.isStationary = still }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopActivityUpdates()
        isStationary = false
    }
}
