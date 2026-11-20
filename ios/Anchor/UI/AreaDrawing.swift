import MapKit
import SwiftUI

/// The outline being drawn: each dot numbered, joined in order, and closed into a shaded area from 3 dots on.
struct DrawnShapeLayers: MapContent {
    let points: [GeoPoint]

    var body: some MapContent {
        if points.count >= 3 {
            MapPolygon(coordinates: points.map(\.coordinate))
                .foregroundStyle(Palette.blue.opacity(0.18))
                .stroke(Palette.blue, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        } else if points.count == 2 {
            MapPolyline(coordinates: points.map(\.coordinate))
                .stroke(Palette.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
            Annotation("", coordinate: point.coordinate, anchor: .center) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Palette.blue, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .accessibilityLabel("Corner \(index + 1)")
            }
        }
    }
}

extension DrawnArea.Problem {
    var hint: String {
        switch self {
        case .tooFewPoints: "Tap at least 3 corners."
        case .tooManyPoints: "That's the most corners an area can have."
        case .crossesItself: "The lines cross. Undo the last corner and go around the edge in order."
        case .tooSmall: "Too small for GPS. Make it at least about 10 m across."
        }
    }
}

/// Top of the map while drawing: what to do, and what's wrong if Save is off.
struct DrawingHeader: View {
    let points: [GeoPoint]

    var body: some View {
        let problem = DrawnArea.problem(with: points)
        VStack(alignment: .leading, spacing: 4) {
            Text(points.isEmpty ? "Tap the map at each corner of your area" : "\(points.count) corner\(points.count == 1 ? "" : "s")")
                .font(.headline)
            Text(problem?.hint ?? "Looks good. Keep tapping to add corners, or Save.")
                .font(.footnote)
                .foregroundStyle(problem == nil ? Palette.away : Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 22)
        .animation(.smooth(duration: 0.2), value: points.count)
    }
}

/// Bottom of the map while drawing: undo, clear, cancel, save.
struct DrawingToolbar: View {
    let points: [GeoPoint]
    let undo: () -> Void
    let clear: () -> Void
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                tool("arrow.uturn.backward", "Undo", enabled: !points.isEmpty, action: undo)
                tool("trash", "Clear", enabled: !points.isEmpty, action: clear)
                tool("xmark", "Cancel", enabled: true, action: cancel)
            }
            Button(action: save) {
                Label("Save area", systemImage: "checkmark")
            }
            .buttonStyle(ProminentButtonStyle())
            .disabled(DrawnArea.problem(with: points) != nil)
            .opacity(DrawnArea.problem(with: points) == nil ? 1 : 0.45)
        }
        .padding(16)
        .glassPanel(cornerRadius: 30)
    }

    private func tool(_ symbol: String, _ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white.opacity(0.6), in: Capsule())
        }
        .foregroundStyle(enabled ? Palette.ink : Palette.secondary.opacity(0.5))
        .disabled(!enabled)
    }
}
