import SwiftUI
import UIKit

struct ScannerView: View {
    @StateObject private var scanner = BluetoothScanner()
    @State private var exportItem: ExportItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBanner
                controls
                filters
                Divider()
                deviceList
            }
            .navigationTitle("FindMy Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportItem = CSVExporter.export(scanner.filtered)
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(scanner.devices.isEmpty)
                }
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.bold())
                Text("BLE \(scanner.totalAdvertisements) · connectable \(scanner.connectableAdvertisements) · candidates \(scanner.candidateCount) · confirmed \(scanner.confirmedCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let error = scanner.bluetoothError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("iOS hides Apple manufacturer data; Find My devices are confirmed by probing their GATT services.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if scanner.state == .unauthorized {
                Button("Settings") { openSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(statusColor.opacity(0.12))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                scanner.togglePause()
            } label: {
                Label(scanner.isPaused ? "Resume" : "Pause",
                      systemImage: scanner.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanner.state != .poweredOn)

            Button(role: .destructive) {
                scanner.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(scanner.devices.isEmpty)

            Spacer()

            Text("\(scanner.filtered.count)/\(scanner.devices.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by identifier, name, service, category…", text: $scanner.filterText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !scanner.filterText.isEmpty {
                    Button {
                        scanner.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Min RSSI")
                    .font(.footnote)
                Slider(value: $scanner.minRSSI, in: -100 ... 0, step: 1)
                Text("\(Int(scanner.minRSSI)) dBm")
                    .font(.caption.monospacedDigit())
                    .frame(width: 64, alignment: .trailing)
            }

            Toggle("Show all BLE devices (not just Find My)", isOn: $scanner.showAllDevices)
                .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var deviceList: some View {
        Group {
            if scanner.filtered.isEmpty {
                ContentUnavailableView {
                    Label(scanner.devices.isEmpty ? "Scanning for BLE devices…" : "No matching devices",
                          systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text(scanner.devices.isEmpty
                         ? "Move near an AirTag or Find My accessory. Candidates are connected to and probed automatically; enable \"Show all BLE devices\" to see everything."
                         : "Adjust the filters above.")
                }
            } else {
                List(scanner.filtered) { device in
                    NavigationLink {
                        PacketDetailView(device: device)
                    } label: {
                        DeviceRow(device: device)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusIcon: String {
        switch scanner.state {
        case .poweredOn: return scanner.isPaused ? "pause.circle.fill" : "dot.radiowaves.left.and.right"
        case .poweredOff: return "bolt.horizontal.circle.fill"
        case .unauthorized: return "lock.circle.fill"
        case .unsupported: return "xmark.circle.fill"
        default: return "hourglass.circle.fill"
        }
    }

    private var statusColor: Color {
        switch scanner.state {
        case .poweredOn: return scanner.isPaused ? .orange : .green
        case .poweredOff, .unauthorized, .unsupported: return .red
        default: return .secondary
        }
    }

    private var statusTitle: String {
        switch scanner.state {
        case .poweredOn: return scanner.isPaused ? "Paused" : "Scanning"
        case .poweredOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth not authorized"
        case .unsupported: return "Bluetooth LE unsupported"
        case .resetting: return "Bluetooth resetting"
        default: return "Waiting for Bluetooth…"
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
