import SwiftUI
import Charts

struct PacketDetailView: View {
    let device: BLEDevice

    var body: some View {
        List {
            Section("Identity") {
                row("Name", device.name ?? "—")
                row("Category", device.category.rawValue)
                if let service = device.confirmedService {
                    row("Confirmed via", service)
                }
                row("Identifier", device.peripheralID.uuidString)
                row("Connectable", device.isConnectable ? "Yes" : "No")
                row("First seen", device.firstSeen.formatted(date: .abbreviated, time: .standard))
                row("Last seen", device.lastSeen.formatted(date: .abbreviated, time: .standard))
                row("Sightings", "\(device.sightings)")
                row("Last RSSI", "\(device.rssi) dBm")
            }

            Section("Signal history") {
                if device.history.count >= 2 {
                    Chart(device.history) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("RSSI", sample.rssi)
                        )
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Time", sample.date),
                            y: .value("RSSI", sample.rssi)
                        )
                        .foregroundStyle(rssiColor(device.rssi).opacity(0.15))
                    }
                    .chartYScale(domain: -100 ... -30)
                    .frame(height: 160)
                } else {
                    Text("Collecting samples…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Advertisement") {
                row("Advertised services", device.servicesLabel)
                row("Service data", device.hasServiceData ? "present" : "—")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manufacturer data")
                        .foregroundStyle(.secondary)
                    Text(device.manufacturerHex)
                        .font(.caption.monospaced())
                }
                .font(.footnote)
                if device.appleType != nil {
                    row("Apple type", String(format: "0x%02X", device.appleType!))
                    row("Status byte", "\(device.statusHex) (0b\(device.statusBits))")
                    row("Public key (22 bytes)", device.publicKeyHex)
                }
            }

            Section {
                Text("iOS strips Apple's Find My manufacturer data (0x004C / 0x12) from advertisements, so AirTags and Find My accessories are confirmed by connecting and probing Apple's Find My GATT services instead. Only public data is shown; the encrypted location payload is never touched.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}
