import MapKit
import SwiftUI

/// The zones on a map, Lime-style: each building shaded red, your position with its accuracy circle on top.
struct ZoneLayers: MapContent {
    let zones: [Zone]
    var tint: Color = Palette.red
    let accuracy: (center: GeoPoint, radius: Double)?

    var body: some MapContent {
        ForEach(zones) { zone in
            MapPolygon(coordinates: zone.polygon.map(\.coordinate))
                .foregroundStyle(tint.opacity(0.2))
                .stroke(tint.opacity(0.85), lineWidth: 2)
            Annotation("", coordinate: zone.center.coordinate, anchor: .center) {
                ZoneLabel(name: zone.name, tint: tint)
            }
        }
        if let accuracy {
            MapCircle(center: accuracy.center.coordinate, radius: accuracy.radius)
                .foregroundStyle(Palette.blue.opacity(0.12))
                .stroke(Palette.blue.opacity(0.45), lineWidth: 1)
        }
        UserAnnotation()
    }
}

/// The red "no-phone zone" tag on the map.
struct ZoneLabel: View {
    let name: String
    var tint: Color = Palette.red

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "iphone.slash").font(.system(size: 10, weight: .bold))
            Text(name).font(.caption2.weight(.bold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint, in: Capsule())
        .accessibilityLabel("No-phone zone: \(name)")
    }
}

extension PlaceStatus {
    /// The status line.
    var line: String {
        switch self {
        case .locating: "Finding you…"
        case .inStudyArea(_, let area): "In study area: \(area.name)"
        case .inBuilding(let zone): "In \(zone.name), not a study area"
        case .inZone(let zone): "In \(zone.name)"
        case .outside: "Outside all zones"
        }
    }

    var isLocking: Bool {
        switch self {
        case .inStudyArea, .inZone: true
        case .locating, .inBuilding, .outside: false
        }
    }

    var zone: Zone? {
        switch self {
        case .inStudyArea(let zone, _), .inBuilding(let zone), .inZone(let zone): zone
        case .locating, .outside: nil
        }
    }

    var color: Color {
        switch self {
        case .inStudyArea, .inZone: Palette.red
        case .inBuilding: .orange
        case .outside: Palette.away
        case .locating: Palette.secondary
        }
    }
}

/// "● In study area: Study Room 2" as a glass capsule.
struct PlaceStatusLine: View {
    let place: PlaceStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(place.color).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(place.line)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCapsule()
        .animation(.smooth(duration: 0.25), value: place.line)
    }
}

/// Which zone and study area you're in, and how far it is to the nearest way out of the building.
struct PlaceCard: View {
    @Environment(AppModel.self) private var model
    let place: PlaceStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.isLocking ? "iphone.slash" : "iphone")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(place.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker).font(.caption.weight(.bold)).tracking(0.4).foregroundStyle(place.color).lineLimit(1)
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Text(detail).font(.footnote).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var kicker: String {
        switch place {
        case .inStudyArea: "NO-PHONE ZONE · STUDY AREA"
        case .inZone: "NO-PHONE ZONE"
        case .inBuilding: "NOT A STUDY AREA"
        case .outside: "OUTSIDE ALL ZONES"
        case .locating: "FINDING YOU"
        }
    }

    private var title: String {
        switch place {
        case .inStudyArea(let zone, let area): "\(area.name) · \(zone.name)"
        case .inZone(let zone), .inBuilding(let zone): zone.name
        case .outside: "Your phone is free here"
        case .locating: "Checking GPS and beacons…"
        }
    }

    private var detail: String {
        switch place {
        case .inStudyArea(let zone, _), .inZone(let zone):
            return exitLine(zone) ?? "Stop stays locked until you leave."
        case .inBuilding(let zone):
            return "Your phone is free here. Study areas: " + zone.studyAreas.map(\.name).joined(separator: ", ") + "."
        case .outside:
            return model.tracker.zones.isEmpty ? "No zones are set up." : "Walk into a study area to start."
        case .locating:
            guard let accuracy = model.tracker.lastUsed?.accuracy else { return "Waiting for a sharp GPS reading." }
            return "GPS within \(Format.meters(accuracy))."
        }
    }

    private func exitLine(_ zone: Zone) -> String? {
        model.metersToEdge(of: zone).map { "About \(Int($0.rounded(.up))) m to the nearest way out of \(zone.name)." }
    }
}
