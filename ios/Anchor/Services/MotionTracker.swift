import CoreMotion
import os

/// Step-and-turn tracking from the anchor: the pedometer says how far you walked, the gyroscope says which way you
/// were turning, and `DeadReckoning` adds it up. No GPS or Wi-Fi involved.
@MainActor
final class MotionTracker {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "motion")
    private static let sampleInterval = 1.0 / 25
    /// A gap longer than this between gyro samples (Anchor was not running) is not integrated.
    private static let maxSampleGap = 0.25
    /// Only the last few seconds of turning count for a pedometer report: that is when those steps happened.
    private static let maxSamples = 75

    var onUpdate: ((DeadReckoning) -> Void)?
    private(set) var position = DeadReckoning.origin
    private(set) var isRunning = false

    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private(set) var heading = 0.0
    private var headings: [Double] = []
    private var lastSampleTime: TimeInterval?
    private var lastPedometerMeters = 0.0

    static var isSupported: Bool { CMPedometer.isDistanceAvailable() }
    static var isAuthorized: Bool { CMPedometer.authorizationStatus() == .authorized }
    static var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Asking the pedometer for recent data is what makes iOS show the Motion & Fitness prompt.
    func requestPermission() async -> Bool {
        guard Self.isSupported else { return false }
        let now = Date()
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { @Sendable _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    /// `heading` continues the frame a saved position was laid in.
    func start(from start: DeadReckoning, heading startHeading: Double) {
        stop()
        guard Self.isSupported, motion.isDeviceMotionAvailable else { return }
        position = start
        heading = startHeading
        headings = []
        lastSampleTime = nil
        lastPedometerMeters = 0
        isRunning = true
        motion.deviceMotionUpdateInterval = Self.sampleInterval
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { @Sendable [weak self] data, error in
            if let error { Self.log.error("device motion: \(error.localizedDescription, privacy: .public)") }
            guard let data else { return }
            let r = data.rotationRate, g = data.gravity
            let rate = Turning.yawRate(rotation: (r.x, r.y, r.z), gravity: (g.x, g.y, g.z))
            let time = data.timestamp
            MainActor.assumeIsolated { self?.turned(rate: rate, at: time) }
        }
        pedometer.startUpdates(from: Date()) { @Sendable [weak self] data, error in
            if let error { Self.log.error("pedometer: \(error.localizedDescription, privacy: .public)") }
            guard let meters = data?.distance?.doubleValue else { return }
            Task { @MainActor in self?.walked(totalMeters: meters) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    private func turned(rate: Double, at time: TimeInterval) {
        defer { lastSampleTime = time }
        guard let last = lastSampleTime else { return }
        let dt = time - last
        guard dt > 0, dt <= Self.maxSampleGap else { return }
        heading += rate * dt
        headings.append(heading)
        if headings.count > Self.maxSamples { headings.removeFirst(headings.count - Self.maxSamples) }
    }

    /// The pedometer reports a running total every few seconds; the new stretch is laid along the average heading
    /// since the last report.
    private func walked(totalMeters: Double) {
        let stretch = totalMeters - lastPedometerMeters
        lastPedometerMeters = totalMeters
        let direction = Turning.circularMean(headings) ?? heading
        headings = [heading]
        guard stretch > 0 else { return }
        position = position.walking(stretch, heading: direction)
        onUpdate?(position)
    }
}
