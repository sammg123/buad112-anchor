import Foundation
import os
@preconcurrency import UserNotifications

/// Every buzz is a local notification: iOS vibrates the phone (and plays the sound unless it is on silent)
/// even while another app is open, which an app in the background cannot do any other way.
@MainActor
final class Buzzer {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "buzzer")
    private static let doneID = "anchor-done"
    private static let thread = "anchor-buzz"

    private let center = UNUserNotificationCenter.current()
    /// Every id a ladder can use, so a ladder from an earlier launch can always be cleared.
    private static let allLadderIDs = (0..<4_000).map { "buzz-\($0)" }
    /// The phone-clock time of the last buzz scheduled, so the model can top the ladder up before it runs out.
    private(set) var scheduledThroughSeconds = 0.0

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Replace any pending ladder with one that starts at the next buzz after `phoneSeconds`.
    func scheduleLadder(phoneSeconds: Double, stintSeconds: Double) {
        cancelLadder(clearDelivered: false)
        let buzzes = Ladder.buzzes(phoneSeconds: phoneSeconds, stintSeconds: stintSeconds, limit: Ladder.maxPending)
        scheduledThroughSeconds = phoneSeconds + (buzzes.last?.delay ?? 0)
        for buzz in buzzes {
            let content = UNMutableNotificationContent()
            content.title = buzz.title
            content.body = buzz.body
            content.sound = .default
            content.threadIdentifier = Self.thread
            // Time Sensitive breaks through a Focus, which is exactly when a student would study.
            content.interruptionLevel = .timeSensitive
            content.badge = NSNumber(value: Int((phoneSeconds + buzz.delay) / 60))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, buzz.delay), repeats: false)
            add(UNNotificationRequest(identifier: "buzz-\(buzz.index)", content: content, trigger: trigger))
        }
    }

    func cancelLadder(clearDelivered: Bool = true) {
        center.removePendingNotificationRequests(withIdentifiers: Self.allLadderIDs)
        if clearDelivered { center.removeDeliveredNotifications(withIdentifiers: Self.allLadderIDs) }
        scheduledThroughSeconds = 0
    }

    func clearBadge() {
        center.setBadgeCount(0) { error in
            if let error { Self.log.error("badge reset failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// The "session done" notice at the projected finish, or none while the study clock is stopped.
    func scheduleDone(at date: Date?, now: Date, grayscale: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.doneID])
        guard let date else { return }
        let content = UNMutableNotificationContent()
        content.title = "Session done"
        content.body = grayscale ? "Nice. Open Anchor to get your color back." : "Nice. Open Anchor for your grade."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
        add(UNNotificationRequest(identifier: Self.doneID, content: content, trigger: trigger))
    }

    func cancelDone() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.doneID])
    }

    /// A one-off notice shown right away.
    func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func add(_ request: UNNotificationRequest) {
        let id = request.identifier
        let log = Self.log
        center.add(request) { error in
            if let error {
                log.error("could not schedule \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Shows Anchor's own notices as banners while Anchor is open (iOS hides them by default).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
