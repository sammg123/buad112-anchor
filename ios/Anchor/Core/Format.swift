import Foundation

enum Format {
    /// "0:00", "1:05", "1:02:05". Negative time reads as zero.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func money(_ dollars: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(2))
            .grouping(.automatic)
            .locale(Locale(identifier: "en_US"))
        return "$" + max(0, dollars).formatted(style)
    }

    static func meters(_ m: Double) -> String {
        "\(Int(max(0, m).rounded())) m"
    }
}

/// The red grade on the handed-back cover: the share of session time spent on the phone.
enum Grade {
    static func letter(studied: Double, phone: Double) -> String {
        let total = studied + phone
        guard total > 0 else { return "—" }
        let share = phone / total
        switch share {
        case 0: return "A+"
        case ..<0.05: return "A"
        case ..<0.10: return "B"
        case ..<0.20: return "C"
        case ..<0.35: return "D"
        default: return "F"
        }
    }
}

/// Parsing the cover's blanks. Each returns nil for input that cannot be used.
enum SetupInput {
    static let minMinutes = 1
    static let maxMinutes = 240
    static let maxTuition = 500_000.0
    static let maxCourseLength = 40
    static let defaultCourse = "BUAD 112"

    static func minutes(_ text: String) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), (minMinutes...maxMinutes).contains(n) else {
            return nil
        }
        return n
    }

    /// Empty means no tuition (the cost line then reads $0.00).
    static func tuition(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        if digits.isEmpty { return 0 }
        guard let n = Double(digits), n >= 0, n <= maxTuition else { return nil }
        return n
    }

    static func course(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCourse : String(trimmed.prefix(maxCourseLength))
    }
}
