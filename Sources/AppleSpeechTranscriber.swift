import AVFoundation
import Foundation
import Speech

final class AppleSpeechTranscriber: NSObject, StreamingSpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)?
    var finalTranscriptHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var finalTranscript = ""
    private var isStopping = false

    init(localeIdentifier: String) {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        super.init()
    }

    func start() async throws {
        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw NSError(
                domain: "AppleSpeechTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "需要开启 Speech Recognition 权限。"]
            )
        }

        let microphoneGranted = await requestMicrophoneAccess()
        guard microphoneGranted else {
            throw NSError(
                domain: "AppleSpeechTranscriber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "需要开启麦克风权限。"]
            )
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(
                domain: "AppleSpeechTranscriber",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "当前语言的 Apple Speech 不可用。"]
            )
        }

        stopEngineAndTask(cancelTask: true)
        finalTranscript = ""
        isStopping = false

        let inputNode = audioEngine.inputNode
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.finalTranscript = result.bestTranscription.formattedString
                self.partialTranscriptHandler?(self.finalTranscript)

                if result.isFinal {
                    self.finalTranscriptHandler?(self.finalTranscript)
                    self.stopEngineAndTask(cancelTask: false)
                }
            }

            if let error, !self.isStopping {
                self.errorHandler?(error.localizedDescription)
                self.stopEngineAndTask(cancelTask: true)
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func appendAudio(_ data: Data) async throws {
        // Apple Speech owns its AVAudioEngine path and does not accept external chunks.
    }

    func stop() async throws -> String {
        isStopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        try await Task.sleep(nanoseconds: 500_000_000)
        finalTranscriptHandler?(finalTranscript)
        return finalTranscript
    }

    func cancel() {
        isStopping = true
        stopEngineAndTask(cancelTask: true)
    }

    private func stopEngineAndTask(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
