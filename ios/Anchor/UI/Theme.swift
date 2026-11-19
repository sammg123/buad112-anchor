import SwiftUI

/// The exam blue book and the red pen that grades it (DESIGN.md). Navy ink means studying; red pen means phone.
enum Theme {
    static let cover = Color(hex: 0xA9C7EC)
    static let coverShade = Color(hex: 0x93B6E2)
    static let ink = Color(hex: 0x14284B)
    static let inkSoft = Color(hex: 0x2E4166)
    static let pencil = Color(hex: 0x556682)
    static let paper = Color(hex: 0xFCFBF7)
    static let rule = Color(hex: 0xC9DCF1)
    static let margin = Color(hex: 0xE7969C)
    static let pen = Color(hex: 0xD7262E)

    /// The book's printed lettering: condensed and heavy, like a blue book's title.
    static func lettering(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Timers: condensed, heavy, tabular figures.
    static func timer(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.condensed).monospacedDigit()
    }

    /// Handwriting (Kalam 700). Navy when the student wrote it, red when it grades the phone.
    static func hand(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Kalam-Bold", size: size, relativeTo: style)
    }

    static let spacing: CGFloat = 8
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Navy fill, paper text. The outline variant is for secondary actions.
struct InkButtonStyle: ButtonStyle {
    var outline = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(outline ? Theme.ink : Theme.paper)
            .background(outline ? Color.clear : Theme.ink, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: outline ? 2 : 0))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A ruled page with the red margin line.
struct RuledPaper: View {
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 32
            var y: CGFloat = 96
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Theme.rule))
                y += gap
            }
            context.fill(Path(CGRect(x: 28, y: 0, width: 1.5, height: size.height)), with: .color(Theme.margin))
        }
        .background(Theme.paper)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
