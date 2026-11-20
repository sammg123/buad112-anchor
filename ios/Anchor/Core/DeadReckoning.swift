import Foundation

/// Where you are relative to the anchor, from your own steps: each stretch of walking is added in the direction
/// you were heading, so walking back cancels walking out and pacing never adds up. Heading 0 is the way you first
/// walked off ("north" in this frame) and grows clockwise; it only has to be consistent, never true north.
struct DeadReckoning: Codable, Equatable, Sendable {
    let east: Double
    let north: Double
    /// Total distance walked, out and back included.
    let walkedMeters: Double

    static let origin = DeadReckoning(east: 0, north: 0, walkedMeters: 0)

    var distance: Double { (east * east + north * north).squareRoot() }

    func walking(_ meters: Double, heading radians: Double) -> DeadReckoning {
        guard meters > 0, meters.isFinite, radians.isFinite else { return self }
        return DeadReckoning(east: east + meters * sin(radians), north: north + meters * cos(radians),
                             walkedMeters: walkedMeters + meters)
    }

    func isOutside(radius: Double) -> Bool { distance > radius }
}

/// Turning, measured from the gyroscope as rotation around gravity, so it reads the same whether the phone lies
/// flat, stands in a pocket, or is held in a hand. No compass: magnets and steel indoors don't matter.
enum Turning {
    typealias Vector = (x: Double, y: Double, z: Double)

    /// Clockwise turning speed in radians per second.
    static func yawRate(rotation r: Vector, gravity g: Vector) -> Double {
        let length = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
        guard length > 0.1 else { return 0 }
        return (r.x * g.x + r.y * g.y + r.z * g.z) / length
    }

    /// The average of headings, taking the wrap around a full circle into account.
    static func circularMean(_ angles: [Double]) -> Double? {
        guard !angles.isEmpty else { return nil }
        let s = angles.reduce(0) { $0 + sin($1) }, c = angles.reduce(0) { $0 + cos($1) }
        guard abs(s) + abs(c) > 1e-9 else { return nil }
        return atan2(s, c)
    }
}
