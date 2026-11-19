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
