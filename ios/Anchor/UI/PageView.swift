import SwiftUI

/// The open ruled page while a session runs.
struct PageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            RuledPaper()
            if let session = model.live {
                content(session)
            }
        }
    }

    private func content(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing * 2) {
            Text(session.config.courseName)
                .font(Theme.hand(28, relativeTo: .title))
                .foregroundStyle(Theme.ink)
            status(session)
            VStack(alignment: .leading, spacing: 0) {
                Text("STUDY TIME LEFT").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.pencil)
                Text(Format.clock(session.remainingSeconds))
                    .font(Theme.timer(96))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Study time left \(Format.clock(session.remainingSeconds))")
            }
            phoneLine(session)
            Spacer(minLength: 0)
            distance(session)
            stopButton(session)
        }
        .padding(.leading, 48)
        .padding(.trailing, 24)
        .padding(.vertical, 24)
    }

    private func status(_ session: Session) -> some View {
        let (text, color): (String, Color) = session.away
            ? ("Away from your spot. Phone's free, timer paused.", Theme.pencil)
            : session.onPhone
                ? ("On your phone. Buzzing every 15 s.", Theme.pen)
                : ("Studying. Phone down.", Theme.ink)
        return Text(text).font(.headline).foregroundStyle(color)
    }

    private func phoneLine(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PHONE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.pencil)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(Format.clock(session.phoneSeconds))
                    .font(Theme.hand(44, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.pen)
                    .padding(.horizontal, 10)
                    .overlay(Ellipse().stroke(Theme.pen, lineWidth: 2).opacity(session.phoneSeconds > 0 ? 1 : 0))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Format.money(session.costDollars)) of tuition").font(Theme.hand(20)).foregroundStyle(Theme.pen)
                    Text("\(session.pickups) pickup\(session.pickups == 1 ? "" : "s")").font(.footnote).foregroundStyle(Theme.pencil)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func distance(_ session: Session) -> some View {
        if let meters = model.distanceToAnchor {
            Text("\(Format.meters(meters)) from your spot · Stop unlocks past \(Format.meters(model.unlockDistance))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.pencil)
        } else {
            Text("Waiting for GPS…").font(.footnote.weight(.semibold)).foregroundStyle(Theme.pencil)
        }
    }

    private func stopButton(_ session: Session) -> some View {
        Button(action: model.stop) {
            if model.isStopUnlocked {
                Label("Stop session", systemImage: "stop.fill")
            } else {
                Label(lockedText, systemImage: "lock.fill")
            }
        }
        .buttonStyle(InkButtonStyle(outline: !model.isStopUnlocked))
        .disabled(!model.isStopUnlocked)
        .accessibilityHint(model.isStopUnlocked ? "Ends the session" : "Walk away from your spot to unlock")
    }

    private var lockedText: String {
        guard let meters = model.distanceToAnchor else { return "Stop is locked at your spot" }
        let left = max(1, model.unlockDistance - meters)
        return "Locked. Walk \(Format.meters(left)) more to stop"
    }
}
