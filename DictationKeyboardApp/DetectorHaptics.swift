import Combine
import UIKit

/// Drives metal-detector style feedback: haptic taps that get faster and
/// stronger as the target's signal (proximity) improves.
final class DetectorHaptics: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                generator?.prepare()
                schedule()
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    private var generator: UIImpactFeedbackGenerator?
    private var timer: Timer?
    private var proximity: Double = 0

    func start() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        self.generator = generator
        if isEnabled { schedule() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generator = nil
    }

    /// `proximity` is 0 (far) to 1 (right on top of it).
    func update(proximity: Double) {
        self.proximity = min(max(proximity, 0), 1)
    }

    private func schedule() {
        timer?.invalidate()
        guard isEnabled, generator != nil else {
            timer = nil
            return
        }

        let interval = max(0.65 - 0.5 * proximity, 0.12)
        let intensity = 0.22 + 0.78 * proximity

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.generator?.impactOccurred(intensity: CGFloat(intensity))
            self.generator?.prepare()
            self.schedule()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
