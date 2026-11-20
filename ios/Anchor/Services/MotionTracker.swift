import CoreMotion
import Observation
import os

/// Step-and-turn tracking from the anchor, live: every step found in the phone's bounce moves you one stride along
/// the way you are heading (the gyroscope, turning around gravity), so the walk-out compass moves step by step. The
/// pedometer sets the stride length and, if it has counted more distance than the live steps (missed steps), the
/// difference is added so the total stays true. No GPS or Wi-Fi involved.
@MainActor
@Observable
final class MotionTracker {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "motion")
    private static let sampleInterval = 1.0 / 25
    /// A gap longer than this between samples (Anchor was not running) is not integrated.
    private static let maxSampleGap = 0.25
    /// How many recent positions the compass draws as your trail.
    private static let trailLength = 80

    @ObservationIgnored var onUpdate: ((DeadReckoning) -> Void)?
    private(set) var position = DeadReckoning.origin
    /// Clockwise radians since the session began; never wrapped, so the compass can turn smoothly past a full circle.
    private(set) var heading = 0.0
    private(set) var trail: [DeadReckoning] = []
    private(set) var steps = 0
    private(set) var isRunning = false

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private var detector = StepDetector()
    @ObservationIgnored private var stride = StepDetector.defaultStrideMeters
    @ObservationIgnored private var lastSampleTime: TimeInterval?
    /// Distance the live steps have added since `start`, to compare against the pedometer's total.
    @ObservationIgnored private var liveMeters = 0.0
    /// The pedometer's latest total since `start`.
    @ObservationIgnored private var pedometerMeters = 0.0

    #if DEBUG
    /// Simulator only: `-fakeWalk` walks a scripted path (out, a turn, back a little, out again) so the compass
    /// can be seen moving without a pedometer.
    static let fakesWalking = ProcessInfo.processInfo.arguments.contains("-fakeWalk")
    @ObservationIgnored private var fakeTimer: Timer?
    @ObservationIgnored private var fakeTick = 0
    #else
    static let fakesWalking = false
    #endif

    static var isSupported: Bool { fakesWalking || CMPedometer.isDistanceAvailable() }
    static var isAuthorized: Bool { fakesWalking || CMPedometer.authorizationStatus() == .authorized }
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
        #if DEBUG
        if Self.fakesWalking {
            position = start
            heading = startHeading
            trail = [start]
            steps = 0
            liveMeters = 0
            pedometerMeters = .greatestFiniteMagnitude
            isRunning = true
            startFakeWalk()
            return
        }
        #endif
        guard Self.isSupported, motion.isDeviceMotionAvailable else { return }
        position = start
        heading = startHeading
        trail = [start]
        steps = 0
        detector = StepDetector()
        stride = StepDetector.defaultStrideMeters
        lastSampleTime = nil
        liveMeters = 0
        pedometerMeters = 0
        isRunning = true
        motion.deviceMotionUpdateInterval = Self.sampleInterval
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { @Sendable [weak self] data, error in
            if let error { Self.log.error("device motion: \(error.localizedDescription, privacy: .public)") }
            guard let data else { return }
            let r = data.rotationRate, g = data.gravity, a = data.userAcceleration
            let rate = Turning.yawRate(rotation: (r.x, r.y, r.z), gravity: (g.x, g.y, g.z))
            let gLength = max(0.1, (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot())
            // Gravity points down; the bounce of a step is acceleration against it.
            let upward = -(a.x * g.x + a.y * g.y + a.z * g.z) / gLength
            let time = data.timestamp
            MainActor.assumeIsolated { self?.sampled(turnRate: rate, upward: upward, at: time) }
        }
        pedometer.startUpdates(from: Date()) { @Sendable [weak self] data, error in
            if let error { Self.log.error("pedometer: \(error.localizedDescription, privacy: .public)") }
            guard let data, let meters = data.distance?.doubleValue else { return }
            let count = data.numberOfSteps.intValue
            Task { @MainActor in self?.pedometerCounted(meters: meters, steps: count) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        #if DEBUG
        fakeTimer?.invalidate()
        fakeTimer = nil
        #endif
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    private func sampled(turnRate: Double, upward: Double, at time: TimeInterval) {
        defer { lastSampleTime = time }
        if let last = lastSampleTime {
            let dt = time - last
            if dt > 0, dt <= Self.maxSampleGap { heading += turnRate * dt }
        }
        let (next, stepped) = detector.adding(verticalAcceleration: upward, at: time)
        detector = next
        if stepped, StepDetector.allowsLiveStep(liveMeters: liveMeters, stride: stride, pedometerMeters: pedometerMeters) {
            walk(stride, countsAsStep: true)
        }
    }

    /// The pedometer is the truth for distance: it sets the stride, and fills in steps the live detector missed.
    private func pedometerCounted(meters: Double, steps pedometerSteps: Int) {
        stride = StepDetector.stride(pedometerMeters: meters, pedometerSteps: pedometerSteps)
        pedometerMeters = meters
        let missing = StepDetector.catchUp(pedometerMeters: meters, liveMeters: liveMeters)
        if missing > 0 { walk(missing, countsAsStep: false) }
    }

    #if DEBUG
    /// 25 Hz like the real sensors: a step every half second, turning in places, walking back for a stretch.
    private func startFakeWalk() {
        fakeTick = 0
        let timer = Timer(timeInterval: 1.0 / 25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fakeSample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fakeTimer = timer
    }

    private func fakeSample() {
        fakeTick += 1
        let second = Double(fakeTick) / 25
        let turnRate: Double = switch second {
        case 8..<10: 0.6          // a gentle right turn
        case 16..<18.6: -1.2      // turning around
        case 22..<24.6: 1.2       // and back out
        default: 0.03 * sin(second) // the sway of walking
        }
        heading += turnRate / 25
        if fakeTick % 13 == 0, second > 2 { walk(StepDetector.defaultStrideMeters, countsAsStep: true) }
    }
    #endif

    private func walk(_ meters: Double, countsAsStep: Bool) {
        position = position.walking(meters, heading: heading)
        liveMeters += meters
        if countsAsStep { steps += 1 }
        trail.append(position)
        if trail.count > Self.trailLength { trail.removeFirst(trail.count - Self.trailLength) }
        onUpdate?(position)
    }
}
