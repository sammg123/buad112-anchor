import Foundation

/// One stretch of walking from the motion chip: step distance and which way the phone faced.
struct WalkSegment: Equatable, Sendable {
    let time: Date
    let meters: Double
    /// Radians, in any fixed frame (only turns matter).
    let heading: Double
}

/// Walking, as a path: each stretch of steps laid along the way you turned. Only the net distance counts (how
/// far the path ends from where it began), so pacing back and forth adds nothing, and how the phone sits in a
/// pocket doesn't matter (turning the whole path doesn't change its length).
struct WalkEvidence: Equatable, Sendable {
    static let windowSeconds = 180.0

    let segments: [WalkSegment]

    init(segments: [WalkSegment] = []) {
        self.segments = segments
    }

    func adding(_ segment: WalkSegment) -> WalkEvidence {
        WalkEvidence(segments: (segments + [segment]).filter { segment.time.timeIntervalSince($0.time) <= Self.windowSeconds })
    }

    /// Net meters walked in the last 3 minutes.
    func netMeters(at now: Date) -> Double {
        let recent = segments.filter { now.timeIntervalSince($0.time) <= Self.windowSeconds }
        let east = recent.reduce(0) { $0 + $1.meters * sin($1.heading) }
        let north = recent.reduce(0) { $0 + $1.meters * cos($1.heading) }
        return (east * east + north * north).squareRoot()
    }
}

/// Leaving your own anchor takes two keys:
/// - GPS: your dot is past the line (its fuzz circle at least half outside your circle), for 3 readings and 10 s;
/// - walking: the motion chip shows you walked at least 60% of the radius away, in the last 3 minutes.
/// GPS drifting while you sit has no steps; shaking the phone has steps but doesn't move GPS. Cheating takes both.
enum AnchorExit {
    static let walkShareOfRadius = 0.6
    /// GPS well past the line (by the full margin) this long frees you even without steps, so a step counter that
    /// stops reporting can't trap anyone. Sitting-still drift that large and that steady is very unlikely.
    static let gpsOnlyEscapeSeconds = 90.0
    static let minWalkMeters = 10.0

    static func requiredWalkMeters(radius: Double) -> Double {
        max(radius * walkShareOfRadius, minWalkMeters)
    }

    /// The GPS key's check of one position: in while more than half the fuzz circle is inside, out otherwise.
    static func fit(center: GeoPoint, fuzz: Double, in zone: Zone) -> CircleFit {
        ZoneGeometry.insideShare(center: center, radius: max(fuzz, 1), in: zone.polygon) > ZoneGeometry.mostlyInsideShare
            ? .mostlyInside : .fullyOutside
    }

    /// `walkedOut` is nil without motion data: then GPS alone decides (with the stricter whole-circle rule).
    /// `strictlyOutsideFor`: how long GPS has had you past the line by the full margin, if it does.
    static func lock(building: BuildingPresence.State, walkedOut: Bool?, strictlyOutsideFor: TimeInterval? = nil) -> ZoneLock {
        switch building {
        case .inside: return .locked(areaID: nil)
        case .unknown: return .undecided
        case .outside:
            if walkedOut != false { return .free }
            return (strictlyOutsideFor ?? 0) >= gpsOnlyEscapeSeconds ? .free : .locked(areaID: nil)
        }
    }
}
