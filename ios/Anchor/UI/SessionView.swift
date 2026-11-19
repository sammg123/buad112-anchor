import MapKit
import SwiftUI

/// A running session: the countdown on glass over the map, Stop locked until you leave the circle.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            if let session = model.live {
                map(session)
                VStack(spacing: 0) {
                    TimerCard(session: session)
                    Spacer()
                    if session.away {
                        AwayCard(session: session)
                    } else {
                        lockedFooter
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .animation(.smooth(duration: 0.35), value: session.away)
                .onAppear { frame(session) }
            }
        }
    }

    private func map(_ session: Session) -> some View {
        let away = session.away
        return Map(position: $camera) {
            MapCircle(center: session.anchor.coordinate, radius: session.config.radiusMeters)
                .foregroundStyle((away ? Color.gray : Palette.blue).opacity(0.14))
                .stroke((away ? Color.gray : Palette.blue).opacity(0.6), lineWidth: 2)
            Annotation("Your anchor", coordinate: session.anchor.coordinate, anchor: .center) {
                AnchorPin(size: 30, color: away ? Color(white: 0.55) : Palette.blue)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    private var lockedFooter: some View {
        VStack(spacing: 10) {
            if let meters = model.distanceToAnchor {
                Text("\(Format.meters(meters)) from your anchor")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassCapsule()
            }
            Label(lockedText, systemImage: "lock.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 58)
                .glassPanel(cornerRadius: 29)
                .accessibilityLabel("Stop is locked. \(lockedText)")
        }
    }

    private var lockedText: String {
        guard let meters = model.distanceToAnchor else { return "Stop unlocks when you leave the circle" }
        let left = max(1, model.unlockDistance - meters)
        return "Walk \(Format.meters(left)) to unlock Stop"
    }

    private func frame(_ session: Session) {
        let span = max(session.config.radiusMeters, 25) * 6
        camera = .region(MKCoordinateRegion(center: session.anchor.coordinate,
                                            latitudinalMeters: span * 1.6, longitudinalMeters: span))
    }
}

private struct TimerCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                status
                Spacer()
                Text("of \(session.config.studyMinutes) min").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondary)
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
        .padding(22)
        .glassPanel(cornerRadius: 36)
    }

    private var status: some View {
        let (text, color): (String, Color) = session.away
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOU LEFT YOUR SPOT").font(.footnote.weight(.bold)).tracking(0.4).foregroundStyle(Palette.away)
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
