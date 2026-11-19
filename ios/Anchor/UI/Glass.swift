import SwiftUI

/// Colors and the Liquid Glass surfaces shared by every screen. On iOS 26 these are real Liquid Glass; earlier
/// systems get the closest material.
enum Palette {
    static let blue = AnchorPalette.blue
    static let red = AnchorPalette.red
    static let ink = AnchorPalette.ink
    static let secondary = AnchorPalette.secondary
    static let away = AnchorPalette.away
    static let ground = Color(red: 242 / 255, green: 243 / 255, blue: 240 / 255)
}

extension View {
    /// A glass panel floating over the map.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
    }

    /// A round glass control (the − / + and settings buttons).
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}

/// The one filled button on a screen.
struct ProminentButtonStyle: ButtonStyle {
    var color: Color = Palette.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.3), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A small rounded stat tile inside a glass panel.
struct StatTile: View {
    let label: String
    let value: String
    var valueColor: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The anchor pin on the map.
struct AnchorPin: View {
    var size: CGFloat = 44
    var color: Color = Palette.blue

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(AnchorMark(size: size * 0.55))
            .overlay(Circle().stroke(.white, lineWidth: size > 30 ? 4 : 3))
            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
    }
}
