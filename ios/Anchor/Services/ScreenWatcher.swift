import Foundation
import notify

/// Tells Anchor the moment the screen turns off, so a quick glance followed by a lock never counts. iOS's own
/// "locked" notice arrives about 10 s late. This listens to SpringBoard's screen-blanked notice, which any app may
/// observe; it is not an App Store API, which is fine for TestFlight.
@MainActor
final class ScreenWatcher {
    private static let name = "com.apple.springboard.hasBlankedScreen"
    private var token: Int32 = NOTIFY_TOKEN_INVALID
    var onChange: ((_ isBlank: Bool) -> Void)?

    func start() {
        guard token == NOTIFY_TOKEN_INVALID else { return }
        let status = notify_register_dispatch(Self.name, &token, .main) { @Sendable [weak self] token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            let blank = state != 0
            MainActor.assumeIsolated { self?.onChange?(blank) }
        }
        if status != NOTIFY_STATUS_OK { token = NOTIFY_TOKEN_INVALID }
    }

    func stop() {
        guard token != NOTIFY_TOKEN_INVALID else { return }
        notify_cancel(token)
        token = NOTIFY_TOKEN_INVALID
    }
}
