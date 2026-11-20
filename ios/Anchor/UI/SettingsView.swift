import SwiftUI
import UIKit

/// Settings, laid out the way iOS Settings is: what Anchor will do to you (in order, with when each thing starts),
/// the switches that change it, whether iOS has given Anchor what it needs, and buttons to try it all.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                annoyanceSection
                wholeSessionSection
                switchesSection(library: $model.library, autoStart: $model.autoStart)
                myAreasSection
                grayscaleSection
                permissionsSection
                trySection
                if AppModel.showsDevTools { developerSection }
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
                        detail: "Every unlock is free this long, however much phone time you've used. After it, the alarms pick up where your phone time left off.")
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
                    detail: "Until you leave the study area (its beacon) or the building (GPS).")
        }
    }

    // MARK: - Switches

    private func switchesSection(library: Binding<Bool>, autoStart: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: autoStart) {
                RowLabel(symbol: "bolt.fill", tint: Palette.red, title: "Auto-start",
                         detail: "Walk into a study area and the session starts by itself. Off: Anchor asks first.")
            }
            Toggle(isOn: library) {
                RowLabel(symbol: "books.vertical.fill", tint: .brown, title: "Library mode",
                         detail: "Vibration only. No voice, siren, sound or volume floor.")
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Grace period and minutes are on the start screen.")
        }
        .tint(Palette.blue)
    }

    /// Areas you drew on the map: swipe to delete.
    private var myAreasSection: some View {
        Section {
            if model.userZones.isEmpty {
                Text("None yet. On the start screen, tap **Draw your own area on the map** and tap its corners.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.userZones) { zone in
                RowLabel(symbol: "pencil.and.outline", tint: Palette.blue, title: zone.name,
                         detail: "\(zone.polygon.count) corners · about \(Int(DrawnArea.squareMeters(zone.polygon).rounded())) m²")
            }
            .onDelete { offsets in
                model.deleteUserZones(Set(offsets.map { model.userZones[$0].id }))
            }
        } header: {
            Text("My areas")
        } footer: {
            Text("Inside any of these, Anchor locks your phone, like the library's study areas. Swipe left to delete.")
        }
    }

    /// Apple lets no app switch the screen to black and white; the side button can, instantly.
    private var grayscaleSection: some View {
        Section {
            step(1, "Open **Settings › Accessibility › Display & Text Size › Color Filters**, pick **Grayscale**, then turn Color Filters back **off**.")
            step(2, "Open **Settings › Accessibility › Accessibility Shortcut** and check **Color Filters**.")
            step(3, "Now **triple-click the side button** to go black and white when you sit down, and again to get color back.")
        } header: {
            Text("Black and white")
        } footer: {
            Text("iOS doesn't let apps turn on black and white, so Anchor leaves it to the side button: no app switching, and it works anywhere.")
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
            StatusRow(symbol: "scope", tint: .indigo, title: "Precise Location",
                      value: model.isPrecise ? "On" : "Off", isGood: model.isPrecise)
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
            Text("Location on Always lets Anchor notice when you walk into a zone. Using a Focus? Allow Time Sensitive notifications in it. No vibration? Settings › Sounds & Haptics › Haptics: Always Play.")
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
        }
        .foregroundStyle(Palette.ink)
    }

    // MARK: - Developer

    private var developerSection: some View {
        Section {
            NavigationLink {
                BeaconModeView()
            } label: {
                RowLabel(symbol: "dot.radiowaves.left.and.right", tint: .blue, title: "Beacon mode",
                         detail: "Make this iPhone a study area's beacon, for demos.")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("TestFlight builds only.")
        }
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
