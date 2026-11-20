import CoreMotion
import os

/// The walking key: the step counter's distance laid along the way the phone turned (gyroscope yaw), as
/// `WalkSegment`s. It never unlocks anything by itself: GPS has to agree (see `AnchorExit`).
@MainActor
final class MotionTracker {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "motion")
    /// Gyro samples kept between step-counter reports (10 per second; reports come every few seconds).
    private static let maxHeadingSamples = 100

    var onSegment: ((WalkSegment) -> Void)?
    private(set) var isRunning = false

    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    private var lastDistance = 0.0
    private var headings: [Double] = []
    private var lastHeading = 0.0
    private var lastReport: Date?
    /// Faster than a run is a bunched-up report (locked screen), not walking.
    nonisolated static let maxMetersPerSecond = 3.0

    private static let probe = CMMotionManager()
    static var isAvailable: Bool { CMPedometer.isDistanceAvailable() && probe.isDeviceMotionAvailable }

    /// A report's distance, capped at what's possible in the time since the last one.
    nonisolated static func plausibleMeters(_ meters: Double, overSeconds seconds: Double) -> Double {
        min(meters, maxMetersPerSecond * max(seconds, 1))
    }
    static var isAuthorized: Bool { CMPedometer.authorizationStatus() == .authorized }
    static var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Asking for the last minute of steps is what shows iOS's Motion & Fitness prompt.
    func requestPermission() async -> Bool {
        guard CMPedometer.isStepCountingAvailable() else { return false }
        let now = Date()
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { @Sendable _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func start() {
        guard !isRunning, Self.isAvailable, Self.isAuthorized else { return }
        isRunning = true
        lastDistance = 0
        headings = []
        lastReport = Date()
        motion.deviceMotionUpdateInterval = 0.1
        // iOS's own heading (compass-backed) stays sound with the phone upright in a pocket, where the plain yaw
        // angle breaks down. Only turns matter, so a constant offset is fine.
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { @Sendable [weak self] data, _ in
            guard let degrees = data?.heading, degrees >= 0 else { return }
            MainActor.assumeIsolated { self?.turned(to: degrees * .pi / 180) }
        }
        pedometer.startUpdates(from: Date()) { @Sendable [weak self] data, error in
            if let error { Self.log.error("pedometer: \(error.localizedDescription, privacy: .public)") }
            guard let meters = data?.distance?.doubleValue else { return }
            Task { @MainActor in self?.counted(totalMeters: meters) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
    }

    private func turned(to yaw: Double) {
        headings = Array((headings + [yaw]).suffix(Self.maxHeadingSamples))
    }

    /// New steps since the last report, along the average way the phone faced meanwhile.
    private func counted(totalMeters: Double) {
        let now = Date()
        let meters = Self.plausibleMeters(totalMeters - lastDistance, overSeconds: now.timeIntervalSince(lastReport ?? now))
        lastDistance = totalMeters
        lastReport = now
        guard meters > 0 else { return }
        if !headings.isEmpty {
            lastHeading = atan2(headings.reduce(0) { $0 + sin($1) }, headings.reduce(0) { $0 + cos($1) })
        }
        headings = []
        onSegment?(WalkSegment(time: now, meters: meters, heading: lastHeading))
    }
}
