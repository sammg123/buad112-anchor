import CoreLocation
import LocalAuthentication
import Observation
import SwiftUI
import UIKit
import os

/// Runs a session: turns where you are (no-phone zones, from GPS and study-area beacons), the lock state and Anchor
/// being on screen into the session's three clocks, and turns the session into buzzes, the voice, the alarm and the
/// Live Activity. Every rule lives in `Session`, `Ladder`, `Escalation` and `ZoneRules`; this only wires them up.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable { case permissions, precise, start, session, done }

    /// Unlocking straight into Anchor shows Anchor in the background for a moment; a "pickup" this short that ends
    /// in Anchor is taken back.
    private static let quickReturnSeconds = 3.0
    private static let saveEverySeconds = 10.0
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "session")
    #if DEBUG
    /// Simulator screenshots: the Always prompt would cover the screen.
    private static let skipsAlwaysPrompt = ProcessInfo.processInfo.arguments.contains("-onboarded")
    #else
    private static let skipsAlwaysPrompt = false
    #endif
    /// Top the buzz ladder up when fewer than this many seconds of it are left.
    private static let ladderRefillSeconds = 60.0
    /// Arrival notices and auto-starts for the same zone and area at most this often (also after a session ends
    /// there, so a finished session doesn't start itself again).
    private static let arrivalCooldownSeconds = 30.0 * 60
    /// A start from a notification gives up if being in the zone can't be confirmed this soon.
    private static let confirmZoneSeconds = 20.0
    /// "Drop anchor here" gives up if no usable reading comes this soon.
    private static let findSpotSeconds = 45.0
    /// The test host app must not open the location monitor (it can only be opened once per process).
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private(set) var session: Session?
    private(set) var finished: Session?
    private(set) var fix: CLLocation?
    private(set) var now = Date()
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var notificationsAllowed = false
    private(set) var isPrecise = false
    /// Every zone, your cleaned-up position against each, and which study-area beacon is close.
    let tracker: ZoneTracker
    /// Areas you drew on the map.
    private(set) var userZones: [Zone]
    /// Beacon mode (Settings, TestFlight only): this phone broadcasts a study area's beacon.
    let broadcaster = BeaconBroadcaster()
    /// Zones iOS says you're near (their wake circle); GPS and ranging stay on while there are any.
    private(set) var nearZones: Set<String> = []
    private(set) var hasPasscode = true
    private(set) var isFindingSpot = false
    private(set) var hasOnboarded: Bool
    /// Dev pause for testing: everything stops as if you had walked away (Stop unlocks too). TestFlight and
    /// debug builds only.
    private(set) var isPaused = false
    static let showsDevTools: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
    var minutes: Int { didSet { savePreferences() } }
    var library: Bool { didSet { savePreferences() } }
    var graceSeconds: Double { didSet { savePreferences() } }
    /// "Drop anchor here": Stop stays locked inside this circle around you.
    var radiusMeters: Double { didSet { savePreferences() } }
    /// Start a session by itself when you walk into a no-phone zone, instead of asking first.
    var autoStart: Bool { didSet { store.autoStart = autoStart } }
    var notice: String?

    private let store = SessionStore()
    private let location = LocationService()
    private let buzzer = Buzzer()
    private let escalator = Escalator()
    private let liveActivity = LiveActivityController()
    private let beacons = BeaconService()
    /// The walking key for your own anchor.
    private let motion = MotionTracker()
    private(set) var motionAllowed = MotionTracker.isAuthorized
    let volumeGuard = VolumeGuard()
    /// Launched in the background (iOS relaunching a session), Anchor is not on screen until a scene says so.
    private var isAppActive = UIApplication.shared.applicationState != .background
    /// Locked or unlocked, from iOS's and SpringBoard's notices.
    private var lockTracker = LockTracker(isUnlocked: true)
    private var isDeviceUnlocked: Bool { lockTracker.isUnlocked }
    /// When the phone became unlocked with Anchor not on screen; it counts once the glance grace has passed.
    private var outsideAnchorSince: Date?
    private let screenWatcher = ScreenWatcher()
    /// A zone start (from the arrival notice) waiting until being in the zone is confirmed.
    private var pendingZoneID: String?
    /// "Drop anchor here" waiting for a usable reading.
    private(set) var isDroppingAnchor = false
    /// Which start attempt the 20 s give-up belongs to, so an older one can't cancel a newer one.
    private var pendingAttempt: UUID?
    /// Keeps `now` (and the start screen) current with no session running.
    private var idleTicker: Timer?
    /// The latest zone-watch update; each waits for the one before.
    private var watchUpdate: Task<Void, Never>?
    private var lastSaved = Date.distantPast
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    /// Simulator only (no step counter): GPS movement during a session stands in for walking.
    private var fakesWalking = false
    private var lastFakePoint: GeoPoint?
    /// Simulator only: start a zone session as soon as you're in one.
    private var autoStartsZone = false
    #endif

    init() {
        #if DEBUG
        // UI tests: begin with no running or finished session.
        if ProcessInfo.processInfo.arguments.contains("-freshStart") {
            store.saveRunning(nil)
            store.saveFinished(nil)
        }
        #endif
        let saved = store.loadConfig()
        minutes = saved?.studyMinutes ?? SetupInput.defaultMinutes
        library = saved?.isLibrary ?? false
        graceSeconds = saved?.graceSeconds ?? PickupRule.defaultGraceSeconds
        radiusMeters = AnchorRules.clampedRadius(saved?.radiusMeters ?? AnchorRules.defaultRadiusMeters)
        autoStart = store.autoStart
        hasOnboarded = store.hasOnboarded
        finished = store.loadFinished()
        // The zones file's places (Leavey) join your areas once, so you can edit or delete them like any other;
        // its study-room beacons are kept for when real ones exist.
        let bundled = Self.loadZones()
        if bundled.isEmpty { Self.log.error("no zones from the zones file") }
        let drawn = store.seededAreas ? store.loadUserZones() : DrawnArea.seeded(from: bundled, into: store.loadUserZones())
        if !store.seededAreas, !bundled.isEmpty {
            store.saveUserZones(drawn)
            store.seededAreas = true
        }
        userZones = drawn
        tracker = ZoneTracker(zones: drawn)
        locationStatus = location.status
        isPrecise = location.isPrecise
        location.onFix = { [weak self] fix in self?.received(fix) }
        location.onAuthorizationChange = { [weak self] status in self?.authorizationChanged(status) }
        beacons.onSighting = { [weak self] area, proximity, accuracy in
            self?.sighted(area, proximity: proximity, accuracy: accuracy)
        }
        beacons.onRanged = { [weak self] in self?.tracker.ranged(at: Date()) }
        motion.onSegment = { [weak self] segment in self?.tracker.walked(segment) }
        startIdleTicker()
        startZoneWatch()
        observeZoneStarts()
        screenWatcher.onBlank = { [weak self] blank in self?.screenChanged(blank: blank) }
        screenWatcher.onLockComplete = { [weak self] in self?.lockCompleted() }
        screenWatcher.onLockState = { [weak self] locked, blank in self?.lockStateChanged(reportsLocked: locked, screenBlank: blank) }
        screenWatcher.start()
        observeLockState()
        restore()
        location.startForeground()
        updateTracking()
        #if DEBUG
        // Simulator screenshots only.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-onboarded") { hasOnboarded = true }
        autoStartsZone = args.contains("-autozone")
        fakesWalking = args.contains("-fakeWalk")
        if args.contains("-autostart"), session == nil { dropAnchor() }
        if args.contains("-fakeBeacon") { startFakeBeacon() }
        if args.contains("-resetAreas") { setUserZones([]) }
        #endif
    }

    #if DEBUG
    /// Simulator only (it has no Bluetooth): pretend the first study area's beacon is near, every second.
    private func startFakeBeacon() {
        guard let zone = tracker.zones.first(where: { !$0.studyAreas.isEmpty }), let area = zone.studyAreas.first else { return }
        let key = AreaKey(zoneID: zone.id, areaID: area.id)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sighted(key, proximity: .near, accuracy: 2) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
    #endif

    // MARK: - What the screens read

    var screen: Screen {
        if session != nil { return .session }
        if finished != nil { return .done }
        if !hasOnboarded || !hasLocation { return .permissions }
        if !isPrecise { return .precise }
        return .start
    }

    var hasLocation: Bool { locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse }
    /// Location and Precise Location are required; zones can't work on approximate location.
    var isReadyToStart: Bool { PermissionGate.isReady(location: hasLocation, precise: isPrecise) }

    var locationDenied: Bool { locationStatus == .denied || locationStatus == .restricted }

    var isStopUnlocked: Bool { session?.away ?? false }

    /// Where you are: in a study area, in a zone's building but not a study area, or outside all zones.
    var place: PlaceStatus { tracker.place(at: now) }

    /// The zone (and study area) you could start a session in right now.
    var startable: (zone: Zone, area: StudyArea?)? { tracker.lockingZone(at: now) }

    /// Roughly how much farther to walk before Stop unlocks: out past the edge by the GPS accuracy (the whole
    /// accuracy circle has to be outside).
    /// Your dot and its fuzz for the maps.
    var you: (center: GeoPoint, radius: Double)? {
        tracker.you(at: now, fallback: fix?.reading)
    }

    var motionDenied: Bool { MotionTracker.isDenied }

    /// Motion & Fitness: the second key that makes your own anchor's 25 m exact.
    func requestMotion() async {
        _ = await motion.requestPermission()
        motionAllowed = MotionTracker.isAuthorized
        updateMotion()
    }

    /// The walking key runs during a dropped-anchor session when Motion & Fitness is on.
    private func updateMotion() {
        let wanted = motionAllowed && MotionTracker.isAvailable && session?.isDroppedAnchor == true
        if wanted { motion.start() } else { motion.stop() }
        #if DEBUG
        if fakesWalking, session?.isDroppedAnchor == true { tracker.usesWalkKey = true; return }
        #endif
        tracker.usesWalkKey = wanted
    }

    /// GPS error right now (the margin used at edges), for the start screen.
    var gpsMargin: Double? {
        tracker.freshEstimate(at: now).map(tracker.margin(for:))
    }

    /// A dropped anchor: how far you are from it and how far out Stop unlocks (your radius plus the GPS margin).
    var anchorReadout: (meters: Double, unlocksAt: Double)? {
        guard let session, session.isDroppedAnchor, let here = tracker.freshEstimate(at: now) else { return nil }
        let radius = session.area.enclosingCircle.radius
        // With the walking key, 25 m means 25 m; on GPS alone the whole fuzz circle has to clear the line.
        let unlocksAt = tracker.usesWalkKey ? radius : radius + tracker.margin(for: here)
        return (Geo.distanceMeters(session.area.center, here.point), unlocksAt)
    }

    /// Meters to the nearest way out of a building (its edge), while you're inside one; nil otherwise.
    func metersToEdge(of zone: Zone) -> Double? {
        tracker.depth(in: zone, at: now).flatMap { $0 > 0 ? $0 : nil }
    }

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
        isPrecise = location.isPrecise
        motionAllowed = MotionTracker.isAuthorized
        // Motion & Fitness turned off mid-session: fall back to GPS alone rather than wait for steps forever.
        updateMotion()
        hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        notificationsAllowed = await buzzer.isAuthorized()
        if locationStatus == .authorizedWhenInUse, !Self.skipsAlwaysPrompt { location.requestAlways() }
    }

    /// The Precise Location screen's button: iOS asks to turn it on until Anchor is closed.
    func requestPrecise() {
        location.requestPrecise()
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        locationStatus = status
        isPrecise = location.isPrecise
        // Arrival wake-ups need Always; make sure they're registered once it's granted.
        if status == .authorizedAlways { startZoneWatch() }
    }

    // MARK: - Session lifecycle

    /// Start a session in a no-phone zone (the start screen, the arrival notice, or auto-start). It only starts once
    /// you're confirmed in the zone, so an old notification tapped at home can't lock anything.
    func startZoneSession(_ zoneID: String) {
        guard session == nil, let zone = tracker.zones.first(where: { $0.id == zoneID }) else { return }
        isDroppingAnchor = false
        guard isReadyToStart else {
            notice = "Anchor needs Location with Precise Location on. Turn them on in Settings › Anchor › Location."
            return
        }
        // Your own area starts right away; outside it, the session simply waits as "away" until you walk in.
        if zone.isUserArea { return begin(in: zone, areaID: nil) }
        now = Date()
        if case .locked(let areaID) = tracker.lock(for: zone, at: now) {
            begin(in: zone, areaID: areaID)
            return
        }
        pendingZoneID = zone.id
        let attempt = UUID()
        pendingAttempt = attempt
        isFindingSpot = true
        location.refresh()
        updateTracking()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.confirmZoneSeconds))
            self?.givePendingUp(zone, attempt: attempt)
        }
    }

    private func checkPendingZone() {
        guard let id = pendingZoneID, let zone = tracker.zones.first(where: { $0.id == id }),
              case .locked(let areaID) = tracker.lock(for: zone, at: now) else { return }
        begin(in: zone, areaID: areaID)
    }

    private func givePendingUp(_ zone: Zone, attempt: UUID) {
        guard pendingZoneID == zone.id, pendingAttempt == attempt, session == nil else { return }
        cancelFindingSpot()
        notice = zone.usesWholeBuilding
            ? "You're not in \(zone.name) right now, so there's nothing to lock."
            : "You're not in one of \(zone.name)'s study areas right now, so there's nothing to lock."
    }

    // MARK: - Your areas

    /// Saves an outline you drew; returns why it can't be saved, if it can't.
    @discardableResult
    func saveDrawnArea(name: String, points: [GeoPoint]) -> DrawnArea.Problem? {
        if let problem = DrawnArea.problem(with: points) { return problem }
        setUserZones(userZones + [DrawnArea.zone(named: name, points: points, id: DrawnArea.newID())])
        return nil
    }

    /// Moves an area's corners; returns why it can't, if it can't (an outline that crosses, or the area a session
    /// is running in).
    @discardableResult
    func reshapeUserZone(_ id: String, to points: [GeoPoint]) -> String? {
        guard session?.area.id != id else { return "That area has a session running in it. End the session first." }
        guard let index = userZones.firstIndex(where: { $0.id == id }) else { return "That area is gone." }
        // Corners dragged across each other: untangle rather than refuse.
        let outline = DrawnArea.crossesItself(points) ? DrawnArea.untangled(points) : points
        switch DrawnArea.reshaped(userZones[index], to: outline) {
        case .failure(let problem):
            return problem.hint
        case .success(let zone):
            setUserZones(userZones.enumerated().map { $0.offset == index ? zone : $0.element })
            return nil
        }
    }

    /// Deletes areas you drew (not one a session is running in).
    func deleteUserZones(_ ids: Set<String>) {
        let inUse = Set([session?.area.id].compactMap { $0 })
        if !ids.isDisjoint(with: inUse) { notice = "That area has a session running in it. End the session first." }
        let remove = ids.subtracting(inUse)
        setUserZones(userZones.filter { !remove.contains($0.id) })
    }

    private func setUserZones(_ zones: [Zone]) {
        userZones = zones
        store.saveUserZones(zones)
        tracker.setZones(zones)
        // A deleted area's watch is dropped without an "left" event; forget it here so GPS can rest.
        nearZones.formIntersection(tracker.zones.map(\.id))
        startZoneWatch()
        updateTracking()
    }

    /// "Drop anchor here": a session anywhere, locked to a circle around you. It waits for a usable reading.
    func dropAnchor() {
        guard session == nil else { return }
        guard isReadyToStart else {
            notice = "Anchor needs Location with Precise Location on. Turn them on in Settings › Anchor › Location."
            return
        }
        // Only on a sharp position: an anchor dropped on a rough reading lands where you aren't.
        if tracker.isLockedOn(at: Date()), let fix {
            beginAnchor(at: fix)
        } else {
            dropWaitStarted = Date()
            pendingZoneID = nil
            isDroppingAnchor = true
            isFindingSpot = true
            location.refresh()
            let attempt = UUID()
            pendingAttempt = attempt
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.findSpotSeconds))
                self?.giveDropUp(attempt: attempt)
            }
        }
    }

    /// After a while without sharp GPS, the waiting screen offers dropping on what there is.
    static let dropAnywayAfterSeconds = 15.0
    /// When the current wait for sharp GPS began.
    private(set) var dropWaitStarted: Date?

    /// "Drop anyway": the best position there is, with the circle widened by its error.
    func dropAnchorAnyway() {
        guard isDroppingAnchor, let fix, isUsableAnchor(fix) else {
            notice = "No usable GPS yet. Step near a window or outside for a moment."
            return
        }
        beginAnchor(at: fix)
    }

    /// No usable reading in time (deep indoors, say): stop waiting rather than start somewhere stale later.
    private func giveDropUp(attempt: UUID) {
        guard isDroppingAnchor, pendingAttempt == attempt, session == nil else { return }
        cancelFindingSpot()
        notice = "Couldn't get a sharp enough GPS reading here. Try near a window, or step outside and drop it there."
    }

    private func isUsableAnchor(_ fix: CLLocation) -> Bool {
        fix.reading.isSpoofed == false
            && AnchorRules.isUsableAnchor(accuracy: fix.horizontalAccuracy, age: -fix.timestamp.timeIntervalSinceNow)
    }

    /// The anchor goes where the smoothed position says you are (steadier than one reading). With only a rough
    /// reading, the circle widens by the part of its error the edge margin doesn't already cover.
    private func beginAnchor(at fix: CLLocation) {
        let radius = AnchorRules.clampedRadius(radiusMeters)
        if let here = tracker.freshEstimate(at: Date()) {
            return begin(in: Zone.droppedAnchor(center: here.point, radius: radius), areaID: nil, radius: radius,
                         anchorAccuracy: here.accuracy)
        }
        // Only a rough reading: the circle starts widened by its error, and shrinks back to your radius as soon as
        // the anchor settles onto a sharp one.
        let extra = max(0, fix.horizontalAccuracy - LocationFilter.minMarginMeters)
        begin(in: Zone.droppedAnchor(center: fix.point, radius: radius + extra), areaID: nil, radius: radius,
              anchorAccuracy: fix.horizontalAccuracy)
    }

    func cancelFindingSpot() {
        isDroppingAnchor = false
        dropWaitStarted = nil
        pendingZoneID = nil
        isFindingSpot = false
        updateTracking()
    }

    /// Stop is only allowed out of the zone (or once the timer is done, which ends the session itself).
    func stop() {
        guard let current = session?.advanced(to: Date()), current.away else { return }
        end(current)
    }

    func togglePause() {
        guard Self.showsDevTools, session != nil else { return }
        isPaused.toggle()
        reconcile()
    }

    /// Settings' test: a buzz in 5 s, so you can lock the phone or go home and feel it.
    func testBuzz() {
        buzzer.testBuzz(silent: library)
    }

    func startOver() {
        finished = nil
        store.saveFinished(nil)
    }

    // MARK: - Inputs

    func setAppActive(_ active: Bool) {
        isAppActive = active
        if active { lockTracker = lockTracker.opened() }
        if active, let current = session, current.onPhone, current.stintSeconds <= Self.quickReturnSeconds {
            apply(current.lockedPhone(at: Date(), unseenSeconds: Self.quickReturnSeconds))
        }
        if active {
            // A session started from a notification while iOS still had Anchor in the background gets its card now.
            if let current = session { liveActivity.start(for: current, at: Date()) }
            Task { await refreshPermissions() }
        }
        updateTracking()
        reconcile()
    }

    // MARK: - Zones

    private static func loadZones() -> [Zone] {
        do {
            return try BundledZoneStore().zones()
        } catch {
            log.error("zones file: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// iOS watches a circle around each zone and each study area's beacon, and wakes Anchor near them.
    private func startZoneWatch() {
        guard !Self.isRunningTests, !tracker.zones.isEmpty else { return }
        let zones = ZoneRules.watchable(tracker.zones)
        if zones.count < tracker.zones.count {
            Self.log.notice("watching \(zones.count) of \(self.tracker.zones.count) zones: iOS allows 20 conditions")
        }
        // In order: a save then a delete must reach the watch as a save then a delete.
        let previous = watchUpdate
        watchUpdate = Task {
            await previous?.value
            await ZoneWatch.shared.watch(zones) { [weak self] event in
                Task { @MainActor in self?.zoneEvent(event) }
            }
        }
    }

    private func zoneEvent(_ event: ZoneWatch.Event) {
        switch event {
        case .nearZone(let id, let isNear):
            nearZones = isNear ? nearZones.union([id]) : nearZones.subtracting([id])
        case .areaInRange(let key, let inRange) where inRange:
            nearZones = nearZones.union([key.zoneID])
        case .areaInRange:
            break
        }
        updateTracking()
    }

    /// GPS in the background and beacon ranging run during a session, near a zone, or while confirming a start;
    /// ranging also runs whenever Anchor is on screen.
    private func updateTracking() {
        let near = !nearZones.isEmpty || pendingZoneID != nil
        location.setNearZone(near && session == nil)
        beacons.setBackground(session != nil || near)
        if isAppActive || session != nil || near {
            beacons.startRanging(tracker.allZones)
        } else {
            beacons.stopRanging()
        }
    }

    private func received(_ newFix: CLLocation) {
        fix = newFix
        now = Date()
        if isDroppingAnchor, session == nil, tracker.isLockedOn(at: now) { return beginAnchor(at: newFix) }
        let verdict = tracker.received(newFix.reading, at: now)
        #if DEBUG
        if fakesWalking, session != nil, let last = lastFakePoint {
            let moved = ZoneGeometry.meters(newFix.point, from: last)
            let meters = (moved.x * moved.x + moved.y * moved.y).squareRoot()
            if meters > 0.3 { tracker.walked(WalkSegment(time: now, meters: meters, heading: atan2(moved.x, moved.y))) }
        }
        lastFakePoint = newFix.point
        #endif
        settleAnchor()
        if verdict == .spoofed, let current = session {
            // A faked reading: ignored, you count as still in the zone, and the session remembers it.
            tracker.spoofed(in: current.area.id, at: now)
            Self.log.notice("spoofed location reading during a session")
            apply(current.countingSpoof().advanced(to: now))
        }
        zoneChanged()
    }

    /// A dropped anchor's first minute: move it onto a sharper reading while you're still sitting by it.
    private func settleAnchor() {
        guard let current = session, current.isDroppedAnchor, let radius = current.config.radiusMeters,
              let here = tracker.freshEstimate(at: now),
              AnchorRules.shouldSettle(anchorAccuracy: current.anchorAccuracy, estimateAccuracy: here.accuracy,
                                       metersFromAnchor: Geo.distanceMeters(current.anchor, here.point),
                                       sessionAge: now.timeIntervalSince(current.startedAt),
                                       walkedMeters: tracker.walk.netMeters(at: now)) else { return }
        let settled = current.reanchored(to: Zone.droppedAnchor(center: here.point, radius: radius), accuracy: here.accuracy)
        tracker.moveExtraZone(to: settled.area)
        session = settled
        store.saveRunning(settled)
    }

    private func sighted(_ area: AreaKey, proximity: BeaconProximity, accuracy: Double) {
        now = Date()
        tracker.sighted(area, proximity: proximity, accuracy: accuracy, at: now)
        zoneChanged()
    }

    private func zoneChanged() {
        if session != nil { return reconcile() }
        if pendingZoneID != nil { return checkPendingZone() }
        #if DEBUG
        if autoStartsZone, let here = startable {
            autoStartsZone = false
            return begin(in: here.zone, areaID: here.area?.id)
        }
        #endif
        checkArrival()
    }

    /// You walked into a zone with no session running: start one (Auto-start) or offer it, at most every
    /// 30 minutes per zone (counting from the last session there too). On screen without Auto-start, the start
    /// screen already offers it.
    private func checkArrival() {
        guard session == nil, pendingZoneID == nil, !isDroppingAnchor, let here = startable,
              autoStart || !isAppActive else { return }
        let key = here.zone.id
        if let last = store.lastArrival(atZone: key), now.timeIntervalSince(last) < Self.arrivalCooldownSeconds { return }
        store.saveArrival(atZone: key, at: now)
        if autoStart {
            begin(in: here.zone, areaID: here.area?.id)
        }
        if !isAppActive {
            buzzer.zoneArrival(here.zone, area: here.area, started: autoStart)
        }
    }

    /// With no session: keep the clock (and so the status line, Start button and arrival check) current even
    /// when no new reading arrives.
    private func startIdleTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session == nil else { return }
                self.now = Date()
                self.zoneChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTicker = timer
    }

    /// The arrival notification's Start button.
    private func observeZoneStarts() {
        observers.append(NotificationCenter.default.addObserver(forName: .anchorStartZone, object: nil, queue: .main) { [weak self] note in
            let id = note.userInfo?["zone"] as? String
            MainActor.assumeIsolated {
                guard let id else { return }
                self?.startZoneSession(id)
            }
        })
    }

    private func observeLockState() {
        // Opened by the student, the phone is unlocked. Relaunched in the background, ask iOS.
        lockTracker = LockTracker(isUnlocked: isAppActive || UIApplication.shared.isProtectedDataAvailable)
        let center = NotificationCenter.default
        observers += [
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lockTracker = self.lockTracker.protectedData(available: true, at: Date())
                    self.reconcile()
                }
            },
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.deviceLocked() }
            }
        ]
    }

    /// iOS says "locked" about 10 s after the fact; those seconds were not phone time. When the screen-off notice
    /// already caught the lock, there is nothing left to take back.
    private func deviceLocked() {
        let alreadySeen = !isDeviceUnlocked
        lockTracker = lockTracker.protectedData(available: false, at: Date())
        outsideAnchorSince = nil
        guard let current = session, current.onPhone else { return reconcile() }
        apply(current.lockedPhone(at: Date(), unseenSeconds: alreadySeen ? 0 : Ladder.lockLagSeconds))
    }

    /// Screen off is a lock as far as Anchor is concerned, right away.
    private func screenChanged(blank: Bool) {
        lockTracker = lockTracker.screen(blank: blank, at: Date())
        guard blank else { return }
        lockedNow()
    }

    private func lockCompleted() {
        lockTracker = lockTracker.lockCompleted(at: Date())
        lockedNow()
    }

    /// Every lock and unlock: an unlock starts the grace period right away, however soon after the last lock.
    private func lockStateChanged(reportsLocked: Bool?, screenBlank: Bool) {
        let wasUnlocked = isDeviceUnlocked
        lockTracker = lockTracker.lockStateChanged(at: Date(), reportsLocked: reportsLocked, screenBlank: screenBlank)
        Self.log.info("lock state: \(self.isDeviceUnlocked ? "unlocked" : "locked") (was \(wasUnlocked ? "unlocked" : "locked"), screen \(screenBlank ? "off" : "on"))")
        if isDeviceUnlocked { return reconcile() }
        lockedNow()
    }

    /// The phone is locked as of now: nothing from here on is phone time.
    private func lockedNow() {
        outsideAnchorSince = nil
        guard let current = session, current.onPhone else { return reconcile() }
        apply(current.lockedPhone(at: Date(), unseenSeconds: 0))
    }

    // MARK: - The loop

    /// Starts a session in a zone from the zones file, or (with `radius`) at a dropped anchor's circle.
    private func begin(in zone: Zone, areaID: String?, radius: Double? = nil, anchorAccuracy: Double = 0) {
        pendingZoneID = nil
        isDroppingAnchor = false
        isFindingSpot = false
        finished = nil
        store.saveFinished(nil)
        let config = SessionConfig(studyMinutes: minutes, library: library, grace: graceSeconds,
                                   radiusMeters: radius, zoneID: zone.isDroppedAnchor ? nil : zone.id, areaID: areaID)
        let started = Session.start(config: config, zone: zone, anchorAccuracy: anchorAccuracy, at: Date())
        if !zone.isDroppedAnchor { store.saveArrival(atZone: zone.id, at: Date()) }
        tracker.setExtraZone(zone)
        tracker.resetWalk()
        dropWaitStarted = nil
        location.startSession()
        updateTracking()
        escalator.startKeepAlive()
        volumeGuard.setEnforcing(!config.isLibrary)
        startTicker()
        apply(started)
        // After the session exists: the walking key is for dropped anchors only.
        updateMotion()
        liveActivity.start(for: started, at: Date())
    }

    private func restore() {
        // The unit-test host must not resume a session (one left by a UI test hangs it before tests connect).
        guard !Self.isRunningTests, let saved = store.loadRunning() else {
            // A card left from a session that ended while Anchor was not running would count forever.
            liveActivity.end()
            return
        }
        // Whatever happened while Anchor was not running, it was not seen as phone time.
        let resumed = saved.settingPhone(false, at: saved.lastTick)
        // A ladder scheduled before Anchor was ended would keep buzzing for nobody.
        buzzer.cancelLadder()
        liveActivity.adoptExisting()
        // A dropped anchor (or a session saved before zones) keeps its circle.
        tracker.setExtraZone(saved.area)
        location.startSession()
        defer { updateMotion() }
        escalator.startKeepAlive()
        volumeGuard.setEnforcing(!saved.config.isLibrary)
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
        if isPaused {
            next = next.settingAway(true, at: now)
        } else if let away = isAway() {
            next = next.settingAway(away, at: now)
        }
        syncLockState()
        escalator.keepPlaying()
        let outside = !isAppActive && isDeviceUnlocked
        outsideAnchorSince = outside ? (outsideAnchorSince ?? now) : nil
        let onPhone = PickupRule.isOnPhone(outsideAnchorSince: outsideAnchorSince, now: now,
                                           grace: Escalation.graceSeconds(configured: next.config.graceSeconds))
        next = next.settingPhone(onPhone, at: now).advanced(to: now)
        apply(next)
    }

    /// Store the new session and do whatever its change calls for.
    private func apply(_ next: Session) {
        let before = session
        session = next
        if next.isComplete { return end(next) }
        if before?.onPhone != next.onPhone || before?.away != next.away {
            Self.log.info("on phone \(next.onPhone), away \(next.away), phone \(Int(next.phoneSeconds))s, active \(self.isAppActive), unlocked \(self.isDeviceUnlocked)")
        }
        if before?.onPhone != next.onPhone || before?.away != next.away
            || now.timeIntervalSince(lastSaved) >= Self.saveEverySeconds {
            store.saveRunning(next)
            lastSaved = now
        }
        applyBuzzes(before: before, next: next)
        applyEscalation(before: before, next: next)
        liveActivity.update(for: next, at: now, graceEndsAt: graceEndsAt(for: next))

        if before == nil || before?.isStudying != next.isStudying {
            buzzer.scheduleDone(at: next.projectedFinish(from: now), now: now)
        }
        if let before, before.away != next.away, !isAppActive, !isPaused {
            announceAway(next.away, spot: next.isDroppedAnchor)
        }
    }

    /// While unlocked and out of Anchor but still inside the grace period: when it runs out.
    private func graceEndsAt(for session: Session) -> Date? {
        guard let since = outsideAnchorSince, !session.onPhone, !session.away else { return nil }
        let grace = Escalation.graceSeconds(configured: session.config.graceSeconds)
        return grace > 0 ? since.addingTimeInterval(grace) : nil
    }

    private func applyBuzzes(before: Session?, next: Session) {
        let wasCounting = before?.isOnPhoneCounting ?? false
        if next.isOnPhoneCounting, !wasCounting {
            // Grace is over: the effects start now, from wherever the ladder was.
            buzzer.pickupBuzz(phoneSeconds: next.phoneSeconds, silent: next.config.isLibrary)
            escalator.vibrate()
        }
        if next.isOnPhoneCounting {
            let runningLow = next.phoneSeconds >= buzzer.scheduledThroughSeconds - Self.ladderRefillSeconds
            if !wasCounting || runningLow {
                buzzer.scheduleLadder(phoneSeconds: next.phoneSeconds, stintSeconds: next.stintSeconds,
                                      silent: next.config.isLibrary)
            }
        } else if wasCounting {
            buzzer.cancelLadder()
            buzzer.clearBadge()
        }
    }

    private func applyEscalation(before: Session?, next: Session) {
        let armed = next.isOnPhoneCounting && Escalation.isArmed(stintSeconds: next.stintSeconds)
        guard armed else {
            escalator.stopEscalation()
            return
        }
        let wasArmed = before.map { $0.isOnPhoneCounting && Escalation.isArmed(stintSeconds: $0.stintSeconds) } ?? false
        let previous = wasArmed ? before?.phoneSeconds ?? next.phoneSeconds : next.phoneSeconds
        // Library mode too: nonstop vibration from 0:30 of phone time until the pickup ends.
        if Escalation.isContinuousVibration(phoneSeconds: next.phoneSeconds) {
            escalator.startBuzzing()
        } else {
            escalator.stopBuzzing()
        }
        guard !next.config.isLibrary else { return }
        if let mark = Escalation.voiceMark(from: previous, to: next.phoneSeconds) {
            escalator.speak(Escalation.spokenLine(seconds: mark))
        }
        escalator.setAlarm(Escalation.isAlarm(phoneSeconds: next.phoneSeconds))
    }

    private func announceAway(_ away: Bool, spot: Bool) {
        let place = spot ? "your spot" : "the no-phone zone"
        if away {
            buzzer.notify(id: "anchor-away", title: "You left \(place)",
                          body: "Your phone is free and the timer is paused. Stop is unlocked.")
        } else {
            buzzer.notify(id: "anchor-back", title: "Back at \(place)",
                          body: "The timer is running again. So is the buzzing, if you pick up your phone.")
        }
    }

    private func end(_ last: Session) {
        ticker?.invalidate()
        ticker = nil
        isPaused = false
        buzzer.cancelLadder()
        buzzer.clearBadge()
        escalator.stopEverything()
        volumeGuard.setEnforcing(false)
        liveActivity.end()
        if !last.isComplete || isAppActive { buzzer.cancelDone() }
        location.stopSession()
        if let zone = last.zone, !zone.isDroppedAnchor {
            // Still sitting there when it ends: don't start another one by itself.
            store.saveArrival(atZone: zone.id, at: Date())
        }
        tracker.setExtraZone(nil)
        session = nil
        updateTracking()
        updateMotion()
        finished = last
        store.saveRunning(nil)
        store.saveFinished(last)
    }

    private func savePreferences() {
        store.saveConfig(SessionConfig(studyMinutes: minutes, library: library,
                                       grace: graceSeconds, radiusMeters: radiusMeters))
    }

    // MARK: - Location rules

    /// In case a lock or unlock notice was missed, ask iOS directly. Right after a lock notice its answer can lag,
    /// so "unlocked" is only believed after a quiet spell. Without a passcode iOS always says unlocked: skip it.
    private func syncLockState() {
        guard hasPasscode else { return }
        lockTracker = lockTracker.tick(dataAvailable: UIApplication.shared.isProtectedDataAvailable, at: now)
    }

    /// Location decides. During a session every area locks, not just the one it started in: you're away only
    /// when your own place is free and you're in none of your areas. Nil when there isn't enough to go on.
    private func isAway() -> Bool? {
        guard let session else { return nil }
        let others = tracker.zones.filter { $0.id != session.area.id }.map { tracker.lock(for: $0, at: now) }
        return ZoneRules.sessionAway(own: tracker.lock(for: session.area, at: now), others: others)
    }

    /// During a session, another of your areas holding you in (you walked from your anchor into Leavey, say).
    var lockedByOtherArea: Zone? {
        guard let session, !isLocked(session.area) else { return nil }
        return tracker.zones.first { $0.id != session.area.id && isLocked($0) }
    }

    private func isLocked(_ zone: Zone) -> Bool {
        if case .locked = tracker.lock(for: zone, at: now) { return true }
        return false
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}
