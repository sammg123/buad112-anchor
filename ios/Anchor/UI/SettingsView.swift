import SwiftUI
import UIKit

/// Black and white lives here, off the start screen. iOS gives apps no way to turn the screen gray, so the
/// student makes two one-step shortcuts once.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Toggle("Black and white while studying", isOn: $model.grayscale)
                } footer: {
                    Text("Anchor runs your \"Anchor Gray\" shortcut when a session starts and \"Anchor Color\" when it ends.")
                }
                Section("Set up black and white (once)") {
                    step(1, "Settings › Accessibility › Display & Text Size › Color Filters: pick **Grayscale**, then turn Color Filters back **off**.")
                    step(2, "In Shortcuts, make a shortcut with one action, **Set Color Filters** to **On**. Name it **Anchor Gray**.")
                    step(3, "Make another: **Set Color Filters** to **Off**, named **Anchor Color**.")
                    step(4, "Test both. If Shortcuts asks to allow Anchor, tap **Always Allow**.")
                    Button("Test black and white") { model.runShortcut(.gray) }
                    Button("Test color") { model.runShortcut(.color) }
                }
                Section("So Anchor can do its job") {
                    LabeledContent("Location", value: locationText)
                    LabeledContent("Motion & Fitness", value: model.motionAllowed ? "On" : "Off (required)")
                    LabeledContent("Notifications", value: model.notificationsAllowed ? "On" : "Off")
                    LabeledContent("Phone passcode", value: model.hasPasscode ? "Set" : "Missing")
                    Text("Using a Focus? Anchor's buzzes are Time Sensitive. Allow Time Sensitive notifications in that Focus.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var locationText: String {
        switch model.locationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied, .restricted: "Off"
        default: "Not set"
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.headline).foregroundStyle(Palette.blue)
            Text(text).font(.subheadline)
        }
    }
}
