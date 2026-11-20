import Foundation

enum Format {
    /// "0:00", "1:05", "1:02:05". Negative time reads as zero.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func meters(_ m: Double) -> String {
        "\(Int(max(0, m).rounded())) m"
    }
}

/// The start screen's minute picker.
enum SetupInput {
    static let minMinutes = 5
    static let maxMinutes = 240
    static let presets = [25, 45, 60, 90]
    static let defaultMinutes = 45

    static func stepped(_ minutes: Int, by delta: Int) -> Int {
        min(max(minutes + delta, minMinutes), maxMinutes)
    }
}

/// What has to be allowed before a session can start. Notifications are recommended, never required.
enum PermissionGate {
    /// Location (Always, ideally) and Precise Location; zones can't work on approximate location.
    static func isReady(location: Bool, precise: Bool) -> Bool {
        location && precise
    }
}

/// When being outside Anchor becomes "on your phone": not the moment you unlock (you may only be checking the
/// timer on the Lock Screen, which iOS does not tell apps apart from the home screen), but once you have stayed
/// unlocked and out of Anchor for the grace period the student picked.
enum PickupRule {
    static let defaultGraceSeconds = 10.0
    static let maxGraceSeconds = 60.0
    static let graceStepSeconds = 5.0

    static func isOnPhone(outsideAnchorSince since: Date?, now: Date, grace: Double) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) >= max(0, grace)
    }

    static func steppedGrace(_ seconds: Double, by delta: Double) -> Double {
        min(max(seconds + delta, 0), maxGraceSeconds)
    }
}
