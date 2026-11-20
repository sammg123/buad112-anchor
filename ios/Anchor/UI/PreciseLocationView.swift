import SwiftUI
import UIKit

/// Shown when Precise Location is off: zones are a building wide, and approximate location is kilometers off.
struct PreciseLocationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Palette.red, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)
                Text("Turn on\nPrecise Location")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .accessibilityAddTraits(.isHeader)
                Text("No-phone zones are one building. With Precise Location off, iOS only tells Anchor your position to within a few kilometers, so it can't tell the library from the street.")
                    .foregroundStyle(Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Open **Settings › Anchor › Location**.")
                step(2, "Turn **Precise Location** on.")
                step(3, "While you're there, pick **Always** so Anchor notices zones even when it's closed.")
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(ProminentButtonStyle())
                Button("Just for now") { model.requestPrecise() }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityHint("Turns Precise Location on until Anchor is closed")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.ground.ignoresSafeArea())
        .task { await model.refreshPermissions() }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.headline).foregroundStyle(Palette.blue).frame(width: 18)
            Text(text)
        }
    }
}
