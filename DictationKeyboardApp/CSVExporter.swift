import Foundation

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum CSVExporter {
    static func export(_ devices: [BLEDevice]) -> ExportItem? {
        let iso = ISO8601DateFormatter()

        var lines = [
            "first_seen,last_seen,identifier,category,name,rssi,connectable,confirmed_service,services,manufacturer_data,apple_type,status_byte,sightings"
        ]

        for device in devices.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            let fields = [
                iso.string(from: device.firstSeen),
                iso.string(from: device.lastSeen),
                device.peripheralID.uuidString,
                device.category.rawValue,
                device.name ?? "",
                "\(device.rssi)",
                device.isConnectable ? "yes" : "no",
                device.confirmedService ?? "",
                device.serviceUUIDs.joined(separator: " "),
                device.manufacturerHex,
                device.appleType.map { String(format: "0x%02X", $0) } ?? "",
                device.statusHex,
                "\(device.sightings)"
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
