import ActivityKit
import Foundation
import os

/// Keeps the Lock Screen / Dynamic Island card in step with the session. Its timers count by themselves, so it
/// is only updated when the mode changes.
@MainActor
final class LiveActivityController {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "live-activity")

    private var activity: Activity<AnchorActivityAttributes>?
    private var lastState: AnchorActivityAttributes.ContentState?

    static func state(for session: Session, at now: Date) -> AnchorActivityAttributes.ContentState {
        let mode: AnchorActivityAttributes.ContentState.Mode =
            session.away ? .away : session.isOnPhoneCounting ? .onPhone : .studying
        return AnchorActivityAttributes.ContentState(
            mode: mode,
            studyRemaining: session.remainingSeconds,
            studyEndsAt: mode == .studying ? now.addingTimeInterval(session.remainingSeconds) : nil,
            phoneSeconds: session.phoneSeconds,
            phoneZeroAt: mode == .onPhone ? now.addingTimeInterval(-session.phoneSeconds) : nil,
            totalSeconds: session.targetSeconds
        )
    }

    /// Past the study end the card is out of date unless Anchor updated it.
    nonisolated private static func staleDate(_ state: AnchorActivityAttributes.ContentState) -> Date? {
        state.studyEndsAt?.addingTimeInterval(60)
    }

    /// Starting needs Anchor on screen; iOS refuses from the background.
    func start(for session: Session, at now: Date) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.state(for: session, at: now)
        do {
            activity = try Activity.request(
                attributes: AnchorActivityAttributes(minutes: session.config.studyMinutes),
                content: ActivityContent(state: state, staleDate: Self.staleDate(state))
            )
            lastState = state
        } catch {
            Self.log.error("live activity failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adopts a card left over from before a relaunch, so it keeps updating.
    func adoptExisting() {
        activity = Activity<AnchorActivityAttributes>.activities.first
    }

    func update(for session: Session, at now: Date) {
        guard let activity else { return }
        let state = Self.state(for: session, at: now)
        guard state.mode != lastState?.mode else { return }
        lastState = state
        let id = activity.id
        // Activity is not Sendable: look it up again inside the task instead of sending it.
        Task.detached {
            for item in Activity<AnchorActivityAttributes>.activities where item.id == id {
                await item.update(ActivityContent(state: state, staleDate: Self.staleDate(state)))
            }
        }
    }

    func end() {
        activity = nil
        lastState = nil
        Task.detached {
            for item in Activity<AnchorActivityAttributes>.activities {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
