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
                packetList
            }
            .navigationTitle("FindMy Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportItem = CSVExporter.export(scanner.filtered)
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(scanner.packets.isEmpty)
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
                Text("BLE \(scanner.totalAdvertisements) · Apple \(scanner.appleAdvertisements) · 0x12 \(scanner.findMyAdvertisements)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let error = scanner.bluetoothError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("iOS hides hardware MAC addresses; the identifier below is app-scoped.")
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
            .disabled(scanner.packets.isEmpty)

            Spacer()

            Text("\(scanner.filtered.count)/\(scanner.packets.count)")
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
                TextField("Filter by identifier, payload, status…", text: $scanner.filterText)
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

            Toggle("Show all Apple BLE types (not just 0x12)", isOn: $scanner.showAllApple)
                .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var packetList: some View {
        Group {
            if scanner.filtered.isEmpty {
                ContentUnavailableView {
                    Label(scanner.packets.isEmpty ? "Scanning for Find My packets…" : "No matching packets",
                          systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text(scanner.packets.isEmpty
                         ? "Move near an AirTag or Find My accessory. Apple type 0x12 advertisements will appear here."
                         : "Adjust the filters above.")
                }
            } else {
                List(scanner.filtered) { packet in
                    NavigationLink {
                        PacketDetailView(packet: packet)
                    } label: {
                        PacketRow(packet: packet)
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
