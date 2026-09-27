import SwiftUI

func rssiColor(_ rssi: Int) -> Color {
    if rssi >= 0 { return .gray }
    if rssi <= -80 { return .red }
    if rssi <= -65 { return .orange }
    if rssi <= -50 { return .yellow }
    return .green
}

struct SignalBar: View {
    let rssi: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(rssiColor(rssi))
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(width: 90, height: 8)
    }

    private var fraction: CGFloat {
        guard rssi < 0 else { return 0 }
        let clamped = min(max(rssi, -100), -30)
        return CGFloat(clamped + 100) / 70.0
    }
}

struct PacketRow: View {
    let packet: FindMyPacket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(packet.name ?? "Unnamed device")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Text(packet.lastSeen, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SignalBar(rssi: packet.rssi)
                Text("\(packet.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(rssiColor(packet.rssi))
                Spacer()
                Text("x\(packet.sightings)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(packet.peripheralID.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label(packet.statusHex, systemImage: "flag")
                Label(String(format: "0x%02X", packet.appleType), systemImage: "tag")
                if packet.appleType != ApplePacketParser.findMyType {
                    Text(packet.typeName)
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)

            Text(packet.manufacturerHex)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
