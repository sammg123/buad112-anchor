import Foundation
import os

/// Keeps the running session (and the last one, for its grade) across app restarts.
struct SessionStore {
    private static let log = Logger(subsystem: "com.sammg123.anchor", category: "store")
    private static let runningKey = "anchor.session.v2"
    private static let finishedKey = "anchor.finished.v2"
    private static let configKey = "anchor.config.v2"
    private static let onboardedKey = "anchor.onboarded.v1"
    private static let arrivalsKey = "anchor.arrivals.v1"
    private static let autoStartKey = "anchor.autostart.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Self.onboardedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.onboardedKey) }
    }

    /// Auto-start: begin a session by itself on walking into a no-phone zone.
    var autoStart: Bool {
        get { defaults.bool(forKey: Self.autoStartKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.autoStartKey) }
    }

    /// When each zone's arrival notice last went out (seconds since 1970), so the cooldown survives relaunches.
    func lastArrival(atZone id: String) -> Date? {
        (defaults.dictionary(forKey: Self.arrivalsKey)?[id] as? Double).map { Date(timeIntervalSince1970: $0) }
    }

    func saveArrival(atZone id: String, at date: Date) {
        var all = defaults.dictionary(forKey: Self.arrivalsKey) ?? [:]
        all[id] = date.timeIntervalSince1970
        defaults.set(all, forKey: Self.arrivalsKey)
    }

    func loadRunning() -> Session? { load(Session.self, key: Self.runningKey) }
    func loadFinished() -> Session? { load(Session.self, key: Self.finishedKey) }
    func loadConfig() -> SessionConfig? { load(SessionConfig.self, key: Self.configKey) }

    func saveRunning(_ session: Session?) { save(session, key: Self.runningKey) }
    func saveFinished(_ session: Session?) { save(session, key: Self.finishedKey) }
    func saveConfig(_ config: SessionConfig) { save(config, key: Self.configKey) }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Self.log.error("dropping unreadable \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Self.log.error("could not save \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
