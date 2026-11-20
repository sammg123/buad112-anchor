import MapKit
import SwiftUI

/// Your selected area, lit up: a bolder outline and fill so it's clear which one the buttons act on.
struct SelectedAreaLayers: MapContent {
    let points: [GeoPoint]

    var body: some MapContent {
        MapPolygon(coordinates: points.map(\.coordinate))
            .foregroundStyle(Palette.blue.opacity(0.32))
            .stroke(Palette.blue, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
    }
}

/// Top right while an area is selected: its name, then edit, delete and close, on glass.
struct AreaActionBar: View {
    let name: String
    let edit: () -> Void
    let delete: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 70, maxWidth: 140, alignment: .leading)
                .layoutPriority(1)
                .padding(.leading, 14)
                .padding(.trailing, 6)
            icon("pencil", label: "Edit \(name)", color: Palette.blue, action: edit)
            icon("trash", label: "Delete \(name)", color: Palette.red, action: delete)
            icon("xmark", label: "Done with \(name)", color: Palette.ink, action: close)
        }
        .foregroundStyle(Palette.ink)
        .padding(4)
        .glassCapsule()
        .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
    }

    private func icon(_ symbol: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

/// "Delete Desk area?" on glass, over a dimmed map.
struct DeleteAreaConfirm: View {
    let name: String
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
                .accessibilityHidden(true)
            VStack(spacing: 18) {
                Image(systemName: "trash")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Palette.red, in: Circle())
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Delete \u{201C}\(name)\u{201D}?")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Anchor will stop locking your phone there. You can't undo this.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button(action: cancel) {
                        Text("Cancel")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white.opacity(0.75), in: Capsule())
                    }
                    .foregroundStyle(Palette.ink)
                    Button(action: delete) {
                        Text("Delete")
                            .font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Palette.red, in: Capsule())
                    }
                    .foregroundStyle(.white)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(22)
            .frame(maxWidth: 340)
            .glassPanel(cornerRadius: 32)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// A corner you can drag while editing: a white knob with a blue ring, big enough to grab.
struct CornerHandle: View {
    let number: Int
    let isDragging: Bool

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: isDragging ? 30 : 24, height: isDragging ? 30 : 24)
            .overlay(Circle().stroke(Palette.blue, lineWidth: 4))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(.snappy(duration: 0.15), value: isDragging)
            .accessibilityLabel("Corner \(number)")
            .accessibilityHint("Drag to move this corner")
    }
}

/// Bottom of the map while editing: what to do, what's wrong if Save is off, cancel and save.
struct EditToolbar: View {
    let points: [GeoPoint]
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        let problem = DrawnArea.problem(with: points)
        VStack(spacing: 12) {
            Text(problem?.hint ?? "Drag the corners out or in, then Save.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(problem == nil ? Palette.secondary : Palette.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: cancel) {
                    Text("Cancel")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white.opacity(0.7), in: Capsule())
                }
                .foregroundStyle(Palette.ink)
                Button(action: save) {
                    Label("Save", systemImage: "checkmark")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.blue, in: Capsule())
                }
                .foregroundStyle(.white)
                .disabled(problem != nil)
                .opacity(problem == nil ? 1 : 0.45)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 30)
    }
}
