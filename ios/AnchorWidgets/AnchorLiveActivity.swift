import ActivityKit
import SwiftUI
import WidgetKit

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
                    Text(bottomLine(state))
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
            .keylineTint(state.mode == .onPhone ? AnchorPalette.red : AnchorPalette.blue)
        }
    }
}

private func caption(_ mode: AnchorActivityAttributes.ContentState.Mode) -> String {
    switch mode {
    case .studying: "Anchored · phone down"
    case .onPhone: "On your phone at your spot"
    case .away: "Away · phone's free"
    }
}

/// The full-width line under the expanded Dynamic Island.
private func bottomLine(_ state: AnchorActivityAttributes.ContentState) -> String {
    switch state.mode {
    case .onPhone: "Study paused at \(Format.clock(state.studyRemaining)) · lock it to stop the buzzing"
    case .studying: "Phone \(Format.clock(state.phoneSeconds)) so far"
    case .away: "Timer paused at \(Format.clock(state.studyRemaining))"
    }
}

/// The big number: phone time counting up while on the phone, otherwise study time left.
private struct MainClock: View {
    let state: AnchorActivityAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .onPhone:
            if let zero = state.phoneZeroAt {
                Text(timerInterval: zero...Date.distantFuture, countsDown: false)
                    .foregroundStyle(AnchorPalette.brightRed)
            } else {
                Text(Format.clock(state.phoneSeconds)).foregroundStyle(AnchorPalette.brightRed)
            }
        case .studying:
            if let end = state.studyEndsAt, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
            } else {
                Text(Format.clock(state.studyRemaining))
            }
        case .away:
            Text(Format.clock(state.studyRemaining))
        }
    }
}

/// The small number on the side: study left while on the phone, phone time otherwise.
private struct SideClock: View {
    let state: AnchorActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(state.mode == .onPhone ? "Study" : "Phone")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Format.clock(state.mode == .onPhone ? state.studyRemaining : state.phoneSeconds))
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(state.mode == .onPhone ? Color.white : AnchorPalette.brightRed)
        }
    }
}

private struct Badge: View {
    let mode: AnchorActivityAttributes.ContentState.Mode
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(mode == .onPhone ? AnchorPalette.red : mode == .away ? AnchorPalette.away : AnchorPalette.blue)
            .frame(width: size, height: size)
            .overlay(AnchorMark(size: size * 0.55))
    }
}

private struct LockScreenView: View {
    let state: AnchorActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Badge(mode: state.mode, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption(state.mode)).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MainClock(state: state)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .frame(maxWidth: 150, alignment: .leading)
                        if state.mode != .onPhone {
                            Text("left").font(.headline).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                Spacer(minLength: 0)
                SideClock(state: state)
            }
            progressBar
                .tint(state.mode == .onPhone ? AnchorPalette.brightRed : Color(red: 0.3, green: 0.61, blue: 1))
        }
        .foregroundStyle(.white)
        .padding(18)
    }

    /// While studying the bar fills by itself; otherwise it holds where the study timer stopped.
    @ViewBuilder
    private var progressBar: some View {
        if state.mode == .studying, let end = state.studyEndsAt, end > .now {
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
