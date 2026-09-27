import Foundation

struct RSSISample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let rssi: Int
}

struct FindMyPacket: Identifiable, Equatable {
    let id: String
    let peripheralID: UUID
    let manufacturerData: Data
    let appleType: UInt8
    let statusByte: UInt8?
    let publicKey: Data?
    var name: String?
    var firstSeen: Date
    var lastSeen: Date
    var rssi: Int
    var sightings: Int
    var history: [RSSISample]

    var manufacturerHex: String { manufacturerData.hexString }
    var publicKeyHex: String { publicKey?.hexString ?? "—" }

    var statusHex: String {
        guard let statusByte else { return "—" }
        return String(format: "%02X", statusByte)
    }

    var statusBits: String {
        guard let statusByte else { return "—" }
        return String(statusByte, radix: 2).leftPadded(to: 8, with: "0")
    }

    var typeName: String {
        switch appleType {
        case 0x02: return "iBeacon"
        case 0x05: return "AirDrop"
        case 0x07: return "Proximity Pairing"
        case 0x09: return "AirPlay Target"
        case 0x0A: return "AirPlay Source"
        case 0x0C: return "Handoff"
        case 0x0F: return "Nearby Action"
        case 0x10: return "Nearby Info"
        case 0x12: return "Find My / Offline Finding"
        default: return String(format: "0x%02X", appleType)
        }
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
