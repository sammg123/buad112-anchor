import ActivityKit
import SwiftUI
import WidgetKit

private typealias State = AnchorActivityAttributes.ContentState

/// One layout for every state (see the mocks): a one-line label, one big clock with its unit right after it as a
/// single piece of text (so the unit can never drift away from the number), and one small fixed-width stat.
struct AnchorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnchorActivityAttributes.self) { context in
            LockScreenView(state: context.state, place: context.attributes.place)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let place = context.attributes.place
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Badge(mode: state.mode, size: 40).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(caption(state, place: place)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        clockWithUnit(state, size: 30, unitSize: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomLine(state)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            } compactLeading: {
                Badge(mode: state.mode, size: 22)
            } compactTrailing: {
                bigClock(state)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            } minimal: {
                Badge(mode: state.mode, size: 22)
            }
            .keylineTint(modeColor(state.mode))
        }
    }
}

// MARK: - Words

private func modeColor(_ mode: State.Mode) -> Color {
    switch mode {
    case .studying: AnchorPalette.blue
    case .grace: AnchorPalette.grace
    case .onPhone: AnchorPalette.red
    case .away: AnchorPalette.away
    }
}

/// The top line: where you are while studying ("Leavey Library · Study Room 2"), otherwise what's happening.
private func caption(_ state: State, place: String?) -> String {
    switch state.mode {
    case .studying: place ?? "Studying · phone down"
    case .grace: "Grace period"
    case .onPhone: "On your phone"
    case .away: "Out of the zone · phone is free"
    }
}

private func unit(_ state: State) -> String {
    switch state.mode {
    case .studying: "left"
    case .grace: "until it counts"
    case .onPhone: "on phone"
    case .away: "paused"
    }
}

// MARK: - Clocks

/// A live countdown to `end`, or the frozen value once it has passed.
private func countdown(to end: Date?, fallback: Double) -> Text {
    if let end, end > .now {
        return Text(timerInterval: Date.now...end, countsDown: true)
    }
    return Text(Format.clock(fallback))
}

/// The big number of each state, colored.
private func bigClock(_ state: State) -> Text {
    switch state.mode {
    case .studying:
        return countdown(to: state.studyEndsAt, fallback: state.studyRemaining)
    case .grace:
        return countdown(to: state.graceEndsAt, fallback: 0).foregroundColor(Color(white: 0.85))
    case .onPhone:
        // A bounded range: an open-ended timer reserves room for a huge number and leaves a gap before the unit.
        let counting = state.phoneZeroAt.map {
            Text(timerInterval: $0...$0.addingTimeInterval(24 * 3600), countsDown: false)
        }
        return (counting ?? Text(Format.clock(state.phoneSeconds))).foregroundColor(AnchorPalette.brightRed)
    case .away:
        return Text(Format.clock(state.studyRemaining))
    }
}

/// Clock and unit as ONE Text, so the unit always sits right after the digits.
private func clockWithUnit(_ state: State, size: CGFloat, unitSize: CGFloat) -> some View {
    (bigClock(state).font(.system(size: size, weight: .bold).monospacedDigit())
        + Text(" " + unit(state)).font(.system(size: unitSize, weight: .semibold)).foregroundColor(.white.opacity(0.7)))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
}

private func bottomLine(_ state: State) -> Text {
    switch state.mode {
    case .studying:
        return Text("Phone \(Format.clock(state.phoneSeconds)) so far")
    case .grace:
        return Text("Study still running · ") + countdown(to: state.studyEndsAt, fallback: state.studyRemaining) + Text(" left")
    case .onPhone:
        return Text("Study paused at \(Format.clock(state.studyRemaining)) · lock it to stop")
    case .away:
        return Text("Timer paused at \(Format.clock(state.studyRemaining))")
    }
}

// MARK: - Pieces

private struct Badge: View {
    let mode: State.Mode
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(modeColor(mode))
            .frame(width: size, height: size)
            .overlay(AnchorMark(size: size * 0.55))
    }
}

/// The small stat on the Lock Screen's right: study time while it matters, otherwise phone time.
private struct SideStat: View {
    let state: State

    var body: some View {
        let showsStudy = state.mode == .grace || state.mode == .onPhone
        VStack(alignment: .trailing, spacing: 0) {
            Text(showsStudy ? "Study" : "Phone")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Group {
                switch state.mode {
                case .grace:
                    countdown(to: state.studyEndsAt, fallback: state.studyRemaining)
                case .onPhone:
                    Text(Format.clock(state.studyRemaining))
                case .studying, .away:
                    Text(Format.clock(state.phoneSeconds)).foregroundColor(AnchorPalette.brightRed)
                }
            }
            .font(.system(size: 17, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.trailing)
        }
        .frame(width: 72, alignment: .trailing)
    }
}

private struct LockScreenView: View {
    let state: State
    let place: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Badge(mode: state.mode, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption(state, place: place))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    clockWithUnit(state, size: 32, unitSize: 15)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SideStat(state: state)
            }
            progressBar
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    /// Study progress, filling by itself while it runs.
    @ViewBuilder
    private var progressBar: some View {
        if let end = state.studyEndsAt, end > .now {
            let start = end.addingTimeInterval(-state.totalSeconds)
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(Color(red: 0.3, green: 0.61, blue: 1))
        } else {
            ProgressView(value: studyProgress)
                .tint(state.mode == .onPhone ? AnchorPalette.brightRed : Color(red: 0.3, green: 0.61, blue: 1))
        }
    }

    private var studyProgress: Double {
        guard state.totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - state.studyRemaining / state.totalSeconds))
    }
}
