import Foundation

/// Inside or outside one building's outline, without flicker. Each reading is a circle of its accuracy:
/// - mostly inside the outline: inside, right away;
/// - wholly outside: outside, but only after 3 such readings in a row *and* 10 s, whichever comes later;
/// - straddling the edge: says nothing, and breaks a run of outside readings.
/// With no usable reading for 30 s (indoor GPS is often worse than 20 m) it no longer claims to know.
struct BuildingPresence: Equatable, Sendable {
    enum State: Equatable, Sendable { case unknown, inside, outside }

    static let exitReadings = 3
    static let exitSeconds = 10.0
    static let staleSeconds = 30.0

    let state: State
    let outsideRun: Int
    let outsideSince: Date?
    let lastReadingAt: Date?

    static let unknown = BuildingPresence(state: .unknown, outsideRun: 0, outsideSince: nil, lastReadingAt: nil)

    func updated(with fit: CircleFit, at now: Date) -> BuildingPresence {
        let fresh = lastReadingAt.map { now.timeIntervalSince($0) <= Self.staleSeconds } ?? false
        let known = fresh ? state : .unknown
        switch fit {
        case .mostlyInside:
            return BuildingPresence(state: .inside, outsideRun: 0, outsideSince: nil, lastReadingAt: now)
        case .straddling:
            return BuildingPresence(state: known, outsideRun: 0, outsideSince: nil, lastReadingAt: now)
        case .fullyOutside:
            let run = (fresh ? outsideRun : 0) + 1
            let since = (fresh ? outsideSince : nil) ?? now
            let isOut = known == .outside
                || (run >= Self.exitReadings && now.timeIntervalSince(since) >= Self.exitSeconds)
            return BuildingPresence(state: isOut ? .outside : known, outsideRun: run, outsideSince: since,
                                    lastReadingAt: now)
        }
    }

    /// A reading too rough for the filter: only a wholly-outside one counts, toward leaving; anything else is ignored.
    func updatedRough(with fit: CircleFit, at now: Date) -> BuildingPresence {
        fit == .fullyOutside ? updated(with: fit, at: now) : self
    }

    /// A faked reading: ignored, and the person is treated as still in the zone.
    func spoofed(at now: Date) -> BuildingPresence {
        BuildingPresence(state: .inside, outsideRun: 0, outsideSince: nil, lastReadingAt: now)
    }

    func state(at now: Date) -> State {
        guard let lastReadingAt, now.timeIntervalSince(lastReadingAt) <= Self.staleSeconds else { return .unknown }
        return state
    }

    /// For the status line only: not known yet but the latest reading was wholly outside reads as outside. Leaving a
    /// session still waits for the full exit rule.
    func displayState(at now: Date) -> State {
        let current = state(at: now)
        let fresh = lastReadingAt.map { now.timeIntervalSince($0) <= Self.staleSeconds } ?? false
        return current == .unknown && outsideRun > 0 && fresh ? .outside : current
    }
}

/// How close a beacon is, as iOS ranges it.
enum BeaconProximity: Equatable, Sendable { case immediate, near, far, unknown }

/// Which study area you're in, from beacon ranging.
enum BeaconRules {
    /// A `.far` beacon still counts when iOS puts it closer than this.
    static let farMaxAccuracyMeters = 8.0
    /// You've left a study area after this long with no close reading of its beacon.
    static let lostAfterSeconds = 15.0
    /// Ranging reports every second, even with nothing in range. Quiet this long means iOS stopped ranging
    /// (in the background, say), so a missing beacon proves nothing.
    static let rangingSilenceSeconds = 5.0

    static func isClose(_ proximity: BeaconProximity, accuracy: Double) -> Bool {
        switch proximity {
        case .immediate, .near: true
        case .far: accuracy >= 0 && accuracy < farMaxAccuracyMeters
        case .unknown: false
        }
    }
}

/// A study area, by zone and area id.
struct AreaKey: Hashable, Codable, Sendable {
    let zoneID: String
    let areaID: String
}

/// When each study area's beacon was last close.
struct AreaPresence: Equatable, Sendable {
    let lastClose: [AreaKey: Date]
    /// When ranging last reported anything, an empty report included.
    let lastRanged: Date?

    init(lastClose: [AreaKey: Date] = [:], lastRanged: Date? = nil) {
        self.lastClose = lastClose
        self.lastRanged = lastRanged
    }

    func sighted(_ key: AreaKey, proximity: BeaconProximity, accuracy: Double, at now: Date) -> AreaPresence {
        let ranged = ranged(at: now)
        guard BeaconRules.isClose(proximity, accuracy: accuracy) else { return ranged }
        return AreaPresence(lastClose: lastClose.merging([key: now]) { max($0, $1) }, lastRanged: now)
    }

    /// Ranging reported, with or without beacons.
    func ranged(at now: Date) -> AreaPresence {
        AreaPresence(lastClose: lastClose, lastRanged: max(lastRanged ?? now, now))
    }

    func isRangingLive(at now: Date) -> Bool {
        lastRanged.map { now.timeIntervalSince($0) <= BeaconRules.rangingSilenceSeconds } ?? false
    }

    /// The study area in this zone you're in now (the most recently close one), if any.
    func current(in zoneID: String, at now: Date) -> String? {
        lastClose
            .filter { $0.key.zoneID == zoneID && now.timeIntervalSince($0.value) <= BeaconRules.lostAfterSeconds }
            .max { $0.value < $1.value }?
            .key.areaID
    }
}

/// Whether a zone locks the phone right now.
enum ZoneLock: Equatable, Sendable {
    /// In the zone; `areaID` is the study area, or nil for a whole-building zone.
    case locked(areaID: String?)
    case free
    /// Not enough to go on: keep whatever was true.
    case undecided
}

/// Where you are, for the screens.
enum PlaceStatus: Equatable, Sendable {
    case locating
    case inStudyArea(Zone, StudyArea)
    /// In a building whose study areas you aren't in (the lobby, the café).
    case inBuilding(Zone)
    /// In a zone that is a whole building.
    case inZone(Zone)
    case outside
}

/// How building and beacons combine.
enum ZoneRules {
    /// - Whole-building zone: inside locks, outside frees, unknown can't say.
    /// - Zone with study areas: a close study-area beacon locks, unless GPS is sure you're outside the building
    ///   (a beacon carried off, or broadcast from somewhere else). Indoors GPS is often too rough to prove you're
    ///   inside, so "not outside" is enough. No close beacon: free, like the lobby or café, but only while ranging
    ///   is reporting; if iOS stopped ranging, a missing beacon proves nothing and nothing changes.
    static func lock(zone: Zone, building: BuildingPresence.State, areaID: String?, rangingLive: Bool) -> ZoneLock {
        if zone.usesWholeBuilding {
            switch building {
            case .inside: return .locked(areaID: nil)
            case .outside: return .free
            case .unknown: return .undecided
            }
        }
        if building == .outside { return .free }
        if let area = zone.area(areaID) { return .locked(areaID: area.id) }
        return rangingLive ? .free : .undecided
    }

    static func place(zones: [Zone], buildings: [String: BuildingPresence.State],
                      areaIn: (String) -> String?) -> PlaceStatus {
        for zone in zones {
            let building = buildings[zone.id] ?? .unknown
            if building != .outside, let area = zone.area(areaIn(zone.id)) { return .inStudyArea(zone, area) }
        }
        if let zone = zones.first(where: { buildings[$0.id] == .inside }) {
            return zone.usesWholeBuilding ? .inZone(zone) : .inBuilding(zone)
        }
        return zones.contains { buildings[$0.id] == .outside } ? .outside : .locating
    }
}
