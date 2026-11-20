import MapKit
import SwiftUI

/// The start screen: drop an anchor anywhere (your radius around you), or, in a no-phone zone's study area,
/// start there. Zones are shaded on the map, with where you are.
struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingSettings = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            map
            VStack(spacing: 0) {
                topBar
                Spacer()
                sheet(minutes: $model.minutes, radius: $model.radiusMeters)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-settings") { showingSettings = true } }
        #endif
        .onChange(of: fixKey) { _, _ in recenter() }
        .onChange(of: model.radiusMeters) { _, _ in recenter() }
        .onChange(of: model.place.zone?.id) { _, _ in recenter() }
        .onChange(of: model.fix == nil) { _, _ in recenter() }
        .onAppear(perform: recenter)
    }

    private var map: some View {
        Map(position: $camera) {
            ZoneLayers(zones: model.tracker.zones, accuracy: model.tracker.accuracyCircle)
            if model.startable == nil, let here = model.fix?.coordinate {
                // The circle "Drop anchor here" would lock.
                MapCircle(center: here, radius: AnchorRules.clampedRadius(model.radiusMeters) + model.anchorMargin)
                    .foregroundStyle(Palette.blue.opacity(0.12))
                    .stroke(Palette.blue.opacity(0.6), lineWidth: 2)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            PlaceStatusLine(place: model.place)
            Spacer(minLength: 8)
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .glassCircle()
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private func sheet(minutes: Binding<Int>, radius: Binding<Double>) -> some View {
        VStack(spacing: 22) {
            if model.place.zone != nil {
                PlaceCard(place: model.place)
            }
            MinutePicker(minutes: minutes)
            if model.startable == nil {
                RadiusSlider(radius: radius, margin: model.anchorMargin)
            }
            GraceStepper()
            LibraryToggle()
            if !model.notificationsAllowed || !model.hasPasscode {
                warning
            }
            if model.isFindingSpot {
                FindingSpot()
            } else if let here = model.startable {
                VStack(spacing: 6) {
                    Button { model.startZoneSession(here.zone.id) } label: {
                        Label { Text("Start in \(here.area?.name ?? here.zone.name)") } icon: { AnchorMark(size: 22) }
                    }
                    .buttonStyle(ProminentButtonStyle(color: Palette.red))
                    Button("Drop my own anchor instead (\(Int(AnchorRules.clampedRadius(model.radiusMeters))) m)", action: model.dropAnchor)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.blue)
                        .frame(minHeight: 44)
                }
            } else {
                Button(action: model.dropAnchor) {
                    Label { Text("Drop anchor here") } icon: { AnchorMark(size: 22) }
                }
                .buttonStyle(ProminentButtonStyle())
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .glassPanel(cornerRadius: 38)
    }

    private var warning: some View {
        Text(!model.hasPasscode
             ? "Set a phone passcode, or Anchor can't tell when your phone is locked."
             : "Notifications are off, so Anchor can't buzz you. Turn them on in Settings.")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Changes when the fix moves about 10 m, so the map follows you without jittering.
    private var fixKey: String {
        guard let c = model.fix?.coordinate else { return "none" }
        return String(format: "%.4f,%.4f", c.latitude, c.longitude)
    }

    /// Frame the zone you're in, or follow you, with room around it.
    private func recenter() {
        let target = model.place.zone.map { ($0.center.coordinate, max($0.wakeRadiusMeters * 2, 200)) }
            ?? model.fix.map { ($0.coordinate, max(AnchorRules.clampedRadius(model.radiusMeters) * 5, 150)) }
        guard let (center, span) = target else { return }
        // The sheet covers the lower half: aim below the target so it sits in the open top part of the map.
        let shifted = CLLocationCoordinate2D(latitude: center.latitude - span * 0.45 / 111_195, longitude: center.longitude)
        withAnimation(.smooth(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(center: shifted, latitudinalMeters: span * 1.6, longitudinalMeters: span))
        }
    }
}

private struct MinutePicker: View {
    @Binding var minutes: Int

    var body: some View {
        VStack(spacing: 8) {
            Text("Study for").font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary)
            HStack(spacing: 22) {
                stepButton("minus", delta: -5, label: "Five minutes less")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(minutes)")
                        .font(.system(size: 64, weight: .bold).monospacedDigit())
                        .tracking(-2)
                        .contentTransition(.numericText(value: Double(minutes)))
                    Text("min").font(.headline).foregroundStyle(Palette.secondary)
                }
                .frame(minWidth: 128)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(minutes) minutes")
                stepButton("plus", delta: 5, label: "Five minutes more")
            }
            HStack(spacing: 8) {
                ForEach(SetupInput.presets, id: \.self) { preset in
                    Button("\(preset)") { withAnimation(.snappy) { minutes = preset } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 56, minHeight: 34)
                        .foregroundStyle(preset == minutes ? .white : Palette.ink)
                        .background(preset == minutes ? Palette.ink : Color.secondary.opacity(0.14), in: Capsule())
                        .accessibilityLabel("\(preset) minutes")
                        .accessibilityAddTraits(preset == minutes ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: minutes)
    }

    private func stepButton(_ symbol: String, delta: Int, label: String) -> some View {
        Button {
            withAnimation(.snappy) { minutes = SetupInput.stepped(minutes, by: delta) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 48, height: 48)
                .glassCircle()
        }
        .accessibilityLabel(label)
    }
}

private struct RadiusSlider: View {
    @Binding var radius: Double
    /// GPS accuracy right now: the circle you'd get is this much wider.
    let margin: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lock radius").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(AnchorRules.clampedRadius(radius))) m")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.blue)
            }
            Slider(value: $radius, in: AnchorRules.minRadiusMeters...AnchorRules.maxRadiusMeters,
                   step: AnchorRules.radiusStepMeters)
                .tint(Palette.blue)
                .accessibilityLabel("Lock radius")
                .accessibilityValue("\(Int(radius)) meters")
            Text(margin >= 1
                 ? "Stop stays locked until you walk out of the circle. GPS adds \(Int(margin.rounded(.up))) m here."
                 : "Stop stays locked until you walk out of the circle.")
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
        }
        .sensoryFeedback(.selection, trigger: radius)
    }
}

