import MapKit
import SwiftUI

/// A running session: the countdown on glass over the map, the zone shaded, Stop locked until you leave it.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic
    /// The map frames your spot until you pinch, drag, or zoom it yourself.
    @State private var isFramed = true
    @State private var visibleRegion: MKCoordinateRegion?
    /// Where a zoom tap is heading, so a second tap mid-animation goes one step further.
    @State private var zoomTarget: MKCoordinateRegion?
    @Namespace private var mapScope

    var body: some View {
        ZStack {
            if let session = model.live {
                map(session)
                VStack(spacing: 0) {
                    TimerCard(session: session)
                    mapControls(session)
                    Spacer()
                    if model.isPaused {
                        AwayCard(session: session, paused: true)
                    } else {
                        VStack(spacing: 10) {
                            notificationsWarning
                            ZoneCard(session: session)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .animation(.smooth(duration: 0.35), value: session.away)
                .onAppear { frame(session) }
            }
        }
        .mapScope(mapScope)
    }

    private func mapControls(_ session: Session) -> some View {
        let span = visibleRegion.map(MapZoom.spanMeters(of:))
        return HStack(alignment: .top) {
            MapScaleBar(scope: mapScope)
            Spacer()
            MapZoomButtons(canZoomIn: span.map { MapZoom.canZoom(span: $0, zoomingIn: true) } ?? true,
                           canZoomOut: span.map { MapZoom.canZoom(span: $0, zoomingIn: false) } ?? true,
                           showsRecenter: !isFramed,
                           recenterLabel: session.isDroppedAnchor ? "Back to your spot" : "Back to the zone",
                           zoom: zoom(in:), recenter: { frame(session) })
        }
        .padding(.top, 10)
    }

    private func zoom(in zoomingIn: Bool) {
        guard let from = zoomTarget ?? visibleRegion else { return }
        let target = MapZoom.region(from, spanMeters: MapZoom.span(MapZoom.spanMeters(of: from), zoomingIn: zoomingIn))
        zoomTarget = target
        isFramed = false
        withAnimation(.smooth(duration: 0.3)) { camera = .region(target) }
    }

    private func map(_ session: Session) -> some View {
        let away = session.away
        let tint = away ? Palette.away : (session.isDroppedAnchor || session.area.isUserArea ? Palette.blue : Palette.red)
        return Map(position: $camera, interactionModes: [.pan, .zoom], scope: mapScope) {
            // Every area locks during a session, so they're all on the map.
            ZoneLayers(zones: model.tracker.zones.filter { $0.id != session.area.id }, userAreaTint: Palette.blue, you: nil)
            ZoneLayers(zones: [session.area], tint: tint, you: model.you)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            zoomTarget = nil
            if camera.positionedByUser { isFramed = false }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var notificationsWarning: some View {
        if !model.notificationsAllowed {
            Text("Notifications are off, so Anchor can't buzz you")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassCapsule()
        }
    }

    private func frame(_ session: Session) {
        let span = max(session.area.wakeRadiusMeters * 2.5, 200)
        isFramed = true
        withAnimation(.smooth(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(center: session.area.center.coordinate,
                                                latitudinalMeters: span * 1.6, longitudinalMeters: span))
        }
    }
}

private struct TimerCard: View {
    @Environment(AppModel.self) private var model
    let session: Session
    /// Swiped up to just the timer, so the map shows full screen.
    @State private var isCompact = false

    var body: some View {
        CollapsibleCard(edge: .top, isCollapsed: $isCompact, cornerRadius: 36,
                        expandLabel: "Show the full timer", collapseLabel: "Shrink to just the timer") {
            full
        } compact: {
            compact
        }
    }

    /// Just the timer.
    private var compact: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(Format.clock(session.remainingSeconds))
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                Text(session.away ? "paused" : "left")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                status
                Spacer()
                if AppModel.showsDevTools {
                    Button(model.isPaused ? "Resume" : "Pause", action: model.togglePause)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Palette.ink.opacity(0.08), in: Capsule())
                        .accessibilityHint("Developer pause for testing")
                } else {
                    Text("of \(session.config.studyMinutes) min").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.clock(session.remainingSeconds))
                    .font(.system(size: 84, weight: .bold).monospacedDigit())
                    .tracking(-3)
                    .contentTransition(.numericText(countsDown: true))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(session.away ? "paused" : "left to study")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondary)
            }
            .accessibilityElement(children: .combine)
            ProgressView(value: progress).tint(Palette.blue)
            HStack(spacing: 10) {
                StatTile(label: "On your phone", value: Format.clock(session.phoneSeconds), valueColor: Palette.red)
                StatTile(label: "Pickups", value: "\(session.pickups)")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }

    private var statusColor: Color {
        model.isPaused ? Palette.secondary : session.away ? Palette.away : session.onPhone ? Palette.red : Palette.blue
    }

    private var status: some View {
        let (text, color): (String, Color) = model.isPaused
            ? ("Paused (dev)", Palette.secondary)
            : session.away
            ? ("Away · phone's free", Palette.away)
            : session.onPhone ? ("On your phone", Palette.red) : ("Studying · phone down", Palette.blue)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var progress: Double {
        guard session.targetSeconds > 0 else { return 0 }
        return min(1, session.studiedSeconds / session.targetSeconds)
    }
}

private struct AwayCard: View {
    @Environment(AppModel.self) private var model
    let session: Session
    let paused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(paused ? "PAUSED FOR TESTING" : "YOU LEFT YOUR SPOT")
                    .font(.footnote.weight(.bold)).tracking(0.4).foregroundStyle(paused ? Palette.secondary : Palette.away)
                Text("Your phone is free.").font(.system(size: 28, weight: .bold)).tracking(-0.6)
                Text("The timer is paused at \(Format.clock(session.remainingSeconds)). Walk back to keep going, or stop here.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
            }
            Button(action: model.stop) {
                Label("End Session", systemImage: "stop.fill")
            }
            .buttonStyle(ProminentButtonStyle(color: Palette.ink))
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .glassPanel(cornerRadius: 38)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The bottom of the session screen: inside or outside the zone, roughly how far to its edge, and Stop.
private struct ZoneCard: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        let out = session.away
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: out ? "iphone" : "iphone.slash")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(out ? Palette.away : Palette.red, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kicker(out: out))
                        .font(.caption.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(out ? Palette.away : Palette.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(out ? "Your phone is free." : (session.isDroppedAnchor ? "Phone down." : "No-phone zone."))
                        .font(.title3.weight(.bold))
                    Text(hint(out: out))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if out {
                Button(action: model.stop) {
                    Label("End Session", systemImage: "stop.fill")
                }
                .buttonStyle(ProminentButtonStyle(color: Palette.ink))
            } else {
                Label(session.isDroppedAnchor ? "Walk out of your circle to unlock Stop" : "Leave the zone to unlock Stop",
                      systemImage: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(.white.opacity(0.7), in: Capsule())
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
        .glassPanel(cornerRadius: 34)
        .animation(.smooth(duration: 0.3), value: out)
        .sensoryFeedback(.success, trigger: out)
    }

    private func kicker(out: Bool) -> String {
        if !out, let other = model.lockedByOtherArea { return "IN \(other.name.uppercased())" }
        if session.isDroppedAnchor { return out ? "AWAY FROM YOUR SPOT" : "AT YOUR SPOT" }
        return out ? "OUTSIDE THE ZONE" : session.placeName.uppercased()
    }

    private func hint(out: Bool) -> String {
        if out { return "The timer is paused. Walk back in to keep going." }
        if let other = model.lockedByOtherArea { return "\(other.name) is one of your areas. Leave it to unlock Stop." }
        if session.isDroppedAnchor {
            guard let readout = model.anchorReadout else { return "Waiting for GPS…" }
            if readout.meters >= readout.unlocksAt { return "You look out. Checking for a few seconds…" }
            let fuzz = model.you.map { " (±\(Int($0.radius.rounded())) m)" } ?? ""
            return "You're \(Int(readout.meters.rounded())) m from your anchor\(fuzz). Stop unlocks at \(Int(readout.unlocksAt.rounded())) m."
        }
        let zone = session.area
        if let area = zone.area(session.config.areaID) {
            return "Walk out of \(area.name) to unlock Stop. The lobby and café are free."
        }
        guard let meters = model.metersToEdge(of: zone) else { return "Leave \(zone.name) to unlock Stop." }
        return "About \(Int(meters.rounded(.up))) m to the nearest way out of \(zone.name)."
    }
}
