import ActivityKit
import SwiftUI

/// What the Lock Screen and Dynamic Island show. Timers count on their own (Text(timerInterval:)), so the app
/// only updates this when the mode changes.
struct AnchorActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Mode: String, Codable, Hashable, Sendable { case studying, grace, onPhone, walkingOut, away }

        let mode: Mode
        /// Study time left, frozen while on the phone or away.
        let studyRemaining: Double
        /// While studying: when the countdown reaches zero.
        let studyEndsAt: Date?
        /// Phone time so far, frozen while not on the phone.
        let phoneSeconds: Double
        /// While on the phone: the moment the phone clock would read zero, so it counts up live.
        let phoneZeroAt: Date?
        let totalSeconds: Double
        /// In the grace period: when it runs out and the phone starts counting.
        let graceEndsAt: Date?
        /// Walking out: how far your steps have taken you from the anchor, and the circle you need to leave.
        let walkedMeters: Double?
        let radiusMeters: Double?
    }

    let minutes: Int
}

enum AnchorPalette {
    static let blue = Color(red: 10 / 255, green: 102 / 255, blue: 216 / 255)
    static let red = Color(red: 214 / 255, green: 40 / 255, blue: 40 / 255)
    static let brightRed = Color(red: 255 / 255, green: 90 / 255, blue: 90 / 255)
    static let ink = Color(red: 17 / 255, green: 17 / 255, blue: 20 / 255)
    static let secondary = Color(red: 91 / 255, green: 91 / 255, blue: 99 / 255)
    static let away = Color(red: 31 / 255, green: 122 / 255, blue: 58 / 255)
    static let grace = Color(white: 0.55)
}

/// The anchor mark: ring, stem, stock and arms. SF Symbols has no anchor.
struct AnchorGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let p = { (x: Double, y: Double) in CGPoint(x: rect.minX + x / 24 * w, y: rect.minY + y / 24 * h) }
        var path = Path()
        path.addEllipse(in: CGRect(origin: p(9.8, 2.8), size: CGSize(width: 4.4 / 24 * w, height: 4.4 / 24 * h)))
        path.move(to: p(12, 7.2)); path.addLine(to: p(12, 20.5))
        path.move(to: p(7.5, 10.5)); path.addLine(to: p(16.5, 10.5))
        path.move(to: p(4.5, 13.5))
        path.addQuadCurve(to: p(12, 21), control: p(4.5, 21))
        path.addQuadCurve(to: p(19.5, 13.5), control: p(19.5, 21))
        return path
    }
}

struct AnchorMark: View {
    var size: CGFloat = 24
    var color: Color = .white
    var body: some View {
        AnchorGlyph()
            .stroke(color, style: StrokeStyle(lineWidth: max(1.5, size / 11), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
