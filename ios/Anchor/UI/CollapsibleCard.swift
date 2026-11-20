import SwiftUI

/// A card that drags between full and compact the way iOS sheets do: it follows your finger, growing or shrinking
/// as you go (the full content fading out as the compact row fades in), and on release springs to whichever state
/// your drag and flick point at. Grab it anywhere, not just the grabber; tap the grabber to toggle.
struct CollapsibleCard<Full: View, Compact: View>: View {
    /// The screen edge the card hangs from: a bottom sheet shrinks downward, a top card shrinks upward.
    enum Edge { case top, bottom }

    let edge: Edge
    @Binding var isCollapsed: Bool
    var cornerRadius: CGFloat = 34
    let expandLabel: String
    let collapseLabel: String
    @ViewBuilder var full: () -> Full
    @ViewBuilder var compact: () -> Compact

    @State private var fullHeight: CGFloat = 0
    @State private var compactHeight: CGFloat = 0
    @State private var drag: CGFloat = 0
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var spring: Animation { .spring(response: 0.38, dampingFraction: 0.86) }
    private var settle: Animation { reduceMotion ? .easeOut(duration: 0.15) : Self.spring }
    private let grabberHeight: CGFloat = 22
    /// Past either end the card stretches at a quarter of the finger's pace.
    private let rubber: CGFloat = 0.25

    var body: some View {
        let low = compactHeight
        let high = max(fullHeight, low + 1)
        let measured = fullHeight > 0 && compactHeight > 0
        let base = isCollapsed ? low : high
        let height = stretch(base + grow(drag), low: low, high: high)
        let progress = measured ? min(1, max(0, (height - low) / (high - low))) : (isCollapsed ? 0 : 1)
        VStack(spacing: 0) {
            if edge == .bottom { grabber }
            ZStack(alignment: edge == .bottom ? .top : .bottom) {
                full()
                    .fixedSize(horizontal: false, vertical: true)
                    .background(HeightReader { fullHeight = $0 })
                    .opacity(progress * progress)
                    .allowsHitTesting(progress > 0.5)
                    .accessibilityHidden(progress <= 0.5)
                compact()
                    .fixedSize(horizontal: false, vertical: true)
                    .background(HeightReader { compactHeight = $0 })
                    .opacity((1 - progress) * (1 - progress))
                    .allowsHitTesting(progress <= 0.5)
                    .accessibilityHidden(progress > 0.5)
            }
            .frame(height: measured ? max(height, 0) : nil, alignment: edge == .bottom ? .top : .bottom)
            .clipped()
            if edge == .top { grabber }
        }
        .glassPanel(cornerRadius: cornerRadius)
        // Until both sizes are known the card would draw at full height for a frame; keep it out of sight.
        .opacity(measured ? 1 : 0)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .gesture(dragGesture(low: low, high: high, base: base))
        .onChange(of: isDragging) { _, dragging in
            // A drag the system cancelled (no end event): settle back without a jump.
            if !dragging, drag != 0 { withAnimation(settle) { drag = 0 } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isCollapsed)
    }

    /// How much a drag grows the card: down grows a top card, up grows a bottom sheet.
    private func grow(_ translation: CGFloat) -> CGFloat {
        edge == .bottom ? -translation : translation
    }

    private func stretch(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        if value > high { return high + (value - high) * rubber }
        if value < low { return low - (low - value) * rubber }
        return value
    }

    private func dragGesture(low: CGFloat, high: CGFloat, base: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                // A sideways swipe isn't a drag of the card.
                if drag == 0, abs(value.translation.width) > abs(value.translation.height) { return }
                drag = value.translation.height
            }
            .onEnded { value in
                guard drag != 0 else { return }
                // Where the flick would carry it decides, so a quick short swipe still opens or closes it.
                let landing = base + grow(value.predictedEndTranslation.height)
                withAnimation(settle) {
                    isCollapsed = landing < (low + high) / 2
                    drag = 0
                }
            }
    }

    private var grabber: some View {
        Capsule()
            .fill(Palette.secondary.opacity(0.45))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: grabberHeight)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(settle) { isCollapsed.toggle() } }
            .accessibilityElement()
            .accessibilityLabel(isCollapsed ? expandLabel : collapseLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation(settle) { isCollapsed.toggle() } }
    }
}

/// Reports a view's height as it lays out.
private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { onChange(geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in onChange(height) }
        }
    }
}
