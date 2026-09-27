import Foundation

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum CSVExporter {
    static func export(_ packets: [FindMyPacket]) -> ExportItem? {
        let iso = ISO8601DateFormatter()

        var lines = [
            "first_seen,last_seen,identifier,rssi,status_byte,apple_type,public_key,manufacturer_data,name,sightings"
        ]

        for packet in packets.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            let fields = [
                iso.string(from: packet.firstSeen),
                iso.string(from: packet.lastSeen),
                packet.peripheralID.uuidString,
                "\(packet.rssi)",
                packet.statusHex,
                String(format: "0x%02X", packet.appleType),
                packet.publicKeyHex,
                packet.manufacturerHex,
                packet.name ?? "",
                "\(packet.sightings)"
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        let filename = "findmy-scan-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return ExportItem(url: url)
        } catch {
            return nil
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
