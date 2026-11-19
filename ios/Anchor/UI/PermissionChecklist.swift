import SwiftUI
import UIKit

/// Says why each permission matters before iOS asks, and where to fix it when it was refused.
struct PermissionChecklist: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BEFORE YOU START").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.inkSoft)
            row(done: locationDone, title: "Location",
                detail: locationDetail)
            row(done: model.notificationsAllowed, title: "Notifications",
                detail: "This is how Anchor buzzes you while you're in other apps.")
            if !model.hasPasscode {
                row(done: false, title: "Phone passcode",
                    detail: "Without a passcode iOS never tells Anchor your phone is locked, so it would buzz forever. Settings › Face ID & Passcode.")
            }
            Text("Using a Focus or Do Not Disturb? Add Anchor to its allowed apps, or the buzzes stay silent.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            if !(locationDone && model.notificationsAllowed) {
                Button(needsSettings ? "Open Settings" : "Allow") {
                    if needsSettings {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } else {
                        Task { await model.requestPermissions() }
                    }
                }
                .buttonStyle(InkButtonStyle(outline: true))
            }
        }
        .task { await model.refreshPermissions() }
    }

    private var locationDone: Bool { model.hasLocation }

    private var needsSettings: Bool {
        model.locationStatus == .denied || model.locationStatus == .restricted
    }

    private var locationDetail: String {
        switch model.locationStatus {
        case .authorizedAlways: "Set to Always. Anchor knows when you leave your spot."
        case .authorizedWhenInUse: "Works. For the best results, choose Always when iOS asks."
        case .denied, .restricted: "Off. Turn it on in Settings > Anchor > Location."
        default: "So Anchor knows where your spot is and when you leave it."
        }
    }

    private func row(done: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Allowed" : "Not allowed yet")
    }
}
