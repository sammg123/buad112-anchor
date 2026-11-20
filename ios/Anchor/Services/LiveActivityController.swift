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

    /// Steps this far from the anchor (still inside the circle) show the walk-out state.
    nonisolated static let walkingOutAfterMeters = 3.0
    /// While walking out the card refreshes every this many meters; iOS limits how often it may update.
    nonisolated static let walkingUpdateMeters = 5.0

    /// `graceEndsAt` is set while you are unlocked and out of Anchor but the grace period has not run out.
    nonisolated static func state(for session: Session, at now: Date, graceEndsAt: Date?,
                                  walkedMeters: Double) -> AnchorActivityAttributes.ContentState {
        let mode: AnchorActivityAttributes.ContentState.Mode =
            session.away ? .away
            : session.isOnPhoneCounting ? .onPhone
            : graceEndsAt != nil ? .grace
            : walkedMeters >= walkingOutAfterMeters ? .walkingOut
            : .studying
        let studyRuns = mode == .studying || mode == .grace || mode == .walkingOut
        return AnchorActivityAttributes.ContentState(
            mode: mode,
            studyRemaining: session.remainingSeconds,
            studyEndsAt: studyRuns ? now.addingTimeInterval(session.remainingSeconds) : nil,
            phoneSeconds: session.phoneSeconds,
            phoneZeroAt: mode == .onPhone ? now.addingTimeInterval(-session.phoneSeconds) : nil,
            totalSeconds: session.targetSeconds,
            graceEndsAt: mode == .grace ? graceEndsAt : nil,
            walkedMeters: mode == .walkingOut ? walkedMeters : nil,
            radiusMeters: session.config.radiusMeters
        )
    }

    /// A new card on a mode change, or every few meters while walking out; never on every step.
    nonisolated static func needsUpdate(from old: AnchorActivityAttributes.ContentState?,
                                        to new: AnchorActivityAttributes.ContentState) -> Bool {
        guard let old else { return true }
        if old.mode != new.mode { return true }
        guard new.mode == .walkingOut else { return false }
        let bucket = { (m: Double?) in Int(((m ?? 0) / walkingUpdateMeters).rounded(.down)) }
        return bucket(old.walkedMeters) != bucket(new.walkedMeters)
    }

    /// Past the study end the card is out of date unless Anchor updated it.
    nonisolated private static func staleDate(_ state: AnchorActivityAttributes.ContentState) -> Date? {
        state.studyEndsAt?.addingTimeInterval(60)
    }

    /// Starting needs Anchor on screen; iOS refuses from the background.
    func start(for session: Session, at now: Date) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.state(for: session, at: now, graceEndsAt: nil, walkedMeters: 0)
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

    func update(for session: Session, at now: Date, graceEndsAt: Date?, walkedMeters: Double) {
        guard let activity else { return }
        let state = Self.state(for: session, at: now, graceEndsAt: graceEndsAt, walkedMeters: walkedMeters)
        guard Self.needsUpdate(from: lastState, to: state) else { return }
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
