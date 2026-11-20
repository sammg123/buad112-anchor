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
    /// Corners of the area being drawn, in outline order; nil when not drawing.
    @State private var drawing: [GeoPoint]?
    /// The outline before each tap, so Undo takes back your last tap wherever it went in the outline.
    @State private var drawingHistory: [[GeoPoint]] = []
    @State private var isNamingArea = false
    /// Your area picked by holding or tapping it: the glass bar offers edit and delete.
    @State private var selectedAreaID: String?
    /// Corners of the selected area while you drag them; nil when not editing.
    @State private var editingPoints: [GeoPoint]?
    @State private var draggingCorner: Int?
    /// Where on the corner your finger grabbed it, so the corner doesn't jump under your fingertip.
    @State private var grabOffset: CGSize?
    @State private var isConfirmingDelete = false
    /// Where the current touch on the map began, for picking an area by holding it.
    @State private var touchDown: CGPoint?
    @State private var areaName = ""

    var body: some View {
        @Bindable var model = model
        ZStack {
            map
            if let points = editingPoints {
                VStack(spacing: 10) {
                    HStack(alignment: .top) {
                        MapScaleBar(scope: mapScope)
                        Spacer()
                        zoomButtons
                    }
                    Spacer()
                    EditToolbar(points: points, cancel: { editingPoints = nil }, save: saveEdit)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .transition(.opacity)
            } else if let points = drawing {
                VStack(spacing: 10) {
                    DrawingHeader(points: points)
                    HStack {
                        MapScaleBar(scope: mapScope)
                        Spacer()
                        zoomButtons
                    }
                    Spacer()
                    DrawingToolbar(points: points,
                                   undo: {
                                       drawing = drawingHistory.last ?? []
                                       drawingHistory = Array(drawingHistory.dropLast())
                                   },
                                   clear: {
                                       drawing = []
                                       drawingHistory = []
                                   },
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
                    CollapsibleCard(edge: .bottom, isCollapsed: $isSheetCollapsed, cornerRadius: 34,
                                    expandLabel: "Show options", collapseLabel: "Hide options and show the map") {
                        sheet(minutes: $model.minutes, radius: $model.radiusMeters)
                    } compact: {
                        collapsedBar
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .overlay {
            if isConfirmingDelete, let area = selectedArea {
                DeleteAreaConfirm(name: area.name, cancel: { isConfirmingDelete = false }, delete: deleteSelected)
            }
        }
        .animation(.smooth(duration: 0.25), value: isConfirmingDelete)
        .animation(.smooth(duration: 0.25), value: selectedAreaID)
        .animation(.smooth(duration: 0.25), value: editingPoints == nil)
        .sensoryFeedback(.selection, trigger: selectedAreaID)
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
            // While you drag corners the map holds still, so the drag moves the corner, not the map.
            Map(position: $camera, interactionModes: editingPoints == nil ? [.pan, .zoom] : [], scope: mapScope) {
                mapContent(proxy)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                zoomTarget = nil
                if camera.positionedByUser { isFollowing = false }
            }
            // Drawing: each tap adds a corner. Otherwise a tap picks (or lets go of) one of your areas.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
                guard let coordinate = proxy.convert(tap.location, from: .local) else { return }
                let point = GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude)
                if let points = drawing {
                    if points.count < DrawnArea.maxPoints {
                        drawingHistory = drawingHistory + [points]
                        drawing = DrawnArea.inserting(point, into: points)
                    }
                    return
                }
                select(at: point)
            }, including: editingPoints == nil ? .all : .subviews)
            // Holding on one of your areas picks it too: remember where the finger went down, and pick there once
            // the hold completes.
            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { touch in touchDown = touch.startLocation }
                .onEnded { _ in touchDown = nil },
                including: drawing == nil && editingPoints == nil ? .all : .subviews)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard drawing == nil, editingPoints == nil, let touchDown,
                      let coordinate = proxy.convert(touchDown, from: .local) else { return }
                select(at: GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude))
            }, including: drawing == nil && editingPoints == nil ? .all : .subviews)
            .sensoryFeedback(.impact(weight: .light), trigger: drawing?.count ?? 0)
        }
        .ignoresSafeArea()
    }

    @MapContentBuilder
    private func mapContent(_ proxy: MapProxy) -> some MapContent {
        ZoneLayers(zones: model.tracker.zones.filter { $0.id != selectedAreaID }, userAreaTint: Palette.blue, you: model.you)
        if let editingPoints {
            SelectedAreaLayers(points: editingPoints)
            ForEach(Array(editingPoints.enumerated()), id: \.offset) { index, point in
                Annotation("", coordinate: point.coordinate, anchor: .center) {
                    CornerHandle(number: index + 1, isDragging: draggingCorner == index)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { drag in moveCorner(index, to: drag.location, proxy: proxy) }
                            .onEnded { _ in
                                draggingCorner = nil
                                grabOffset = nil
                            })
                }
            }
        } else if let area = selectedArea {
            SelectedAreaLayers(points: area.polygon)
        }
        if let drawing {
            DrawnShapeLayers(points: drawing)
        } else if model.startable == nil, let here = model.you?.center.coordinate {
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
        VStack(alignment: .trailing, spacing: 10) {
            // A selected area's glass bar gets its own row, top right, so nothing gets squeezed.
            if let area = selectedArea {
                AreaActionBar(name: area.name,
                              edit: { editingPoints = area.polygon; isFollowing = false },
                              delete: { isConfirmingDelete = true },
                              close: { selectedAreaID = nil })
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    PlaceStatusLine(place: model.place)
                    MapScaleBar(scope: mapScope)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    if selectedArea == nil {
                        Button { showingSettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 44, height: 44)
                                .glassCircle()
                        }
                        .accessibilityLabel("Settings")
                    }
                    zoomButtons
                }
            }
        }
        .padding(.top, 8)
    }

    private var zoomButtons: some View {
        MapZoomButtons(canZoomIn: canZoom(in: true), canZoomOut: canZoom(in: false),
                       showsRecenter: !isFollowing, recenterLabel: "Back to where you are",
                       zoom: zoom(in:), recenter: { recenter(force: true) })
    }

    /// The sheet shrunk down: the essentials in one row.
    private var collapsedBar: some View {
        Group {
            if model.isFindingSpot {
                FindingSpot()
            } else {
                collapsedActions
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var collapsedActions: some View {
            HStack(spacing: 10) {
                Button { withAnimation(CollapsibleCard<EmptyView, EmptyView>.spring) { isSheetCollapsed = false } } label: {
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

    private var selectedArea: Zone? {
        model.userZones.first { $0.id == selectedAreaID }
    }

    /// Picks your area under the point (and moves the sheet out of the way), or lets go if there's none.
    private func select(at point: GeoPoint) {
        guard let area = DrawnArea.area(at: point, in: model.userZones) else {
            selectedAreaID = nil
            return
        }
        selectedAreaID = area.id
        withAnimation(CollapsibleCard<EmptyView, EmptyView>.spring) { isSheetCollapsed = true }
    }

    private func moveCorner(_ index: Int, to location: CGPoint, proxy: MapProxy) {
        guard let points = editingPoints, points.indices.contains(index) else { return }
        if draggingCorner != index || grabOffset == nil,
           let corner = proxy.convert(points[index].coordinate, to: .global) {
            grabOffset = CGSize(width: location.x - corner.x, height: location.y - corner.y)
        }
        let target = CGPoint(x: location.x - (grabOffset?.width ?? 0), y: location.y - (grabOffset?.height ?? 0))
        guard let coordinate = proxy.convert(target, from: .global) else { return }
        draggingCorner = index
        let moved = GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude)
        editingPoints = points.enumerated().map { $0.offset == index ? moved : $0.element }
    }

    private func saveEdit() {
        guard let id = selectedAreaID, let points = editingPoints else { return }
        if let problem = model.reshapeUserZone(id, to: points) {
            model.notice = problem
            return
        }
        editingPoints = nil
    }

    private func deleteSelected() {
        guard let id = selectedAreaID else { return }
        model.deleteUserZones([id])
        isConfirmingDelete = false
        selectedAreaID = nil
    }

    private func startDrawing() {
        selectedAreaID = nil
        isFollowing = false
        isSheetCollapsed = false
        drawingHistory = []
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
            if model.startable == nil, !model.motionAllowed {
                motionPrompt
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
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    /// Without Motion & Fitness your anchor runs on GPS alone, which needs the extra margin (25 m becomes ~33 m).
    @ViewBuilder
    private var motionPrompt: some View {
        if model.motionDenied {
            Text("Turn on Motion & Fitness in Settings › Anchor to make your 25 m exact.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                Task { await model.requestMotion() }
            } label: {
                Label("Make 25 m exact: allow Motion & Fitness", systemImage: "figure.walk")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Palette.blue)
        }
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

/// Waiting for sharp GPS before dropping the anchor ("Locking on… ±32 m, need ±15 m"), or for proof you're in a
/// zone. After 15 s it offers dropping on what there is.
private struct FindingSpot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isDroppingAnchor ? "Locking on to where you are…" : "Checking you're in the zone…")
                        .font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote.monospacedDigit()).foregroundStyle(Palette.secondary)
                }
            }
            HStack(spacing: 10) {
                Button("Cancel", action: model.cancelFindingSpot)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                if showsDropAnyway {
                    Button("Drop anyway", action: model.dropAnchorAnyway)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.7), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.25), value: showsDropAnyway)
    }

    private var detail: String {
        guard let fix = model.fix, fix.horizontalAccuracy >= 0 else { return "Waiting for GPS" }
        let now = "GPS ±\(Int(fix.horizontalAccuracy.rounded())) m"
        return model.isDroppingAnchor ? "\(now), need ±\(Int(ZoneTracker.lockOnMeters)) m" : now
    }

    private var showsDropAnyway: Bool {
        guard model.isDroppingAnchor, let started = model.dropWaitStarted else { return false }
        return model.now.timeIntervalSince(started) >= AppModel.dropAnywayAfterSeconds
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
