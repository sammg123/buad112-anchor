import Foundation

/// One location reading, as Core Location gave it.
struct LocationReading: Equatable, Sendable {
    let point: GeoPoint
    /// `horizontalAccuracy` in meters; negative means iOS has no position.
    let accuracy: Double
    let time: Date
    /// iOS says the reading was simulated by software (a spoofing app or Xcode) or came from an accessory.
    let isSpoofed: Bool
}

/// What happens to a reading.
enum ReadingVerdict: Equatable, Sendable {
    case use
    case invalid
    case tooInaccurate
    case tooOld
    /// Faked: ignored, and the session counts it.
    case spoofed
}

/// The cleaned-up position.
struct LocationEstimate: Equatable, Sendable {
    let point: GeoPoint
    /// One standard deviation, in meters.
    let accuracy: Double
    let time: Date
}

/// GPS clean-up. Readings worse than 20 m, older than 5 s, invalid or faked are thrown out; the rest go through a
/// small Kalman filter (the standard one for GPS: the position's uncertainty grows at walking speed between
/// readings, and each reading pulls the estimate in proportion to how sharp it is). Unlike a plain average over a
/// window it doesn't trail a walking person, and sitting still it settles tighter than any single reading.
struct LocationFilter: Equatable, Sendable {
    static let maxAccuracyMeters = 20.0
    static let maxAgeSeconds = 5.0
    /// How fast the true position can drift between readings, in meters per second.
    static let processSpeed = 3.0

    let estimate: LocationEstimate?

    init(estimate: LocationEstimate? = nil) {
        self.estimate = estimate
    }

    static func verdict(for reading: LocationReading, at now: Date) -> ReadingVerdict {
        if reading.isSpoofed { return .spoofed }
        guard reading.accuracy >= 0, reading.accuracy.isFinite else { return .invalid }
        if reading.accuracy > maxAccuracyMeters { return .tooInaccurate }
        if now.timeIntervalSince(reading.time) > maxAgeSeconds { return .tooOld }
        return .use
    }

    /// Takes a reading that passed `verdict`; one older than the current estimate is ignored.
    func adding(_ reading: LocationReading) -> LocationFilter {
        let measurementVariance = max(reading.accuracy * reading.accuracy, 1)
        guard let estimate else {
            return LocationFilter(estimate: LocationEstimate(point: reading.point, accuracy: max(reading.accuracy, 1),
                                                             time: reading.time))
        }
        let dt = reading.time.timeIntervalSince(estimate.time)
        guard dt >= 0 else { return self }
        let predicted = estimate.accuracy * estimate.accuracy + dt * Self.processSpeed * Self.processSpeed
        let gain = predicted / (predicted + measurementVariance)
        let pull = ZoneGeometry.meters(reading.point, from: estimate.point)
        let point = ZoneGeometry.point(from: estimate.point, east: gain * pull.x, north: gain * pull.y)
        let variance = (1 - gain) * predicted
        return LocationFilter(estimate: LocationEstimate(point: point, accuracy: variance.squareRoot(), time: reading.time))
    }
}
