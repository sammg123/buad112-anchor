import Foundation

/// What the walk-out compass says about where your steps have taken you.
enum WalkOut {
    enum Status: Equatable, Sendable { case atAnchor, walkingOut, walkingBack, out }

    /// Closer than this to the anchor reads as "at your anchor".
    static let atAnchorMeters = 0.5
    /// Coming this much closer than a moment ago reads as walking back in.
    static let backTolerance = 0.3

    static func status(distance: Double, earlier: Double, radius: Double) -> Status {
        if distance >= radius { return .out }
        if distance < atAnchorMeters { return .atAnchor }
        return distance < earlier - backTolerance ? .walkingBack : .walkingOut
    }

    static func metersToGo(distance: Double, radius: Double) -> Int {
        max(0, Int((radius - distance).rounded(.up)))
    }

    /// Clockwise radians from the start frame's "north" to the direction straight out from the anchor.
    static func outwardAngle(_ position: DeadReckoning) -> Double {
        atan2(position.east, position.north)
    }

    /// The same angle, shifted by whole turns to sit nearest `reference` (the last one shown), so the arrow never
    /// spins a full circle when you cross behind the anchor.
    static func outwardAngle(_ position: DeadReckoning, near reference: Double) -> Double {
        let angle = outwardAngle(position)
        return angle + 2 * .pi * ((reference - angle) / (2 * .pi)).rounded()
    }
}
