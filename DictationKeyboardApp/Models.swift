import Foundation
import CoreBluetooth

struct RSSISample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let rssi: Int
}

enum DeviceCategory: String, Equatable {
    case confirmedAirTag = "AirTag (confirmed)"
    case confirmedFindMy = "Find My device (confirmed)"
    case findMyCandidate = "Find My candidate (probing…)"
    case apple = "Apple advertisement"
    case other = "BLE device"

    var isFindMyRelated: Bool {
        switch self {
        case .confirmedAirTag, .confirmedFindMy, .findMyCandidate: return true
        default: return false
        }
    }
}

/// Apple Find My GATT services used to confirm a candidate over a connection.
/// iOS strips Apple manufacturer data from advertisements, so the only reliable
/// way to identify AirTags / Find My accessories is to connect and probe these.
enum FindMyServices {
    static let airTagSound = CBUUID(string: "7DFC9000-7D1C-4951-86AA-8D9728F8D66C")
    static let findMyOffered = CBUUID(string: "FD43")
    static let findMyInfo = CBUUID(string: "87290102-3C51-43B1-A1A9-11B9DC38478B")

    static let probe: [CBUUID] = [airTagSound, findMyOffered, findMyInfo]

    static func match(_ uuid: CBUUID) -> (DeviceCategory, String)? {
        if uuid.data == airTagSound.data { return (.confirmedAirTag, "AirTag sound service") }
        if uuid.data == findMyOffered.data { return (.confirmedFindMy, "Find My offered service (FD43)") }
        if uuid.data == findMyInfo.data { return (.confirmedFindMy, "Find My info service") }
        return nil
    }
}

struct BLEDevice: Identifiable, Equatable {
    let id: String
    let peripheralID: UUID
    var name: String?
    var rssi: Int
    var firstSeen: Date
    var lastSeen: Date
    var sightings: Int
    var history: [RSSISample]
    var isConnectable: Bool
    var manufacturerData: Data?
    var serviceUUIDs: [String]
    var hasServiceData: Bool
    var category: DeviceCategory
    var confirmedService: String?
    var appleType: UInt8?
    var statusByte: UInt8?
    var publicKey: Data?

    /// Devices we consider Find My related: confirmed/candidate trackers, plus any
    /// Apple 0x12 advertisement (kept for the case where iOS does expose it).
    var isFindMyRelated: Bool {
        category.isFindMyRelated || appleType == ApplePacketParser.findMyType
    }

    var manufacturerHex: String { manufacturerData?.hexString ?? "—" }
    var publicKeyHex: String { publicKey?.hexString ?? "—" }
    var servicesLabel: String { serviceUUIDs.isEmpty ? "—" : serviceUUIDs.joined(separator: ", ") }

    var statusHex: String {
        guard let statusByte else { return "—" }
        return String(format: "%02X", statusByte)
    }

    var statusBits: String {
        guard let statusByte else { return "—" }
        return String(statusByte, radix: 2).leftPadded(to: 8, with: "0")
    }

    var advertisedSummary: String {
        if let manufacturerData { return manufacturerData.hexString }
        if !serviceUUIDs.isEmpty { return serviceUUIDs.joined(separator: " ") }
        if hasServiceData { return "service data" }
        return "—"
    }
}

enum ApplePacketParser {
    static let appleCompanyID: UInt16 = 0x004C
    static let findMyType: UInt8 = 0x12

    /// Parses a raw manufacturer-specific-data blob. Returns nil unless it is an
    /// Apple (0x004C) advertisement. Only public fields are read; the encrypted
    /// location payload is never touched.
    static func parse(_ data: Data) -> (type: UInt8, status: UInt8?, key: Data?)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == 0x4C, bytes[1] == 0x00 else { return nil }

        let type = bytes[2]
        var status: UInt8?
        var key: Data?

        if type == findMyType, bytes.count >= 5 {
            status = bytes[4]
            if bytes.count >= 27 {
                key = Data(bytes[5..<27])
            } else if bytes.count > 5 {
                key = Data(bytes[5...])
            }
        }

        return (type, status, key)
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var compactHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    func leftPadded(to length: Int, with pad: Character) -> String {
        count >= length ? self : String(repeating: String(pad), count: length - count) + self
    }
}
