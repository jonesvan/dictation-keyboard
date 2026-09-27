import SwiftUI
import Charts

struct PacketDetailView: View {
    let packet: FindMyPacket

    var body: some View {
        List {
            Section("Identity") {
                row("Device name", packet.name ?? "—")
                row("Identifier", packet.peripheralID.uuidString)
                row("Advertisement type", "0x\(String(format: "%02X", packet.appleType)) · \(packet.typeName)")
                row("First seen", packet.firstSeen.formatted(date: .abbreviated, time: .standard))
                row("Last seen", packet.lastSeen.formatted(date: .abbreviated, time: .standard))
                row("Sightings", "\(packet.sightings)")
                row("Last RSSI", "\(packet.rssi) dBm")
            }

            Section("Signal history") {
                if packet.history.count >= 2 {
                    Chart(packet.history) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("RSSI", sample.rssi)
                        )
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Time", sample.date),
                            y: .value("RSSI", sample.rssi)
                        )
                        .foregroundStyle(rssiColor(packet.rssi).opacity(0.15))
                    }
                    .chartYScale(domain: -100 ... -30)
                    .frame(height: 160)
                } else {
                    Text("Collecting samples…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Packet") {
                row("Status byte", "\(packet.statusHex) (0b\(packet.statusBits))")
                row("Public key (22 bytes)", packet.publicKeyHex)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manufacturer data")
                        .foregroundStyle(.secondary)
                    Text(packet.manufacturerHex)
                        .font(.caption.monospaced())
                }
                .font(.footnote)
            }

            Section {
                Text("Only public advertisement fields are shown. This app never attempts to decrypt Apple's encrypted location payload; the rotating key can only be resolved inside Apple's Find My network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Packet")
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
