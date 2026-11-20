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
    /// Updates run one after another, so a quick pair of changes can never land in the wrong order.
    private var lastUpdate: Task<Void, Never>?

    /// `graceEndsAt` is set while you are unlocked and out of Anchor but the grace period has not run out.
    nonisolated static func state(for session: Session, at now: Date,
                                  graceEndsAt: Date?) -> AnchorActivityAttributes.ContentState {
        let mode: AnchorActivityAttributes.ContentState.Mode =
            session.away ? .away
            : session.isOnPhoneCounting ? .onPhone
            : graceEndsAt != nil ? .grace
            : .studying
        let studyRuns = mode == .studying || mode == .grace
        return AnchorActivityAttributes.ContentState(
            mode: mode,
            studyRemaining: session.remainingSeconds,
            studyEndsAt: studyRuns ? now.addingTimeInterval(session.remainingSeconds) : nil,
            phoneSeconds: session.phoneSeconds,
            phoneZeroAt: mode == .onPhone ? now.addingTimeInterval(-session.phoneSeconds) : nil,
            totalSeconds: session.targetSeconds,
            graceEndsAt: mode == .grace ? graceEndsAt : nil
        )
    }

    /// A new card only when the mode changes; the card's own timers do the counting.
    nonisolated static func needsUpdate(from old: AnchorActivityAttributes.ContentState?,
                                        to new: AnchorActivityAttributes.ContentState) -> Bool {
        old?.mode != new.mode
    }

    /// Past the study end the card is out of date unless Anchor updated it.
    nonisolated private static func staleDate(_ state: AnchorActivityAttributes.ContentState) -> Date? {
        state.studyEndsAt?.addingTimeInterval(60)
    }

    /// Starting needs Anchor on screen; iOS refuses from the background.
    func start(for session: Session, at now: Date) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.state(for: session, at: now, graceEndsAt: nil)
        do {
            activity = try Activity.request(
                attributes: AnchorActivityAttributes(minutes: session.config.studyMinutes, place: session.placeName),
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

    func update(for session: Session, at now: Date, graceEndsAt: Date?) {
        guard let activity else { return }
        let state = Self.state(for: session, at: now, graceEndsAt: graceEndsAt)
        guard Self.needsUpdate(from: lastState, to: state) else { return }
        lastState = state
        let id = activity.id
        // Activity is not Sendable: look it up again inside the task instead of sending it.
        let previous = lastUpdate
        lastUpdate = Task.detached {
            await previous?.value
            for item in Activity<AnchorActivityAttributes>.activities where item.id == id {
                await item.update(ActivityContent(state: state, staleDate: Self.staleDate(state)))
            }
        }
    }

    func end() {
        activity = nil
        lastState = nil
        let previous = lastUpdate
        lastUpdate = nil
        Task.detached {
            await previous?.value
            for item in Activity<AnchorActivityAttributes>.activities {
                await item.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
