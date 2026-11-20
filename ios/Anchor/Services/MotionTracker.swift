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

    static var isAvailable: Bool { CMPedometer.isDistanceAvailable() && CMMotionManager().isDeviceMotionAvailable }
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
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { @Sendable [weak self] data, _ in
            guard let yaw = data?.attitude.yaw else { return }
            MainActor.assumeIsolated { self?.turned(to: yaw) }
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
        let meters = totalMeters - lastDistance
        lastDistance = totalMeters
        guard meters > 0 else { return }
        if !headings.isEmpty {
            lastHeading = atan2(headings.reduce(0) { $0 + sin($1) }, headings.reduce(0) { $0 + cos($1) })
        }
        headings = []
        onSegment?(WalkSegment(time: Date(), meters: meters, heading: lastHeading))
    }
}
