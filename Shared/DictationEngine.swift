import Foundation
import AVFoundation
import Speech

final class DictationEngine {
    enum EngineError: Error {
        case recognizerUnavailable
        case recordingFailed
    }

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRecording = false

    var onTranscript: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

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

    static var hasAuthorization: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func start() throws {
        guard !isRecording else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw EngineError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw EngineError.recordingFailed }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDeviceOnly
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        self.request = request

        task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onTranscript?(result.bestTranscription.formattedString, result.isFinal)
                if result.isFinal { self.stop() }
            }
            if let error {
                let nsError = error as NSError
                if nsError.code != 216 && nsError.code != 203 {
                    self.onError?(error)
                }
            }
        }

        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stop() {
        guard isRecording || request != nil else { return }
        isRecording = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
