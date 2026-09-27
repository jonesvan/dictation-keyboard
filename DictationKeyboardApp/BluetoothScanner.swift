import Foundation
import CoreBluetooth

final class BluetoothScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [BLEDevice] = []
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothError: String?

    @Published private(set) var totalAdvertisements = 0
    @Published private(set) var connectableAdvertisements = 0
    @Published private(set) var candidateCount = 0
    @Published private(set) var confirmedCount = 0

    @Published var isPaused = false
    @Published var filterText = ""
    @Published var minRSSI: Double = -100
    @Published var showAllDevices = false

    private var central: CBCentralManager!
    /// Retains peripherals so CoreBluetooth keeps delivering delegate callbacks.
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// Devices we are currently connecting to / have already probed.
    private var probing: Set<UUID> = []
    private var probed: Set<UUID> = []
    private let maxHistory = 120

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    var filtered: [BLEDevice] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        return devices
            .filter { showAllDevices || $0.isFindMyRelated }
            .filter { device in
                guard !query.isEmpty else { return true }
                return device.peripheralID.uuidString.localizedCaseInsensitiveContains(query)
                    || device.manufacturerHex.localizedCaseInsensitiveContains(query)
                    || device.servicesLabel.localizedCaseInsensitiveContains(query)
                    || (device.name?.localizedCaseInsensitiveContains(query) ?? false)
                    || device.category.rawValue.localizedCaseInsensitiveContains(query)
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
        for peripheral in peripherals.values where probing.contains(peripheral.identifier) {
            central.cancelPeripheralConnection(peripheral)
        }
        probing.removeAll()
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
        devices.removeAll()
        probed.removeAll()
        candidateCount = 0
        confirmedCount = 0
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
        totalAdvertisements += 1
        peripherals[peripheral.identifier] = peripheral

        let rssi = RSSI.intValue
        let now = Date()
        let id = peripheral.identifier.uuidString
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let hasServiceData = !(serviceData?.isEmpty ?? true)
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
        if isConnectable { connectableAdvertisements += 1 }

        let appleParsed = manufacturer.flatMap { ApplePacketParser.parse($0) }

        // Apple strips Find My manufacturer data on iOS, so the signature of an
        // AirTag / Find My accessory is: connectable, but nothing else advertised.
        let looksLikeFindMy = isConnectable
            && name == nil
            && manufacturer == nil
            && advertisedServices.isEmpty
            && !hasServiceData

        let category: DeviceCategory = looksLikeFindMy
            ? .findMyCandidate
            : (appleParsed != nil ? .apple : .other)
        let validRSSI = rssi != 127

        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].lastSeen = now
            devices[index].sightings += 1
            if validRSSI {
                devices[index].rssi = rssi
                devices[index].history.append(RSSISample(date: now, rssi: rssi))
                if devices[index].history.count > maxHistory {
                    devices[index].history.removeFirst(devices[index].history.count - maxHistory)
                }
            }
            if let name { devices[index].name = name }
            if let manufacturer { devices[index].manufacturerData = manufacturer }
            if !advertisedServices.isEmpty { devices[index].serviceUUIDs = advertisedServices }
            if hasServiceData { devices[index].hasServiceData = true }
            devices[index].isConnectable = devices[index].isConnectable || isConnectable
            if devices[index].category == .other || devices[index].category == .apple {
                devices[index].category = category
            }
            if let parsed = appleParsed {
                devices[index].appleType = parsed.type
                devices[index].statusByte = parsed.status
                devices[index].publicKey = parsed.key
            }
        } else {
            let device = BLEDevice(
                id: id,
                peripheralID: peripheral.identifier,
                name: name,
                rssi: rssi,
                firstSeen: now,
                lastSeen: now,
                sightings: 1,
                history: validRSSI ? [RSSISample(date: now, rssi: rssi)] : [],
                isConnectable: isConnectable,
                manufacturerData: manufacturer,
                serviceUUIDs: advertisedServices,
                hasServiceData: hasServiceData,
                category: category,
                confirmedService: nil,
                appleType: appleParsed?.type,
                statusByte: appleParsed?.status,
                publicKey: appleParsed?.key
            )
            devices.append(device)
            if category == .findMyCandidate { candidateCount += 1 }
        }

        maybeProbe(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(FindMyServices.probe)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        probing.remove(peripheral.identifier)
        probed.insert(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        probing.remove(peripheral.identifier)
        probed.insert(peripheral.identifier)
    }

    private func maybeProbe(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        guard state == .poweredOn else { return }
        guard !probing.contains(uuid), !probed.contains(uuid) else { return }
        guard let device = devices.first(where: { $0.id == uuid.uuidString }) else { return }
        guard device.category == .findMyCandidate else { return }

        probing.insert(uuid)
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }
}

extension BluetoothScanner: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        var matched: (DeviceCategory, String)?

        for service in peripheral.services ?? [] {
            if let kind = FindMyServices.match(service.uuid) {
                matched = kind
                if kind.0 == .confirmedAirTag { break }
            }
        }

        if let matched, let index = devices.firstIndex(where: { $0.id == peripheral.identifier.uuidString }) {
            devices[index].category = matched.0
            devices[index].confirmedService = matched.1
            confirmedCount += 1
        }

        probed.insert(peripheral.identifier)
        central.cancelPeripheralConnection(peripheral)
    }
}
