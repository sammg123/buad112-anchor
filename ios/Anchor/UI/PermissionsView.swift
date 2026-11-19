import SwiftUI
import UIKit

/// First launch: location is required, notifications are recommended and can be skipped.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model
    @State private var askedNotifications = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.blue)
                    .frame(width: 64, height: 64)
                    .overlay(AnchorMark(size: 34))
                    .shadow(color: Palette.blue.opacity(0.3), radius: 12, y: 8)
                Text("Study where you sit.\nLeave to quit.")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick up your phone at your spot and Anchor makes it miserable. Walk away and it lets you go.")
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
            }
            VStack(spacing: 12) {
                PermissionRow(symbol: "location.fill", tint: Palette.blue, title: "Location", tag: "REQUIRED",
                              detail: "To know where your spot is and when you leave it. Choose Always when iOS asks.",
                              done: model.hasLocation)
                PermissionRow(symbol: "bell.fill", tint: Palette.red, title: "Notifications", tag: "RECOMMENDED",
                              detail: "The annoying part. Without them Anchor can't buzz you while you scroll.",
                              done: model.notificationsAllowed)
            }
            Spacer(minLength: 0)
            buttons
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.ground.ignoresSafeArea())
        .task { await model.refreshPermissions() }
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if model.locationDenied {
                Text("Location is off for Anchor. Turn it on in Settings › Anchor › Location.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.red)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(ProminentButtonStyle())
            } else if !model.hasLocation {
                Button("Allow Location") { model.requestLocation() }
                    .buttonStyle(ProminentButtonStyle())
            } else if !model.notificationsAllowed && !askedNotifications {
                Button("Turn On Buzzing") {
                    Task {
                        await model.requestNotifications()
                        askedNotifications = true
                    }
                }
                .buttonStyle(ProminentButtonStyle(color: Palette.ink))
                Button("Not now") { askedNotifications = true }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
            } else {
                Button("Continue") { model.finishOnboarding() }
                    .buttonStyle(ProminentButtonStyle())
            }
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let tag: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: done ? "checkmark" : symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(done ? "ON" : tag)
                        .font(.caption.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(done ? Palette.away : tag == "REQUIRED" ? Palette.blue : Palette.secondary)
                }
                Text(detail).font(.subheadline).foregroundStyle(Palette.secondary)
            }
        }
        .padding(18)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
