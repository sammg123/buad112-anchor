import CoreBluetooth
import CoreLocation
import Observation

/// Beacon mode: makes this iPhone broadcast a study area's beacon, so a spare phone can stand in for real beacons
/// in a demo. iOS only lets an app broadcast while it is open, so it stops when its screen closes.
@MainActor
@Observable
final class BeaconBroadcaster: NSObject, CBPeripheralManagerDelegate {
    enum State: Equatable {
        case off, starting, broadcasting, bluetoothOff, notAllowed, unsupported, failed
    }

    private(set) var state: State = .off
    @ObservationIgnored private var manager: CBPeripheralManager?
    @ObservationIgnored private var beacon: BeaconID?

    func start(_ beacon: BeaconID) {
        self.beacon = beacon
        state = .starting
        if let manager {
            advertise(with: manager)
        } else {
            // Creating the manager is what asks for Bluetooth permission.
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
    }

    func stop() {
        manager?.stopAdvertising()
        beacon = nil
        state = .off
    }

    private func advertise(with manager: CBPeripheralManager) {
        guard let beacon else { return }
        switch manager.state {
        case .poweredOn:
            let region = CLBeaconRegion(uuid: beacon.uuid, major: beacon.major, minor: beacon.minor,
                                        identifier: "anchor-test-beacon")
            manager.stopAdvertising()
            manager.startAdvertising(region.peripheralData(withMeasuredPower: nil) as? [String: Any])
        case .poweredOff: state = .bluetoothOff
        case .unauthorized: state = .notAllowed
        case .unsupported: state = .unsupported
        default: state = .starting
        }
    }

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            guard let manager, beacon != nil else { return }
            advertise(with: manager)
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let failed = error != nil
        MainActor.assumeIsolated {
            guard beacon != nil else { return }
            state = failed ? .failed : .broadcasting
        }
    }
}
