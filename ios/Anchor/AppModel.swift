import CoreLocation
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Runs a session: turns location, the lock state and Anchor being on screen into the session's three clocks,
/// and turns the session into buzzes, the voice, the alarm and the Live Activity. Every rule lives in `Session`,
/// `Ladder` and `Escalation`; this only wires them up.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable { case permissions, start, session, done }

    /// A fix worse than this never decides whether you are away.
    static let maxDecidingAccuracy = 100.0
    /// Leaving Anchor only counts as picking up the phone after this long, so unlocking straight into Anchor
    /// (which wakes Anchor in the background for a moment) is not a pickup.
    private static let pickupDebounceSeconds = 2.0
    private static let saveEverySeconds = 10.0
    #if DEBUG
    /// Simulator screenshots: the Always prompt would cover the screen.
    private static let skipsAlwaysPrompt = ProcessInfo.processInfo.arguments.contains("-onboarded")
    #else
    private static let skipsAlwaysPrompt = false
    #endif
    /// Top the buzz ladder up when fewer than this many seconds of it are left.
    private static let ladderRefillSeconds = 60.0

    private(set) var session: Session?
    private(set) var finished: Session?
    private(set) var fix: CLLocation?
    private(set) var now = Date()
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var notificationsAllowed = false
    private(set) var hasPasscode = true
    private(set) var isFindingSpot = false
    private(set) var hasOnboarded: Bool
    var minutes: Int { didSet { savePreferences() } }
    var radiusMeters: Double { didSet { savePreferences() } }
    var grayscale: Bool { didSet { savePreferences() } }
    var notice: String?

    private let store = SessionStore()
    private let location = LocationService()
    private let buzzer = Buzzer()
    private let escalator = Escalator()
    private let liveActivity = LiveActivityController()
    /// Launched in the background (iOS relaunching a session), Anchor is not on screen until a scene says so.
    private var isAppActive = UIApplication.shared.applicationState != .background
    private var isDeviceUnlocked = true
    private var wantsPhoneSince: Date?
    private var shortcutGraceUntil = Date.distantPast
    private var pendingConfig: SessionConfig?
    /// The session ended in the background in black and white; color comes back when Anchor is opened.
    private var needsColorBack = false
    private var lastSaved = Date.distantPast
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let saved = store.loadConfig()
        minutes = saved?.studyMinutes ?? SetupInput.defaultMinutes
        radiusMeters = AnchorRules.clampedRadius(saved?.radiusMeters ?? AnchorRules.defaultRadiusMeters)
        grayscale = saved?.grayscale ?? false
        hasOnboarded = store.hasOnboarded
        finished = store.loadFinished()
        locationStatus = location.status
        location.onFix = { [weak self] fix in self?.received(fix) }
        location.onAuthorizationChange = { [weak self] status in self?.locationStatus = status }
        observeLockState()
        restore()
        location.startForeground()
        #if DEBUG
        // Simulator screenshots only.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-onboarded") { hasOnboarded = true }
        if args.contains("-autostart"), session == nil { dropAnchor() }
        #endif
    }

    // MARK: - What the screens read

    var screen: Screen {
        if session != nil { return .session }
        if finished != nil { return .done }
        if !hasOnboarded || !hasLocation { return .permissions }
        return .start
    }

    var hasLocation: Bool { locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse }
    var locationDenied: Bool { locationStatus == .denied || locationStatus == .restricted }

    var distanceToAnchor: Double? {
        guard let session, let fix else { return nil }
        return Geo.distanceMeters(session.anchor, fix.point)
    }

    var unlockDistance: Double {
        AnchorRules.unlockDistance(radius: session?.config.radiusMeters ?? radiusMeters,
                                   anchorAccuracy: session?.anchorAccuracy ?? 0,
                                   fixAccuracy: fix?.horizontalAccuracy ?? 0)
    }

    var isStopUnlocked: Bool { session?.away ?? false }

    /// The session as of this second, for display.
    var live: Session? { session?.advanced(to: now) }

    // MARK: - Permissions

    func requestLocation() {
        if locationStatus == .notDetermined { location.requestWhenInUse() }
    }

    func requestNotifications() async {
        notificationsAllowed = await buzzer.requestAuthorization()
    }

    func finishOnboarding() {
        hasOnboarded = true
        store.hasOnboarded = true
    }

    func refreshPermissions() async {
        locationStatus = location.status
        hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        notificationsAllowed = await buzzer.isAuthorized()
        if locationStatus == .authorizedWhenInUse, !Self.skipsAlwaysPrompt { location.requestAlways() }
    }

    // MARK: - Session lifecycle

    func dropAnchor() {
        guard hasLocation else {
            notice = "Anchor needs your location to know where you study. Allow it in Settings."
            return
        }
        let config = SessionConfig(studyMinutes: minutes, radiusMeters: AnchorRules.clampedRadius(radiusMeters),
                                   grayscale: grayscale)
        if let fix, isUsableAnchor(fix) {
            begin(config, at: fix)
        } else {
            pendingConfig = config
            isFindingSpot = true
            location.refresh()
        }
    }

    func cancelFindingSpot() {
        pendingConfig = nil
        isFindingSpot = false
    }

    /// Stop is only allowed away from the anchor (or once the timer is done, which ends the session itself).
    func stop() {
        guard let current = session?.advanced(to: Date()), current.away else { return }
        end(current)
    }

    func startOver() {
        finished = nil
        store.saveFinished(nil)
    }

    func runShortcut(_ shortcut: ColorShortcut) {
        guard let url = shortcut.url else { return }
        shortcutGraceUntil = Date().addingTimeInterval(ColorShortcut.graceSeconds)
        UIApplication.shared.open(url) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.notice = "Couldn't open Shortcuts. Is the Shortcuts app installed?"
            }
        }
    }

    // MARK: - Inputs

    func setAppActive(_ active: Bool) {
        isAppActive = active
        if active {
            Task { await refreshPermissions() }
            if needsColorBack {
                needsColorBack = false
                runShortcut(.color)
            }
        }
        reconcile()
    }

    private func received(_ newFix: CLLocation) {
        fix = newFix
        if let config = pendingConfig, isUsableAnchor(newFix) {
            begin(config, at: newFix)
            return
        }
        reconcile()
    }

    private func observeLockState() {
        // Opened by the student, the phone is unlocked. Relaunched in the background, ask iOS.
        isDeviceUnlocked = isAppActive || UIApplication.shared.isProtectedDataAvailable
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isDeviceUnlocked = true
                    self?.reconcile()
                }
            },
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.deviceLocked() }
            }
        ]
    }

    /// iOS says "locked" about 10 s after the fact; those seconds were not phone time.
    private func deviceLocked() {
        isDeviceUnlocked = false
        wantsPhoneSince = nil
        guard let current = session, current.onPhone else { return reconcile() }
        apply(current.lockedPhone(at: Date(), unseenSeconds: Ladder.lockLagSeconds))
    }

    // MARK: - The loop

    private func begin(_ config: SessionConfig, at anchorFix: CLLocation) {
        pendingConfig = nil
        isFindingSpot = false
        finished = nil
        store.saveFinished(nil)
        let started = Session.start(config: config, anchor: anchorFix.point,
                                    anchorAccuracy: anchorFix.horizontalAccuracy, at: Date())
        location.startSession()
        startTicker()
        apply(started)
        liveActivity.start(for: started, at: Date())
        if config.grayscale, isAppActive { runShortcut(.gray) }
    }

    private func restore() {
        guard let saved = store.loadRunning() else {
            // A card left from a session that ended while Anchor was not running would count forever.
            liveActivity.end()
            return
        }
        // Whatever happened while Anchor was not running, it was not seen as phone time.
        let resumed = saved.settingPhone(false, at: saved.lastTick)
        // A ladder scheduled before Anchor was ended would keep buzzing for nobody.
        buzzer.cancelLadder()
        liveActivity.adoptExisting()
        location.startSession()
        startTicker()
        apply(resumed)
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Bring the session up to date with where you are and what the phone is doing.
    private func reconcile() {
        now = Date()
        guard var next = session else { return }
        if let away = isAway() { next = next.settingAway(away, at: now) }
        let wantsPhone = !isAppActive && isDeviceUnlocked && now >= shortcutGraceUntil
        wantsPhoneSince = wantsPhone ? (wantsPhoneSince ?? now) : nil
        let onPhone = wantsPhoneSince.map { now.timeIntervalSince($0) >= Self.pickupDebounceSeconds } ?? false
        next = next.settingPhone(onPhone, at: now).advanced(to: now)
        apply(next)
    }

    /// Store the new session and do whatever its change calls for.
    private func apply(_ next: Session) {
        let before = session
        session = next
        if next.isComplete { return end(next) }
        if before?.onPhone != next.onPhone || before?.away != next.away
            || now.timeIntervalSince(lastSaved) >= Self.saveEverySeconds {
            store.saveRunning(next)
            lastSaved = now
        }
        applyBuzzes(before: before, next: next)
        applyEscalation(before: before, next: next)
        liveActivity.update(for: next, at: now)

        if before == nil || before?.isStudying != next.isStudying {
            buzzer.scheduleDone(at: next.projectedFinish(from: now), now: now, grayscale: next.config.grayscale)
        }
        if let before, before.away != next.away, !isAppActive {
            announceAway(next.away)
        }
    }

    private func applyBuzzes(before: Session?, next: Session) {
        let wasCounting = before?.isOnPhoneCounting ?? false
        if next.isOnPhoneCounting {
            let runningLow = next.phoneSeconds >= buzzer.scheduledThroughSeconds - Self.ladderRefillSeconds
            if !wasCounting || runningLow {
                buzzer.scheduleLadder(phoneSeconds: next.phoneSeconds, stintSeconds: next.stintSeconds)
            }
        } else if wasCounting {
            buzzer.cancelLadder()
            buzzer.clearBadge()
        }
    }

    private func applyEscalation(before: Session?, next: Session) {
        let armed = next.isOnPhoneCounting && Escalation.isArmed(stintSeconds: next.stintSeconds)
        guard armed else {
            escalator.stopAll()
            return
        }
        let wasArmed = before.map { $0.isOnPhoneCounting && Escalation.isArmed(stintSeconds: $0.stintSeconds) } ?? false
        let previous = wasArmed ? before?.phoneSeconds ?? next.phoneSeconds : next.phoneSeconds
        if let mark = Escalation.voiceMark(from: previous, to: next.phoneSeconds) {
            escalator.speak(Escalation.spokenLine(seconds: mark))
        }
        escalator.setAlarm(Escalation.isAlarm(phoneSeconds: next.phoneSeconds))
    }

    private func announceAway(_ away: Bool) {
        if away {
            buzzer.notify(id: "anchor-away", title: "You left your spot",
                          body: "Your phone is free and the timer is paused. Stop is unlocked.")
        } else {
            buzzer.notify(id: "anchor-back", title: "Back at your spot",
                          body: "The timer is running again. So is the buzzing, if you pick up your phone.")
        }
    }

    private func end(_ last: Session) {
        ticker?.invalidate()
        ticker = nil
        buzzer.cancelLadder()
        buzzer.clearBadge()
        escalator.stopAll()
        liveActivity.end()
        if !last.isComplete || isAppActive { buzzer.cancelDone() }
        location.stopSession()
        session = nil
        finished = last
        store.saveRunning(nil)
        store.saveFinished(last)
        guard last.config.grayscale else { return }
        if isAppActive { runShortcut(.color) } else { needsColorBack = true }
    }

    private func savePreferences() {
        store.saveConfig(SessionConfig(studyMinutes: minutes, radiusMeters: radiusMeters, grayscale: grayscale))
    }

    // MARK: - Location rules

    private func isUsableAnchor(_ fix: CLLocation) -> Bool {
        AnchorRules.isUsableAnchor(accuracy: fix.horizontalAccuracy, age: -fix.timestamp.timeIntervalSinceNow)
    }

    /// nil when there is no fix good enough to decide.
    private func isAway() -> Bool? {
        guard let session, let fix, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= Self.maxDecidingAccuracy else { return nil }
        return AnchorRules.isAway(distance: Geo.distanceMeters(session.anchor, fix.point), unlockDistance: unlockDistance)
    }
}

extension CLLocation {
    var point: GeoPoint { GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude) }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}