private struct FindingSpot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                Text(text).font(.subheadline.weight(.semibold))
            }
            Button("Cancel", action: model.cancelFindingSpot)
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
    }

    private var text: String {
        let label = model.isDroppingAnchor ? "Finding your spot…" : "Checking you're in the zone…"
        guard let fix = model.fix, fix.horizontalAccuracy >= 0 else { return label }
        return "\(label) GPS within \(Format.meters(fix.horizontalAccuracy))"
    }
}

private struct LibraryToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle(isOn: $model.library) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library mode").font(.subheadline.weight(.semibold))
                Text(model.library ? "Vibration only. No voice, alarm or sound." : "Off: voice, alarm, and volume stays up.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .tint(Palette.blue)
    }
}

/// How long you can be unlocked and out of Anchor before it counts, so glancing at the Lock Screen is free.
private struct GraceStepper: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grace period").font(.subheadline.weight(.semibold))
                Text("Free time after unlocking").font(.footnote).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            step("minus", by: -PickupRule.graceStepSeconds, label: "Shorter grace period")
            Text("\(Int(model.graceSeconds)) s")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.blue)
                .frame(minWidth: 40)
                .accessibilityLabel("Grace period \(Int(model.graceSeconds)) seconds")
            step("plus", by: PickupRule.graceStepSeconds, label: "Longer grace period")
        }
        .sensoryFeedback(.selection, trigger: model.graceSeconds)
    }

    private func step(_ symbol: String, by delta: Double, label: String) -> some View {
        Button {
            model.graceSeconds = PickupRule.steppedGrace(model.graceSeconds, by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .glassCircle()
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
    }
}
