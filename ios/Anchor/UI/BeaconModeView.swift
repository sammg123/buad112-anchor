import SwiftUI

/// Beacon mode: this iPhone broadcasts a study area's beacon so a spare phone can stand in for a real beacon.
/// iOS only lets an app broadcast while it's open, so it stops when you leave this screen.
struct BeaconModeView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?

    var body: some View {
        let broadcaster = model.broadcaster
        List {
            Section {
                ForEach(areas, id: \.key) { item in
                    Button {
                        selected = item.key
                        broadcaster.start(item.area.beacon)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.area.name).foregroundStyle(Palette.ink)
                                Text("\(item.zone.name) · major \(item.area.beacon.major), minor \(item.area.beacon.minor)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected == item.key { Image(systemName: "checkmark").foregroundStyle(Palette.blue) }
                        }
                    }
                    .accessibilityAddTraits(selected == item.key ? .isSelected : [])
                }
            } header: {
                Text("Broadcast as")
            } footer: {
                Text("Put this phone in the study area and walk in with the phone running Anchor. It only broadcasts while this screen is open and the phone is unlocked.")
            }
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText(broadcaster.state))
                        .foregroundStyle(broadcaster.state == .broadcasting ? Palette.away : .secondary)
                }
                if broadcaster.state == .broadcasting {
                    Button("Stop broadcasting", role: .destructive) {
                        broadcaster.stop()
                        selected = nil
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Beacon mode")
        .onDisappear { broadcaster.stop() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var areas: [(key: String, zone: Zone, area: StudyArea)] {
        model.tracker.zones.flatMap { zone in zone.studyAreas.map { ("\(zone.id)/\($0.id)", zone, $0) } }
    }

    private func statusText(_ state: BeaconBroadcaster.State) -> String {
        switch state {
        case .off: "Off"
        case .starting: "Starting…"
        case .broadcasting: "Broadcasting"
        case .bluetoothOff: "Bluetooth is off"
        case .notAllowed: "Bluetooth not allowed for Anchor"
        case .unsupported: "Not supported here"
        case .failed: "Couldn't start"
        }
    }
}
