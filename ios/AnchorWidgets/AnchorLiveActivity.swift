import ActivityKit
import SwiftUI
import WidgetKit

private typealias State = AnchorActivityAttributes.ContentState

struct AnchorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnchorActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Badge(mode: state.mode, size: 40).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(caption(state.mode)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        MainClock(state: state)
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomLine(state: state)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            } compactLeading: {
                Badge(mode: state.mode, size: 22)
            } compactTrailing: {
                MainClock(state: state)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Badge(mode: state.mode, size: 22)
            }
            .keylineTint(modeColor(state.mode))
        }
    }
}

private func modeColor(_ mode: State.Mode) -> Color {
    switch mode {
    case .studying: AnchorPalette.blue
    case .grace: AnchorPalette.grace
    case .onPhone: AnchorPalette.red
    case .away: AnchorPalette.away
    }
}

private func caption(_ mode: State.Mode) -> String {
    switch mode {
    case .studying: "Anchored · phone down"
    case .grace: "Grace period · not counting yet"
    case .onPhone: "On your phone at your spot"
    case .away: "Away · phone's free"
    }
}

/// A live countdown to `end`, or the frozen value once it has passed.
private struct Countdown: View {
    let end: Date?
    let fallback: Double

    var body: some View {
        if let end, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else {
            Text(Format.clock(fallback))
        }
    }
}

/// The big number: the grace countdown, the phone clock counting up, or study time left.
private struct MainClock: View {
    let state: State

    var body: some View {
        switch state.mode {
        case .grace:
            Countdown(end: state.graceEndsAt, fallback: 0).foregroundStyle(Color(white: 0.85))
        case .onPhone:
            if let zero = state.phoneZeroAt {
                Text(timerInterval: zero...Date.distantFuture, countsDown: false)
                    .foregroundStyle(AnchorPalette.brightRed)
            } else {
                Text(Format.clock(state.phoneSeconds)).foregroundStyle(AnchorPalette.brightRed)
            }
        case .studying:
            Countdown(end: state.studyEndsAt, fallback: state.studyRemaining)
        case .away:
            Text(Format.clock(state.studyRemaining))
        }
    }
}

/// The full-width line under the expanded Dynamic Island.
private struct BottomLine: View {
    let state: State

    var body: some View {
        switch state.mode {
        case .grace:
            HStack(spacing: 4) {
                Text("Study still running ·")
                Countdown(end: state.studyEndsAt, fallback: state.studyRemaining)
                Text("· phone \(Format.clock(state.phoneSeconds))")
            }
        case .onPhone:
            Text("Study paused at \(Format.clock(state.studyRemaining)) · lock it to stop the buzzing")
        case .studying:
            Text("Phone \(Format.clock(state.phoneSeconds)) so far")
        case .away:
            Text("Timer paused at \(Format.clock(state.studyRemaining))")
        }
    }
}

/// The small number on the Lock Screen's right side.
private struct SideClock: View {
    let state: State

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(state.mode == .onPhone || state.mode == .grace ? "Study" : "Phone")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1)
            Group {
                switch state.mode {
                case .grace: Countdown(end: state.studyEndsAt, fallback: state.studyRemaining)
                case .onPhone: Text(Format.clock(state.studyRemaining))
                default: Text(Format.clock(state.phoneSeconds)).foregroundStyle(AnchorPalette.brightRed)
                }
            }
            .font(.system(size: 17, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .frame(maxWidth: 70, alignment: .trailing)
        }
    }
}

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

private struct LockScreenView: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Badge(mode: state.mode, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption(state.mode)).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MainClock(state: state)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .frame(maxWidth: 150, alignment: .leading)
                        if state.mode == .studying || state.mode == .away {
                            Text("left").font(.headline).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                Spacer(minLength: 0)
                SideClock(state: state)
            }
            progressBar.tint(state.mode == .onPhone ? AnchorPalette.brightRed : Color(red: 0.3, green: 0.61, blue: 1))
        }
        .foregroundStyle(.white)
        .padding(18)
    }

    /// While the study clock runs the bar fills by itself; otherwise it holds where the study timer stopped.
    @ViewBuilder
    private var progressBar: some View {
        if let end = state.studyEndsAt, end > .now {
            let start = end.addingTimeInterval(-state.totalSeconds)
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
        } else {
            ProgressView(value: progress)
        }
    }

    private var progress: Double {
        guard state.totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - state.studyRemaining / state.totalSeconds))
    }
}
