import Foundation
import notify

/// Tells Anchor the moment the screen turns off, the lock completes, or the lock state changes. iOS's own "locked"
/// notice arrives about 10 s late and it has no public "unlocked" notice at all, so these come from SpringBoard's
/// notices, which any app may observe; they are not App Store API, which is fine for TestFlight.
@MainActor
final class ScreenWatcher {
    private static let blankName = "com.apple.springboard.hasBlankedScreen"
    private static let lockCompleteName = "com.apple.springboard.lockcomplete"
    private static let lockStateName = "com.apple.springboard.lockstate"
    /// The lock's notices can arrive in any order; decide what a lock-state change was once they've all landed.
    private static let settleSeconds = 0.3

    private var tokens: [String: Int32] = [:]
    var onBlank: ((_ isBlank: Bool) -> Void)?
    var onLockComplete: (() -> Void)?
    /// `reportsLocked`: SpringBoard's own state, when it gives one. `screenBlank`: the screen at that moment.
    var onLockState: ((_ reportsLocked: Bool?, _ screenBlank: Bool) -> Void)?

    func start() {
        register(Self.blankName) { [weak self] state in self?.onBlank?(state != 0) }
        register(Self.lockCompleteName) { [weak self] _ in self?.onLockComplete?() }
        register(Self.lockStateName) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.settleSeconds))
                // Stopped meanwhile, or a state that can't be read: no news, never an unlock.
                guard let self, let state = self.state(of: Self.lockStateName) else { return }
                let screenBlank = self.state(of: Self.blankName).map { $0 != 0 } ?? true
                self.onLockState?(state == 1 ? true : nil, screenBlank)
            }
        }
    }

    func stop() {
        tokens.values.forEach { notify_cancel($0) }
        tokens = [:]
    }

    private func register(_ name: String, handler: @escaping @MainActor (UInt64) -> Void) {
        guard tokens[name] == nil else { return }
        var token: Int32 = NOTIFY_TOKEN_INVALID
        let status = notify_register_dispatch(name, &token, .main) { @Sendable token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            MainActor.assumeIsolated { handler(state) }
        }
        if status == NOTIFY_STATUS_OK { tokens[name] = token }
    }

    private func state(of name: String) -> UInt64? {
        guard let token = tokens[name] else { return nil }
        var state: UInt64 = 0
        return notify_get_state(token, &state) == NOTIFY_STATUS_OK ? state : nil
    }
}
