import SwiftUI

/// The end of a session: what you studied and what the phone took.
struct DoneView: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 18) {
                    ring
                    VStack(spacing: 6) {
                        Text(session.isComplete ? "Session done" : "Session ended")
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-0.6)
                            .accessibilityAddTraits(.isHeader)
                        Text(pickupLine).font(.callout).foregroundStyle(Palette.secondary)
                    }
                }
                VStack(spacing: 0) {
                    row("On your phone", Format.clock(session.phoneSeconds), red: true)
                    Divider()
                    row("Longest scroll", Format.clock(session.longestStintSeconds), red: false)
                    Divider()
                    row("Buzzes you sat through", "\(Ladder.buzzCount(phoneSeconds: session.phoneSeconds))", red: false)
                    Divider()
                    row("Time away (paused)", Format.clock(session.awaySeconds), red: false)
                    if session.spoofedReadings > 0 {
                        Divider()
                        row("Faked locations caught", "\(session.spoofedReadings)", red: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 20)
            .padding(.top, 48)
        }
        .safeAreaInset(edge: .bottom) {
            Button("New Session", action: model.startOver)
                .buttonStyle(ProminentButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .background(Palette.ground.ignoresSafeArea())
    }

    private var pickupLine: String {
        switch session.pickups {
        case 0: "You never touched your phone."
        case 1: "You picked up your phone once."
        default: "You picked up your phone \(session.pickups) times."
        }
    }

    private var ring: some View {
        let total = max(1, session.studiedSeconds + session.phoneSeconds)
        let studied = session.studiedSeconds / total
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 14)
            Circle()
                .trim(from: 0, to: studied)
                .stroke(Palette.blue, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: studied, to: 1)
                .stroke(Palette.red, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(session.phoneSeconds > 0 ? 1 : 0)
            VStack(spacing: 2) {
                Text(Format.clock(session.studiedSeconds)).font(.system(size: 44, weight: .bold).monospacedDigit())
                Text("studied").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: 196, height: 196)
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String, red: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(Color(white: 0.23))
            Spacer()
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(red ? Palette.red : Palette.ink)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
