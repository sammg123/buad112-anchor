import MapKit
import SwiftUI

/// The start screen: drop an anchor anywhere (your radius around you), draw your own area on the map, or, in a
/// no-phone zone's study area, start there. The sheet drags down out of the way to show the whole map.
struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingSettings = false
    /// The map follows you until you pinch or drag it yourself.
    @State private var isFollowing = true
    /// Your +/− zoom while it follows, as a scale on its own framing.
    @State private var zoomScale = 1.0
    @State private var visibleRegion: MKCoordinateRegion?
    /// Where a zoom tap is heading, so a second tap mid-animation goes one step further rather than repeating.
    @State private var zoomTarget: MKCoordinateRegion?
    @Namespace private var mapScope
    /// The sheet dragged down to a slim bar, so the whole map shows.
    @State private var isSheetCollapsed = false
    /// Corners of the area being drawn; nil when not drawing.
    @State private var drawing: [GeoPoint]?
    @State private var isNamingArea = false
    @State private var areaName = ""

    var body: some View {
        @Bindable var model = model
        ZStack {
            map
            if let points = drawing {
                VStack(spacing: 10) {
                    DrawingHeader(points: points)
                    HStack {
                        MapScaleBar(scope: mapScope)
                        Spacer()
                        zoomButtons
                    }
                    Spacer()
                    DrawingToolbar(points: points,
                                   undo: { drawing = Array(points.dropLast()) },
                                   clear: { drawing = [] },
                                   cancel: { endDrawing() },
                                   save: {
                                       areaName = DrawnArea.defaultName(existing: model.userZones)
                                       isNamingArea = true
                                   })
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if isSheetCollapsed {
                        collapsedBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        sheet(minutes: $model.minutes, radius: $model.radiusMeters)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: isSheetCollapsed)
        .animation(.smooth(duration: 0.25), value: drawing == nil)
        .mapScope(mapScope)
        .alert("Name this area", isPresented: $isNamingArea) {
            TextField("Name", text: $areaName)
            Button("Save") { saveArea() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Inside it, Anchor locks your phone. It's saved for next time too.")
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-settings") { showingSettings = true } }
        .task {
            // Simulator only: "-zoomTaps 2" presses + twice (negative: −) after the map settles.
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-zoomTaps"), i + 1 < args.count, let taps = Int(args[i + 1]) else { return }
            do {
                try await Task.sleep(for: .seconds(6))
                for _ in 0..<min(abs(taps), 10) {
                    zoom(in: taps > 0)
                    try await Task.sleep(for: .seconds(1))
                }
            } catch {
                return
            }
        }
        #endif
        .onChange(of: fixKey) { _, _ in recenter() }
        .onChange(of: model.radiusMeters) { _, _ in recenter() }
        .onChange(of: model.place.zone?.id) { _, _ in recenter() }
        .onChange(of: model.fix == nil) { _, _ in recenter() }
        .onChange(of: isSheetCollapsed) { _, _ in recenter() }
        .onAppear { recenter() }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom], scope: mapScope) {
                mapContent
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                zoomTarget = nil
                if camera.positionedByUser { isFollowing = false }
            }
            // While drawing, each tap on the map adds a corner.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
                guard let points = drawing, points.count < DrawnArea.maxPoints,
                      let coordinate = proxy.convert(tap.location, from: .local) else { return }
                drawing = points + [GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude)]
            }, including: drawing == nil ? .subviews : .all)
            .sensoryFeedback(.impact(weight: .light), trigger: drawing?.count ?? 0)
        }
        .ignoresSafeArea()
    }

    @MapContentBuilder
    private var mapContent: some MapContent {
        ZoneLayers(zones: model.tracker.zones, userAreaTint: Palette.blue, accuracy: model.tracker.accuracyCircle)
        if let drawing {
            DrawnShapeLayers(points: drawing)
        } else if model.startable == nil, let here = model.fix?.coordinate {
                // The circle "Drop anchor here" would lock.
                MapCircle(center: here, radius: AnchorRules.clampedRadius(model.radiusMeters))
                    .foregroundStyle(Palette.blue.opacity(0.12))
                    .stroke(Palette.blue.opacity(0.6), lineWidth: 2)
            Annotation("", coordinate: here, anchor: .bottom) {
                Text("\(Int(AnchorRules.clampedRadius(model.radiusMeters))) m")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.blue, in: Capsule())
                    .offset(y: -22)
                    .accessibilityLabel("Your circle: \(Int(AnchorRules.clampedRadius(model.radiusMeters))) meters")
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                PlaceStatusLine(place: model.place)
                MapScaleBar(scope: mapScope)
            }
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                }
                .accessibilityLabel("Settings")
                zoomButtons
            }
        }
        .padding(.top, 8)
    }

    private var zoomButtons: some View {
        MapZoomButtons(canZoomIn: canZoom(in: true), canZoomOut: canZoom(in: false),
                       showsRecenter: !isFollowing, recenterLabel: "Back to where you are",
                       zoom: zoom(in:), recenter: { recenter(force: true) })
    }

    /// The grabber: drag down (or tap) to shrink the sheet to a bar and see the whole map.
    private var handle: some View {
        Capsule()
            .fill(Palette.secondary.opacity(0.45))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture { isSheetCollapsed.toggle() }
            .gesture(DragGesture(minimumDistance: 10).onEnded { drag in
                if drag.translation.height > 40 { isSheetCollapsed = true }
                if drag.translation.height < -40 { isSheetCollapsed = false }
            })
            .accessibilityElement()
            .accessibilityLabel(isSheetCollapsed ? "Show options" : "Hide options and show the map")
            .accessibilityAddTraits(.isButton)
    }

    /// The sheet shrunk down: the essentials in one row.
    private var collapsedBar: some View {
        VStack(spacing: 4) {
            handle
            if model.isFindingSpot {
                FindingSpot()
            } else {
                collapsedActions
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .glassPanel(cornerRadius: 30)
    }

    private var collapsedActions: some View {
            HStack(spacing: 10) {
                Button { isSheetCollapsed = false } label: {
                    Label("\(model.minutes) min", systemImage: "chevron.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Button(action: startDrawing) {
                    Label("Draw", systemImage: "pencil.and.outline")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.white.opacity(0.7), in: Capsule())
                }
                .foregroundStyle(Palette.blue)
                if let here = model.startable {
                    Button { model.startZoneSession(here.zone.id) } label: {
                        Label("Start", systemImage: "anchor")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Palette.red, in: Capsule())
                    }
                    .foregroundStyle(.white)
                } else {
                    Button(action: model.dropAnchor) {
                        Label("Drop anchor", systemImage: "anchor")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Palette.blue, in: Capsule())
                    }
                    .foregroundStyle(.white)
                }
            }
    }

    private func startDrawing() {
        isFollowing = false
        isSheetCollapsed = false
        drawing = []
    }

    private func endDrawing() {
        drawing = nil
        recenter(force: true)
    }

    private func saveArea() {
        guard let points = drawing else { return }
        if let problem = model.saveDrawnArea(name: areaName, points: points) {
            model.notice = problem.hint
            return
        }
        drawing = nil
        isFollowing = true
        recenter()
    }

    private func sheet(minutes: Binding<Int>, radius: Binding<Double>) -> some View {
        VStack(spacing: 22) {
            handle
                .padding(.top, -14)
                .padding(.bottom, -12)
            // Only where you can start in a zone; otherwise the status line up top already says where you are.
            if model.startable != nil {
                PlaceCard(place: model.place)
            }
            MinutePicker(minutes: minutes)
            if model.startable == nil {
                RadiusSlider(radius: radius, margin: model.gpsMargin)
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
            if !model.isFindingSpot {
                Button(action: startDrawing) {
                    Label("Draw your own area on the map", systemImage: "pencil.and.outline")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Palette.blue)
                .padding(.top, -14)
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
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Changes when the fix moves about 10 m, so the map follows you without jittering.
    private var fixKey: String {
        guard let c = model.fix?.coordinate else { return "none" }
        return String(format: "%.4f,%.4f", c.latitude, c.longitude)
    }

    /// How far above the map's center (as a share of its width) the visible part sits: well up with the sheet
    /// open, nearly centered with it down.
    private var sheetFocusShare: Double { isSheetCollapsed || drawing != nil ? 0.08 : 0.45 }

    /// What following frames: the zone you're in, or you with your circle, and how wide.
    private var followTarget: (center: CLLocationCoordinate2D, span: Double)? {
        model.place.zone.map { ($0.center.coordinate, max($0.wakeRadiusMeters * 2, 200)) }
            ?? model.fix.map { ($0.coordinate, max(AnchorRules.clampedRadius(model.radiusMeters) * 5, 150)) }
    }

    private func canZoom(in zoomingIn: Bool) -> Bool {
        if isFollowing, let base = followTarget?.span { return MapZoom.canZoom(span: base * zoomScale, zoomingIn: zoomingIn) }
        guard let visibleRegion else { return true }
        return MapZoom.canZoom(span: MapZoom.spanMeters(of: visibleRegion), zoomingIn: zoomingIn)
    }

    /// + or −: while following, the zoom sticks as you move; after you've moved the map, it zooms where you are
    /// looking.
    private func zoom(in zoomingIn: Bool) {
        if isFollowing, let base = followTarget?.span {
            zoomScale = MapZoom.scale(zoomScale, base: base, zoomingIn: zoomingIn)
            recenter()
        } else if let from = zoomTarget ?? visibleRegion {
            let span = MapZoom.span(MapZoom.spanMeters(of: from), zoomingIn: zoomingIn)
            // The sheet covers the bottom: keep the part you can see in place, as following does.
            let target = MapZoom.region(from, spanMeters: span, focusShare: sheetFocusShare)
            zoomTarget = target
            withAnimation(.smooth(duration: 0.3)) { camera = .region(target) }
        }
    }

    /// Frame the zone you're in, or follow you, with room around it. Once you've moved the map yourself it stays
    /// put until you tap the location button (`force`), which also resets the zoom.
    private func recenter(force: Bool = false) {
        if force {
            isFollowing = true
            zoomScale = 1
        }
        guard isFollowing, let (center, base) = followTarget else { return }
        let span = base * zoomScale
        // The sheet covers the lower half: aim below the target so it sits in the open top part of the map.
        let shifted = CLLocationCoordinate2D(latitude: center.latitude - span * sheetFocusShare / 111_195,
                                             longitude: center.longitude)
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
    /// GPS error right now, if known.
    let margin: Double?

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
            Text(margin.map { "Your anchor drops where you stand. Walk past the edge to unlock Stop (GPS ±\(Int($0.rounded(.up))) m here)." }
                 ?? "Your anchor drops where you stand. Walk past the edge to unlock Stop.")
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
