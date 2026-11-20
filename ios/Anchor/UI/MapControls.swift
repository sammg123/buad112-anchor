import MapKit
import SwiftUI

/// Zoom math for the + and − buttons: each tap halves or doubles the span the map shows, from about a room's
/// width to a city's.
enum MapZoom {
    static let step = 2.0
    static let minSpanMeters = 60.0
    static let maxSpanMeters = 40_000.0

    static func span(_ span: Double, zoomingIn: Bool) -> Double {
        min(max(zoomingIn ? span / step : span * step, minSpanMeters), maxSpanMeters)
    }

    static func canZoom(span: Double, zoomingIn: Bool) -> Bool {
        zoomingIn ? span > minSpanMeters + 0.5 : span < maxSpanMeters - 0.5
    }

    /// While the map follows you, a zoom is kept as a scale on its own framing (`base` meters across).
    static func scale(_ scale: Double, base: Double, zoomingIn: Bool) -> Double {
        span(base * scale, zoomingIn: zoomingIn) / base
    }

    /// The width a region shows, in meters.
    static func spanMeters(of region: MKCoordinateRegion) -> Double {
        region.span.longitudeDelta * 111_195 * cos(region.center.latitude * .pi / 180)
    }

    /// The same center, `spanMeters` across (the height follows the screen's shape).
    static func region(_ region: MKCoordinateRegion, spanMeters: Double) -> MKCoordinateRegion {
        let ratio = spanMeters / max(Self.spanMeters(of: region), 1)
        return MKCoordinateRegion(center: region.center,
                                  span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * ratio,
                                                         longitudeDelta: region.span.longitudeDelta * ratio))
    }
}

/// Zoom in, zoom out, and (once you've moved the map yourself) back to following you, as one glass column.
struct MapZoomButtons: View {
    let canZoomIn: Bool
    let canZoomOut: Bool
    let showsRecenter: Bool
    let recenterLabel: String
    let zoom: (_ zoomingIn: Bool) -> Void
    let recenter: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                button("plus", label: "Zoom in", enabled: canZoomIn) { zoom(true) }
                Divider().frame(width: 28)
                button("minus", label: "Zoom out", enabled: canZoomOut) { zoom(false) }
            }
            .glassPanel(cornerRadius: 22)
            if showsRecenter {
                button("location.fill", label: recenterLabel, enabled: true, action: recenter)
                    .glassCircle()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: showsRecenter)
    }

    private func button(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.secondary.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: enabled)
    }
}

/// The map's scale bar, always showing and redrawn as you zoom.
struct MapScaleBar: View {
    let scope: Namespace.ID

    var body: some View {
        MapScaleView(anchorEdge: .leading, scope: scope)
            .mapControlVisibility(.visible)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassCapsule()
    }
}
