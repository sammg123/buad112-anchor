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
    func scheduleLadder(phoneSeconds: Double, stintSeconds: Double, silent: Bool) {
        cancelLadder(clearDelivered: false)
        let buzzes = Ladder.buzzes(phoneSeconds: phoneSeconds, stintSeconds: stintSeconds, limit: Ladder.maxPending)
        scheduledThroughSeconds = phoneSeconds + (buzzes.last?.delay ?? 0)
        for buzz in buzzes {
            let content = UNMutableNotificationContent()
            content.title = buzz.title
            content.body = buzz.body
            content.sound = Self.sound(silent: silent)
            content.threadIdentifier = Self.thread
            // Time Sensitive breaks through a Focus, which is exactly when a student would study.
            content.interruptionLevel = .timeSensitive
            content.badge = NSNumber(value: Int((phoneSeconds + buzz.delay) / 60))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, buzz.delay), repeats: false)
            add(UNNotificationRequest(identifier: "buzz-\(buzz.index)", content: content, trigger: trigger))
        }
    }

    /// A notification only vibrates when it has a sound, so library mode plays a silent one: vibration, no noise.
    private static func sound(silent: Bool) -> UNNotificationSound {
        silent ? UNNotificationSound(named: UNNotificationSoundName("silence.wav")) : .default
    }

    /// The buzz the moment the grace period runs out.
    func pickupBuzz(phoneSeconds: Double, silent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = phoneSeconds < 1 ? "You're on your phone" : "Back on your phone · \(Format.clock(phoneSeconds))"
        content.body = "Grace is over. The study timer stopped. Lock it and this all stops."
        content.sound = Self.sound(silent: silent)
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = Self.thread
        add(UNNotificationRequest(identifier: "anchor-pickup", content: content, trigger: nil))
    }

    nonisolated static let zoneCategory = "anchor-zone-arrival"
    nonisolated static let startAction = "anchor-start"

    /// The Start button on the arrival notice opens Anchor and starts the session.
    static func registerCategories() {
        let start = UNNotificationAction(identifier: startAction, title: "Start", options: [.foreground])
        let category = UNNotificationCategory(identifier: zoneCategory, actions: [start], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// "You're in Leavey Library: Study Room 2. Anchor is on." (Auto-start), or the same with a Start button.
    func zoneArrival(_ zone: Zone, area: StudyArea?, started: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "You're in " + [zone.name, area?.name].compactMap { $0 }.joined(separator: ": ")
        content.body = started
            ? "Anchor is on. Stop stays locked until you leave."
            : "It's a no-phone zone. Tap Start to turn Anchor on."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = started ? "" : Self.zoneCategory
        content.userInfo = ["zone": zone.id]
        add(UNNotificationRequest(identifier: "anchor-arrival-\(zone.id)", content: content, trigger: nil))
    }

    func testBuzz(silent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Test buzz"
        content.body = silent ? "Library mode: you should feel this, not hear it." : "You should hear and feel this."
        content.sound = Self.sound(silent: silent)
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        add(UNNotificationRequest(identifier: "anchor-test", content: content, trigger: trigger))
    }

    func cancelLadder(clearDelivered: Bool = true) {
        center.removePendingNotificationRequests(withIdentifiers: Self.allLadderIDs)
        if clearDelivered { center.removeDeliveredNotifications(withIdentifiers: Self.allLadderIDs) }
        scheduledThroughSeconds = 0
    }

    func clearBadge() {
        center.setBadgeCount(0) { @Sendable error in
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
        center.add(request) { @Sendable error in
            if let error {
                log.error("could not schedule \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension Notification.Name {
    /// Posted with `userInfo["zone"]` when the arrival notice's Start (or the notice itself) is tapped.
    static let anchorStartZone = Notification.Name("anchorStartZone")
}

/// Shows Anchor's own notices as banners while Anchor is open (iOS hides them by default), and turns a tap on the
/// arrival notice into starting that zone's session.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == Buzzer.zoneCategory,
              response.actionIdentifier == Buzzer.startAction || response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let zone = content.userInfo["zone"] as? String else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .anchorStartZone, object: nil, userInfo: ["zone": zone])
        }
    }
}
