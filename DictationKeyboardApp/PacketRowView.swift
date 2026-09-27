import SwiftUI

func rssiColor(_ rssi: Int) -> Color {
    if rssi >= 0 { return .gray }
    if rssi <= -80 { return .red }
    if rssi <= -65 { return .orange }
    if rssi <= -50 { return .yellow }
    return .green
}

func categoryColor(_ category: DeviceCategory) -> Color {
    switch category {
    case .confirmedAirTag, .confirmedFindMy: return .green
    case .findMyCandidate: return .orange
    case .apple: return .blue
    case .other: return .secondary
    }
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

struct DeviceRow: View {
    let device: BLEDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(device.name ?? device.category.rawValue)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Text(device.lastSeen, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SignalBar(rssi: device.rssi)
                Text("\(device.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(rssiColor(device.rssi))
                Spacer()
                Text("x\(device.sightings)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(device.peripheralID.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(device.category.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(categoryColor(device.category))
                if device.isConnectable {
                    Label("connectable", systemImage: "link")
                }
                if !device.serviceUUIDs.isEmpty {
                    Label("\(device.serviceUUIDs.count) svc", systemImage: "square.stack.3d.up")
                }
                if device.manufacturerData != nil {
                    Label("mfg data", systemImage: "shippingbox")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(device.advertisedSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
