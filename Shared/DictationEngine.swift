import Foundation
import AVFoundation
import Speech

final class DictationEngine {
    enum EngineError: LocalizedError {
        case recognizerUnavailable
        case recordingFailed
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return "Speech recognition unavailable"
            case .recordingFailed: return "No microphone input"
            case .notAuthorized: return "Microphone or speech permission missing"
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRecording = false
    private var tapInstalled = false

    var onTranscript: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onLog: ((String) -> Void)?

    var onDeviceOnly: Bool {
        get { UserDefaults.standard.bool(forKey: "onDeviceOnly") }
        set { UserDefaults.standard.set(newValue, forKey: "onDeviceOnly") }
    }

    init(locale: Locale = Locale(identifier: Locale.current.identifier)) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            let speechGranted = status == .authorized
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async { completion(speechGranted && micGranted) }
            }
        }
    }

    static var speechAuthorization: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var microphonePermission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static var hasAuthorization: Bool {
        speechAuthorization == .authorized && microphonePermission == .granted
    }

    private func log(_ message: String) {
        onLog?(message)
    }

    func start() throws {
        guard !isRecording else {
            log("start ignored: already recording")
            return
        }
        guard DictationEngine.hasAuthorization else {
            log("start blocked: speech=\(DictationEngine.speechAuthorization) mic=\(DictationEngine.microphonePermission)")
            throw EngineError.notAuthorized
        }
        guard let speechRecognizer else {
            log("SFSpeechRecognizer init returned nil for locale \(Locale.current.identifier)")
            throw EngineError.recognizerUnavailable
        }

        log("recognizer locale=\(speechRecognizer.locale.identifier) available=\(speechRecognizer.isAvailable) onDeviceSupported=\(speechRecognizer.supportsOnDeviceRecognition)")

        guard speechRecognizer.isAvailable else {
            throw EngineError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDeviceOnly
        request.addsPunctuation = true
        self.request = request
        log("request ready. onDeviceOnly=\(onDeviceOnly)")

        task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.log("result final=\(result.isFinal) chars=\(text.count)")
                self.onTranscript?(text, result.isFinal)
                if result.isFinal { self.stop() }
            }
            if let error {
                let nsError = error as NSError
                if !self.isRecording {
                    self.log("ignoring task error after stop: code=\(nsError.code)")
                    return
                }
                self.log("task error domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                if nsError.code != 216 && nsError.code != 203 {
                    self.onError?(error)
                }
            }
        }

        let attempts: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions, String)] = [
            (.playAndRecord, .measurement, [.duckOthers, .defaultToSpeaker], "playAndRecord/measurement"),
            (.playAndRecord, .default, [.duckOthers, .defaultToSpeaker], "playAndRecord/default"),
            (.record, .measurement, [.duckOthers], "record/measurement"),
            (.record, .default, [.duckOthers], "record/default"),
            (.playAndRecord, .default, [], "playAndRecord/default/no-options")
        ]

        var lastError: Error = EngineError.recordingFailed
        for (category, mode, options, label) in attempts {
            do {
                try session.setCategory(category, mode: mode, options: options)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                log("session config \(label) failed: \(error.localizedDescription)")
                lastError = error
                continue
            }

            let inputs = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
            log("session \(label) active. input=\(inputs.isEmpty ? "none" : inputs)")

            let node = audioEngine.inputNode
            let outFormat = node.outputFormat(forBus: 0)
            let inFormat = node.inputFormat(forBus: 0)
            log("formats \(label) out(sr=\(Int(outFormat.sampleRate)) ch=\(outFormat.channelCount)) in(sr=\(Int(inFormat.sampleRate)) ch=\(inFormat.channelCount))")
            let format = (outFormat.channelCount > 0 && outFormat.sampleRate > 0) ? outFormat : inFormat
            guard format.channelCount > 0, format.sampleRate > 0 else {
                log("invalid input format on \(label)")
                lastError = EngineError.recordingFailed
                continue
            }

            if !tapInstalled {
                node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                    self?.request?.append(buffer)
                }
                tapInstalled = true
            }

            audioEngine.prepare()
            do {
                try audioEngine.start()
                isRecording = true
                log("audio engine started with \(label)")
                return
            } catch {
                log("audioEngine.start failed with \(label): \(error.localizedDescription)")
                lastError = error
                if tapInstalled {
                    node.removeTap(onBus: 0)
                    tapInstalled = false
                }
                if audioEngine.isRunning { audioEngine.stop() }
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }

        log("all audio configurations failed")
        stop()
        throw lastError
    }

    func stop() {
        guard isRecording || request != nil else { return }
        log("stop (recording=\(isRecording))")
        isRecording = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
