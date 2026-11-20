import Foundation

/// Whether the phone is unlocked, from iOS's signals. iOS has no public "unlocked" notice: its protected-data notices
/// only fire once the phone has been locked about 10 s, so a quick lock-and-unlock used to go unseen (and a lock
/// restarted the wait, so locking and unlocking over and over never counted). SpringBoard's lock-state notice fires
/// on every lock and unlock; a lock-state notice with the screen on and no lock just before it is an unlock.
struct LockTracker: Equatable {
    /// With no lock-state notice, after a lock iOS can still say "data available" for a while even on the Lock
    /// Screen; only believe it once this long has passed.
    static let relockQuietSeconds = 15.0
    /// A lock-state notice this soon after a lock-complete notice is that lock, not an unlock.
    static let lockCompleteWindow = 1.5

    private(set) var isUnlocked: Bool
    private(set) var isScreenBlank = false
    private var lastLock = Date.distantPast
    private var lastLockComplete = Date.distantPast

    init(isUnlocked: Bool) {
        self.isUnlocked = isUnlocked
    }

    /// The screen went dark (a lock, as far as Anchor is concerned) or lit up (not proof of an unlock: the Lock
    /// Screen lights up too).
    func screen(blank: Bool, at time: Date) -> LockTracker {
        var next = self
        next.isScreenBlank = blank
        if blank { next = next.locked(at: time) }
        return next
    }

    /// SpringBoard says the lock finished.
    func lockCompleted(at time: Date) -> LockTracker {
        var next = locked(at: time)
        next.lastLockComplete = time
        return next
    }

    /// SpringBoard's lock state changed. `reportsLocked`: what its state said, if anything. `screenBlank`: the screen
    /// right now.
    func lockStateChanged(at time: Date, reportsLocked: Bool?, screenBlank: Bool) -> LockTracker {
        let isLock = reportsLocked == true || screenBlank
            || time.timeIntervalSince(lastLockComplete) < Self.lockCompleteWindow
        if isLock { return locked(at: time) }
        var next = self
        next.isScreenBlank = false
        next.isUnlocked = true
        return next
    }

    /// Anchor itself is on screen: the phone is unlocked.
    func opened() -> LockTracker {
        var next = self
        next.isScreenBlank = false
        next.isUnlocked = true
        return next
    }

    /// iOS's protected-data notices: unavailable is a lock; available again (with the screen on) is an unlock.
    func protectedData(available: Bool, at time: Date) -> LockTracker {
        if !available { return locked(at: time) }
        guard !isScreenBlank else { return self }
        var next = self
        next.isUnlocked = true
        return next
    }

    /// Every second: data unavailable means locked; data available, screen on and quiet long enough since the last
    /// lock means unlocked (the fallback for when no lock-state notice came).
    func tick(dataAvailable: Bool, at time: Date) -> LockTracker {
        if isUnlocked, !dataAvailable { return locked(at: time) }
        guard !isUnlocked, dataAvailable, !isScreenBlank,
              time.timeIntervalSince(lastLock) > Self.relockQuietSeconds else { return self }
        var next = self
        next.isUnlocked = true
        return next
    }

    private func locked(at time: Date) -> LockTracker {
        var next = self
        next.isUnlocked = false
        next.lastLock = time
        return next
    }
}
