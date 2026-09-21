import UIKit

final class KeyboardViewController: UIInputViewController {

    private let dictation = DictationEngine()
    private let logView = UITextView()
    private let micButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private var committedText = ""
    private var isListening = false
    private var startTask: Task<Void, Never>?
    private var startGeneration = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()

        dictation.onTranscript = { [weak self] text, isFinal in
            self?.applyTranscript(text, isFinal: isFinal)
        }
        dictation.onError = { [weak self] error in
            self?.log("recognition error: \(error.localizedDescription)")
        }
        dictation.onLog = { [weak self] message in
            self?.log(message)
        }

        log("keyboard loaded. fullAccess=\(hasFullAccess)")
        log("auth speech=\(DictationEngine.speechAuthorization) mic=\(DictationEngine.microphonePermission)")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        log("viewWillAppear. fullAccess=\(hasFullAccess)")
        updateMicState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        startTask?.cancel()
        startTask = nil
        dictation.stop()
        finishDictation()
    }

    private func setupViews() {
        view.backgroundColor = .secondarySystemBackground

        logView.isEditable = false
        logView.isSelectable = true
        logView.isScrollEnabled = true
        logView.showsVerticalScrollIndicator = true
        logView.alwaysBounceVertical = true
        logView.backgroundColor = .tertiarySystemBackground
        logView.textColor = .label
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        logView.layer.cornerRadius = 8
        logView.text = ""

        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold),
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

        clearButton.setImage(UIImage(systemName: "trash"), for: .normal)
        clearButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
            forImageIn: .normal
        )
        clearButton.tintColor = .secondaryLabel
        clearButton.addTarget(self, action: #selector(clearLog), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [nextKeyboardButton, micButton, clearButton])
        buttons.axis = .horizontal
        buttons.alignment = .center
        buttons.distribution = .equalCentering

        let stack = UIStackView(arrangedSubviews: [buttons, logView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(equalToConstant: 260),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44),
            micButton.widthAnchor.constraint(equalToConstant: 56),
            clearButton.widthAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func toggleDictation() {
        if isListening {
            log("user tapped mic -> stop")
            startTask?.cancel()
            startTask = nil
            dictation.stop()
            finishDictation()
            return
        }

        log("user tapped mic -> start. fullAccess=\(hasFullAccess)")

        guard hasFullAccess else {
            log("BLOCKED: Allow Full Access is off for koyō")
            return
        }

        guard DictationEngine.hasAuthorization else {
            log("BLOCKED: speech=\(DictationEngine.speechAuthorization) mic=\(DictationEngine.microphonePermission). Open koyō to grant access.")
            return
        }

        committedText = ""
        isListening = true
        micButton.tintColor = .systemRed
        startTask?.cancel()
        startGeneration += 1
        let generation = startGeneration
        startTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.startGeneration == generation { self.startTask = nil }
            }
            do {
                try await self.dictation.start()
            } catch is CancellationError {
                self.log("start cancelled")
            } catch {
                self.log("start threw: \(error.localizedDescription)")
                self.dictation.stop()
                self.finishDictation()
            }
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
        log("transcript\(isFinal ? " FINAL" : "") (\(text.count) chars): \(text)")
        if isFinal { finishDictation() }
    }

    @objc private func clearLog() {
        logView.text = ""
        log("log cleared")
    }

    private func log(_ message: String) {
        let line = "[\(timeFormatter.string(from: Date()))] \(message)\n"
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.logView.text += line
            let end = NSRange(location: (self.logView.text as NSString).length, length: 0)
            self.logView.scrollRangeToVisible(end)
        }
    }

    private func finishDictation() {
        committedText = ""
        isListening = false
        micButton.tintColor = .systemBlue
        updateMicState()
    }

    private func updateMicState() {
        micButton.tintColor = .systemBlue
    }
}
