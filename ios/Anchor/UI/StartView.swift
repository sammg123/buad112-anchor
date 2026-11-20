import MapKit
import SwiftUI

/// The start screen: no-phone zones shaded on the map, how long, and either "Start in <zone>" when you're in
/// one or "Drop anchor here" anywhere else.
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
        .onChange(of: model.radiusMeters) { _, _ in recenter() }
        .onChange(of: fixKey) { _, _ in recenter() }
        .onChange(of: model.currentZone?.id) { _, _ in recenter() }
        .onChange(of: model.fix == nil) { _, _ in recenter() }
        .onAppear(perform: recenter)
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(model.zones) { zone in
                MapPolygon(coordinates: zone.polygon.map(\.coordinate))
                    .foregroundStyle(Palette.red.opacity(0.2))
                    .stroke(Palette.red.opacity(0.8), lineWidth: 2)
                Annotation(zone.name, coordinate: zone.center.coordinate, anchor: .center) {
                    ZoneLabel(name: zone.name)
                }
            }
            if model.currentZone == nil, let here = model.fix?.coordinate {
                MapCircle(center: here, radius: AnchorRules.clampedRadius(model.radiusMeters))
                    .foregroundStyle(Palette.blue.opacity(0.14))
                    .stroke(Palette.blue.opacity(0.6), lineWidth: 2)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Text("Anchor")
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCapsule()
            Spacer()
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
            if let zone = model.currentZone {
                ZoneBanner(zone: zone)
            }
            MinutePicker(minutes: minutes)
            if model.currentZone == nil {
                RadiusSlider(radius: radius)
            }
            GraceStepper()
            LibraryToggle()
            if !model.notificationsAllowed || !model.hasPasscode || !model.isPrecise {
                warning
            }
            if model.isFindingSpot {
                FindingSpot()
            } else if let zone = model.currentZone {
                Button { model.startZoneSession(zone.id) } label: {
                    Label { Text("Start in \(zone.name)") } icon: { AnchorMark(size: 22) }
                }
                .buttonStyle(ProminentButtonStyle(color: Palette.red))
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
        Text(!model.isPrecise
             ? "Precise Location is off, so Anchor can't tell where zones start. Turn it on in Settings › Anchor › Location."
             : !model.hasPasscode
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

    /// Frame the zone you're in, or the circle you'd drop, with room around it.
    private func recenter() {
        if let zone = model.currentZone {
            let span = max(zone.wakeRadiusMeters * 2, 200)
            withAnimation(.smooth(duration: 0.35)) {
                camera = .region(MKCoordinateRegion(center: zone.center.coordinate,
                                                    latitudinalMeters: span * 1.6, longitudinalMeters: span))
            }
            return
        }
        guard let here = model.fix?.coordinate else { return }
        let span = AnchorRules.clampedRadius(model.radiusMeters) * 5
        withAnimation(.smooth(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(center: here, latitudinalMeters: span * 1.6, longitudinalMeters: span))
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
            Text("Stop stays locked until you walk out of the circle.")
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
        guard let fix = model.fix, fix.horizontalAccuracy >= 0 else { return "Finding your spot…" }
        return "Finding your spot… GPS within \(Format.meters(fix.horizontalAccuracy))"
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

/// The red "no-phone zone" tag on the map, Lime-style.
struct ZoneLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "iphone.slash").font(.system(size: 10, weight: .bold))
            Text(name).font(.caption2.weight(.bold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Palette.red, in: Capsule())
        .accessibilityLabel("No-phone zone: \(name)")
    }
}

/// "You're in Leavey Library": shown on the start sheet when you stand in a zone.
private struct ZoneBanner: View {
    let zone: Zone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Palette.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("NO-PHONE ZONE").font(.caption.weight(.bold)).tracking(0.4).foregroundStyle(Palette.red)
                Text("You're in \(zone.name)").font(.headline)
                Text("Stop stays locked until you leave it.").font(.footnote).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
