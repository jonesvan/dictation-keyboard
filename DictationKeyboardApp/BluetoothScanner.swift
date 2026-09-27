import Foundation
import CoreBluetooth

final class BluetoothScanner: NSObject, ObservableObject {
    @Published private(set) var packets: [FindMyPacket] = []
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothError: String?

    @Published var isPaused = false
    @Published var filterText = ""
    @Published var minRSSI: Double = -100
    @Published var showAllApple = false

    private var central: CBCentralManager!
    private let maxHistory = 120

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    var filtered: [FindMyPacket] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        return packets
            .filter { showAllApple || $0.appleType == ApplePacketParser.findMyType }
            .filter { packet in
                guard !query.isEmpty else { return true }
                return packet.peripheralID.uuidString.localizedCaseInsensitiveContains(query)
                    || packet.manufacturerHex.localizedCaseInsensitiveContains(query)
                    || packet.statusHex.localizedCaseInsensitiveContains(query)
                    || (packet.name?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .filter { Double($0.rssi) >= minRSSI }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    func startScanning() {
        guard state == .poweredOn else { return }
        guard !central.isScanning else {
            isScanning = true
            return
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScanning() {
        if central.isScanning {
            central.stopScan()
        }
        isScanning = false
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            stopScanning()
        } else {
            startScanning()
        }
    }

    func clear() {
        packets.removeAll()
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        switch central.state {
        case .poweredOn:
            bluetoothError = nil
            if !isPaused { startScanning() }
        case .unauthorized:
            bluetoothError = "Bluetooth permission denied. Enable it in Settings."
            isScanning = false
        case .poweredOff:
            bluetoothError = "Bluetooth is turned off."
            isScanning = false
        case .unsupported:
            bluetoothError = "This device does not support Bluetooth LE."
            isScanning = false
        case .resetting:
            bluetoothError = "Bluetooth is resetting…"
            isScanning = false
        default:
            bluetoothError = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !isPaused else { return }
        guard let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        guard let parsed = ApplePacketParser.parse(manufacturer) else { return }

        let rssi = RSSI.intValue
        let now = Date()
        let key = "\(peripheral.identifier.uuidString)|\(manufacturer.compactHex)"
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let validRSSI = rssi != 127

        if let index = packets.firstIndex(where: { $0.id == key }) {
            packets[index].lastSeen = now
            if validRSSI { packets[index].rssi = rssi }
            packets[index].sightings += 1
            if validRSSI {
                packets[index].history.append(RSSISample(date: now, rssi: rssi))
                if packets[index].history.count > maxHistory {
                    packets[index].history.removeFirst(packets[index].history.count - maxHistory)
                }
            }
        } else {
            let packet = FindMyPacket(
                id: key,
                peripheralID: peripheral.identifier,
                manufacturerData: manufacturer,
                appleType: parsed.type,
                statusByte: parsed.status,
                publicKey: parsed.key,
                name: name,
                firstSeen: now,
                lastSeen: now,
                rssi: rssi,
                sightings: 1,
                history: validRSSI ? [RSSISample(date: now, rssi: rssi)] : []
            )
            packets.append(packet)
        }
    }
}
