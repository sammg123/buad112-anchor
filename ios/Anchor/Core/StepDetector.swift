import Foundation

/// Finds each step in the phone's vertical bounce, so the walk-out compass moves the moment you step instead of
/// waiting for the pedometer's report every few seconds. The pedometer still sets the stride length.
struct StepDetector: Equatable, Sendable {
    /// Weight of each new sample in the smoothing (25 samples a second).
    static let smoothing = 0.35
    /// Smoothed upward acceleration (in g) that counts as a step.
    static let stepThreshold = 0.10
    /// The bounce has to come back down below this before the next step can count.
    static let rearmThreshold = 0.0
    /// Nobody takes more than about 3.5 steps a second.
    static let minStepInterval = 0.28
    static let defaultStrideMeters = 0.72
    static let minStrideMeters = 0.4
    static let maxStrideMeters = 1.2
    /// The pedometer's own count has to reach this before its stride is trusted.
    static let minPedometerSteps = 10

    let filtered: Double
    let isArmed: Bool
    let lastStepAt: TimeInterval?

    init() {
        self.init(filtered: 0, isArmed: true, lastStepAt: nil)
    }

    private init(filtered: Double, isArmed: Bool, lastStepAt: TimeInterval?) {
        self.filtered = filtered
        self.isArmed = isArmed
        self.lastStepAt = lastStepAt
    }

    /// `verticalAcceleration` is the phone's acceleration along gravity, without gravity itself, in g.
    func adding(verticalAcceleration a: Double, at time: TimeInterval) -> (StepDetector, Bool) {
        guard a.isFinite else { return (self, false) }
        let f = filtered + Self.smoothing * (a - filtered)
        let restedEnough = lastStepAt.map { time - $0 >= Self.minStepInterval } ?? true
        if isArmed, f > Self.stepThreshold, restedEnough {
            return (StepDetector(filtered: f, isArmed: false, lastStepAt: time), true)
        }
        if !isArmed, f < Self.rearmThreshold {
            return (StepDetector(filtered: f, isArmed: true, lastStepAt: lastStepAt), false)
        }
        return (StepDetector(filtered: f, isArmed: isArmed, lastStepAt: lastStepAt), false)
    }

    /// Meters per step from the pedometer's own totals, within human limits.
    static func stride(pedometerMeters: Double, pedometerSteps: Int) -> Double {
        guard pedometerSteps >= minPedometerSteps, pedometerMeters > 0 else { return defaultStrideMeters }
        return min(max(pedometerMeters / Double(pedometerSteps), minStrideMeters), maxStrideMeters)
    }
}
