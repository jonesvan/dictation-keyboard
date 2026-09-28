import SwiftUI
import UIKit

/// A live, "hot/cold" proximity detector for a single device. Reads RSSI from the
/// scanner each advertisement, visualises it as a radar gauge, and drives haptic
/// feedback that speeds up as the target gets closer.
struct DetectorView: View {
    @ObservedObject var scanner: BluetoothScanner
    let deviceID: String

    @StateObject private var haptics = DetectorHaptics()
    @State private var smoothedProximity: Double = 0
    @State private var trend: Double = 0

    private let radarSize: CGFloat = 260

    private var device: BLEDevice? {
        scanner.devices.first { $0.id == deviceID }
    }

    var body: some View {
        ZStack {
            background
            if let device {
                ScrollView {
                    VStack(spacing: 26) {
                        header(device)
                        radar(device)
                        readout(device)
                        stats(device)
                        sparkline(device)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Out of range",
                    systemImage: "location.slash",
                    description: Text("This device is no longer being seen. Move closer, or resume scanning.")
                )
            }
        }
        .navigationTitle("Locate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    haptics.isEnabled.toggle()
                } label: {
                    Image(systemName: haptics.isEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                }
                .accessibilityLabel(haptics.isEnabled ? "Disable haptics" : "Enable haptics")
            }
        }
        .onAppear {
            if let rssi = device?.rssi, rssi < 0 {
                smoothedProximity = proximity(for: rssi)
                haptics.update(proximity: smoothedProximity)
            }
            haptics.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            haptics.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: device?.rssi) { _, rssi in
            guard let rssi, rssi < 0 else { return }
            let target = proximity(for: rssi)
            let delta = target - smoothedProximity
            trend = delta
            smoothedProximity += delta * 0.25
            haptics.update(proximity: smoothedProximity)
        }
    }

    // MARK: - Sections

    private var background: some View {
        LinearGradient(
            colors: [proximityColor(smoothedProximity).opacity(0.18), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: smoothedProximity)
    }

    private func header(_ device: BLEDevice) -> some View {
        VStack(spacing: 6) {
            Text(device.name ?? device.category.rawValue)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(device.category.rawValue)
                .font(.caption.bold())
                .foregroundStyle(categoryColor(device.category))
            Text(device.peripheralID.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func radar(_ device: BLEDevice) -> some View {
        let tint = proximityColor(smoothedProximity)
        return ZStack {
            ForEach(Array(stride(from: 0.3, through: 1.0, by: 0.175)), id: \.self) { scale in
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    .frame(width: radarSize * CGFloat(scale), height: radarSize * CGFloat(scale))
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let period = max(0.55, 1.7 - smoothedProximity * 1.1)
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let baseRadius = size.width * 0.18
                    for i in 0..<2 {
                        let raw = (t + Double(i) * period / 2).truncatingRemainder(dividingBy: period)
                        let phase = raw / period
                        let radius = baseRadius + CGFloat(phase) * (size.width * 0.32)
                        let rect = CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.stroke(
                            Circle().path(in: rect),
                            with: .color(tint.opacity((1 - phase) * (0.35 + smoothedProximity * 0.4))),
                            lineWidth: 2
                        )
                    }
                }
            }
            .frame(width: radarSize, height: radarSize)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 14)
                .frame(width: radarSize, height: radarSize)

            Circle()
                .trim(from: 0, to: CGFloat(max(0.03, smoothedProximity)))
                .stroke(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: radarSize, height: radarSize)
                .animation(.easeInOut(duration: 0.4), value: smoothedProximity)

            Circle()
                .fill(tint.gradient)
                .frame(width: 118, height: 118)
                .shadow(color: tint.opacity(0.5), radius: 24)

            Image(systemName: symbol(for: device.category))
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: radarSize, height: radarSize)
    }

    private func readout(_ device: BLEDevice) -> some View {
        VStack(spacing: 4) {
            Text(proximityLevel)
                .font(.title2.bold())
                .foregroundStyle(proximityColor(smoothedProximity))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(device.rssi)")
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("dBm")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stats(_ device: BLEDevice) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Distance", value: distanceLabel(device.rssi), caption: "approximate", tint: .primary)
            StatCard(title: "Trend", value: trendWord, caption: trendCaption, tint: trendColor, symbol: trendSymbol)
            StatCard(title: "Sightings", value: "\(device.sightings)", caption: "adverts", tint: .secondary)
        }
    }

    private func sparkline(_ device: BLEDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Signal history")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            SignalSparkline(samples: Array(device.history.suffix(60)), tint: rssiColor(device.rssi))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Helpers

    private func proximity(for rssi: Int) -> Double {
        let clamped = min(max(Double(rssi), -100), -40)
        return (clamped + 100) / 60
    }

    private var proximityLevel: String {
        switch smoothedProximity {
        case ..<0.2: return "Very far"
        case ..<0.4: return "Far"
        case ..<0.6: return "Getting closer"
        case ..<0.8: return "Close"
        default: return "Right here"
        }
    }

    private var trendWord: String {
        if trend > 0.01 { return "Warmer" }
        if trend < -0.01 { return "Colder" }
        return "Steady"
    }

    private var trendCaption: String {
        if trend > 0.01 { return "signal rising" }
        if trend < -0.01 { return "signal falling" }
        return "hold position"
    }

    private var trendSymbol: String {
        if trend > 0.01 { return "arrow.up.right" }
        if trend < -0.01 { return "arrow.down.right" }
        return "equal"
    }

    private var trendColor: Color {
        if trend > 0.01 { return .green }
        if trend < -0.01 { return .red }
        return .secondary
    }

    private func proximityColor(_ proximity: Double) -> Color {
        switch proximity {
        case ..<0.25: return .red
        case ..<0.5: return .orange
        case ..<0.75: return .yellow
        default: return .green
        }
    }

    private func distanceLabel(_ rssi: Int) -> String {
        guard rssi < 0 else { return "—" }
        let meters = pow(10.0, (-59.0 - Double(rssi)) / 20.0)
        if meters < 0.5 { return "< 0.5 m" }
        if meters > 25 { return "> 25 m" }
        if meters < 10 { return String(format: "%.1f m", meters) }
        return String(format: "%.0f m", meters)
    }

    private func symbol(for category: DeviceCategory) -> String {
        switch category {
        case .confirmedAirTag: return "sensor.tag.radiowaves.forward.fill"
        case .confirmedFindMy: return "location.fill"
        case .findMyCandidate: return "questionmark"
        case .apple: return "apple.logo"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color
    var symbol: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.bold())
                }
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            .foregroundStyle(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SignalSparkline: View {
    let samples: [RSSISample]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                Path { path in
                    path.move(to: pts[0])
                    for point in pts.dropFirst() { path.addLine(to: point) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Text("Collecting samples…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 60)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let values = samples.map { Double($0.rssi) }
        let low = (values.min() ?? -100) - 3
        let high = (values.max() ?? -40) + 3
        let span = max(high - low, 1)
        return samples.enumerated().map { index, sample in
            let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
            let normalized = (Double(sample.rssi) - low) / span
            return CGPoint(x: x, y: size.height * (1 - CGFloat(normalized)))
        }
    }
}
