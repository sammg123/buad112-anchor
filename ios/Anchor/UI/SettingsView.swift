import SwiftUI
import UIKit

/// Settings, laid out the way iOS Settings is: what Anchor will do to you (in order, with when each thing starts),
/// the switches that change it, whether iOS has given Anchor what it needs, and buttons to try it all.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showsGraySetup = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                annoyanceSection
                wholeSessionSection
                switchesSection(library: $model.library, grayscale: $model.grayscale)
                if model.grayscale { graySetupSection }
                permissionsSection
                trySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    // MARK: - What happens

    private var annoyanceSection: some View {
        Section {
            TimelineRow(time: "0:00", tint: AnchorPalette.grace, symbol: "hourglass",
                        title: "Grace period, \(Int(model.graceSeconds)) s",
                        detail: "Unlocking is free this long. The island turns gray and counts it down.")
            ForEach(Escalation.annoyances(graceSeconds: model.graceSeconds, library: model.library)) { item in
                TimelineRow(time: "+" + Format.clock(item.startsAt), tint: tint(for: item.startsAt), symbol: item.symbol,
                            title: item.title, detail: item.detail)
            }
        } header: {
            Text("When you pick up your phone")
        } footer: {
            Text("Times are phone time after the grace period. The phone clock never resets during a session, so the next pickup starts where the last one stopped. Lock the phone or open Anchor and all of it stops at once.")
        }
    }

    private var wholeSessionSection: some View {
        Section("The whole session") {
            if !model.library {
                InfoRow(symbol: "speaker.wave.2.fill", tint: .orange, title: "Volume floor",
                        detail: "Volume can't go below 3 of 16 notches.")
            }
            InfoRow(symbol: "lock.iphone", tint: Palette.blue, title: "Lock Screen and Dynamic Island",
                    detail: "Your study clock, grace and phone time, live.")
            InfoRow(symbol: "lock.fill", tint: Palette.ink, title: "Stop is locked",
                    detail: "Until your steps take you out of your circle.")
            if model.grayscale {
                InfoRow(symbol: "circle.lefthalf.filled", tint: .gray, title: "Black and white",
                        detail: "From the moment you drop the anchor until the session ends.")
            }
        }
    }

    // MARK: - Switches

    private func switchesSection(library: Binding<Bool>, grayscale: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: library) {
                RowLabel(symbol: "books.vertical.fill", tint: .brown, title: "Library mode",
                         detail: "Vibration only. No voice, siren, sound or volume floor.")
            }
            Toggle(isOn: grayscale) {
                RowLabel(symbol: "circle.lefthalf.filled", tint: .gray, title: "Black and white while studying",
                         detail: "Your whole screen, for the whole session.")
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Grace period, minutes and lock radius are on the start screen.")
        }
        .tint(Palette.blue)
    }

    private var graySetupSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsGraySetup) {
                step(1, "Settings › Accessibility › Display & Text Size › Color Filters: pick **Grayscale**, then turn Color Filters **off**.")
                step(2, "In Shortcuts, make a shortcut with one action, **Set Color Filters** **On**. Name it **Anchor Gray**.")
                step(3, "Make another, **Set Color Filters** **Off**, named **Anchor Color**.")
                step(4, "Test both below. If Shortcuts asks about Anchor, tap **Always Allow**.")
            } label: {
                RowLabel(symbol: "wand.and.stars", tint: .indigo, title: "One-time setup",
                         detail: "Needed once. Then it runs by itself at start and end.")
            }
        } header: {
            Text("Black and white")
        } footer: {
            Text("Apple doesn't let any app switch Color Filters itself; only Shortcuts can. So Anchor flips to Shortcuts for a split second at the start and end of a session, and comes right back.")
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(Palette.blue).frame(width: 16)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            StatusRow(symbol: "location.fill", tint: Palette.blue, title: "Location", value: locationText,
                      isGood: model.locationStatus == .authorizedAlways)
            StatusRow(symbol: "figure.walk", tint: .green, title: "Motion & Fitness",
                      value: model.motionAllowed ? "On" : "Off", isGood: model.motionAllowed)
            StatusRow(symbol: "bell.badge.fill", tint: .red, title: "Notifications",
                      value: model.notificationsAllowed ? "On" : "Off", isGood: model.notificationsAllowed)
            StatusRow(symbol: "lock.shield.fill", tint: .teal, title: "Phone passcode",
                      value: model.hasPasscode ? "Set" : "Missing", isGood: model.hasPasscode)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Label("Open iPhone Settings for Anchor", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("What Anchor needs")
        } footer: {
            Text("Location works best on Always. Using a Focus? Allow Time Sensitive notifications in it. No vibration? Settings › Sounds & Haptics › Haptics: Always Play.")
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

    // MARK: - Try it

    private var trySection: some View {
        Section("Try it") {
            Button { model.testBuzz() } label: {
                RowLabel(symbol: "iphone.radiowaves.left.and.right", tint: .red, title: "Test buzz",
                         detail: "Arrives in 5 s. Lock the phone or go home to feel it.")
            }
            Button { model.runShortcut(.gray) } label: {
                RowLabel(symbol: "circle.lefthalf.filled", tint: .gray, title: "Test black and white",
                         detail: "Runs your Anchor Gray shortcut.")
            }
            Button { model.runShortcut(.color) } label: {
                RowLabel(symbol: "paintpalette.fill", tint: .orange, title: "Test color",
                         detail: "Runs your Anchor Color shortcut.")
            }
        }
        .foregroundStyle(Palette.ink)
    }

    /// Later annoyances are redder.
    private func tint(for startsAt: Double) -> Color {
        switch startsAt {
        case ..<15: Palette.red.opacity(0.75)
        case ..<30: Color(red: 0.9, green: 0.42, blue: 0.11)
        case ..<60: Color(red: 0.85, green: 0.28, blue: 0.12)
        default: Color(red: 0.56, green: 0.08, blue: 0.08)
        }
    }
}

// MARK: - Rows

/// The colored rounded-square icon of iOS Settings.
private struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct RowLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InfoRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        RowLabel(symbol: symbol, tint: tint, title: title, detail: detail)
            .accessibilityElement(children: .combine)
    }
}

/// One step of the escalation: when it starts, then what it is.
private struct TimelineRow: View {
    let time: String
    let tint: Color
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 22)
                .background(tint, in: Capsule())
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.body.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Palette.ink)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct StatusRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let isGood: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            Text(title)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isGood ? Palette.away : Palette.red)
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGood ? Palette.away : Palette.red)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
