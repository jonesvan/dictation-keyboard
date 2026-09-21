import UIKit

final class KeyboardViewController: UIInputViewController {

    private let dictation = DictationEngine()
    private let statusLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)

    private var committedText = ""
    private var errorActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        dictation.onTranscript = { [weak self] text, isFinal in
            self?.applyTranscript(text, isFinal: isFinal)
        }
        dictation.onError = { [weak self] error in
            self?.showError("Dictation error: \(error.localizedDescription)")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateMicState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dictation.stop()
        finishDictation()
    }

    private func setupViews() {
        view.backgroundColor = .secondarySystemBackground

        statusLabel.text = "Tap the mic and start speaking"
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 3
        statusLabel.adjustsFontForContentSizeCategory = true

        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold),
            forImageIn: .normal
        )
        micButton.tintColor = .systemBlue
        micButton.addTarget(self, action: #selector(toggleDictation), for: .touchUpInside)

        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 22, weight: .regular),
            forImageIn: .normal
        )
        nextKeyboardButton.tintColor = .secondaryLabel
        nextKeyboardButton.addTarget(self, action: #selector(advanceToNextInputMode), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [nextKeyboardButton, micButton])
        buttons.axis = .horizontal
        buttons.alignment = .center
        buttons.distribution = .equalCentering

        let stack = UIStackView(arrangedSubviews: [statusLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 220),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44),
            micButton.widthAnchor.constraint(equalToConstant: 56)
        ])
    }

    @objc private func toggleDictation() {
        if micButton.tintColor == .systemRed {
            dictation.stop()
            finishDictation()
            return
        }

        errorActive = false

        guard hasFullAccess else {
            showError("Turn on Allow Full Access for koyō in Settings → General → Keyboard → Keyboards")
            return
        }

        guard DictationEngine.hasAuthorization else {
            showError("Open koyō and allow Microphone and Speech Recognition access")
            return
        }

        committedText = ""
        statusLabel.text = "Listening…"
        micButton.tintColor = .systemRed
        do {
            try dictation.start()
        } catch {
            dictation.stop()
            showError("Could not start: \(error.localizedDescription)")
        }
    }

    private func applyTranscript(_ text: String, isFinal: Bool) {
        let proxy = textDocumentProxy
        if !committedText.isEmpty {
            for _ in 0..<committedText.count {
                proxy.deleteBackward()
            }
        }
        proxy.insertText(text)
        committedText = text
        statusLabel.text = text.isEmpty ? "Listening…" : text
        if isFinal { finishDictation() }
    }

    private func showError(_ message: String) {
        errorActive = true
        micButton.tintColor = .systemBlue
        statusLabel.text = message
    }

    private func finishDictation() {
        committedText = ""
        micButton.tintColor = .systemBlue
        updateMicState()
    }

    private func updateMicState() {
        if errorActive { return }
        if statusLabel.text == "Listening…" || micButton.tintColor == .systemRed { return }
        statusLabel.text = "Tap the mic and start speaking"
    }
}
