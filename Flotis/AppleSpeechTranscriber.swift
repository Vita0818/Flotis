import AVFoundation
import Foundation
import Speech

struct AppleTranscriptAccumulator {
    private struct Fragment {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
    }

    private static let overlapEpsilon: TimeInterval = 0.001
    private var fragments: [Fragment] = []
    private var untimedTranscript = ""

    var transcript: String {
        if fragments.isEmpty {
            return untimedTranscript
        }
        return fragments
            .sorted { $0.startTime < $1.startTime }
            .reduce("") { appendTranscriptSegment($1.text, to: $0) }
    }

    mutating func reset() {
        fragments.removeAll()
        untimedTranscript = ""
    }

    @discardableResult
    mutating func apply(
        _ value: String,
        startTime: TimeInterval?,
        endTime: TimeInterval?
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Apple can emit an empty final after a useful partial. An empty update is
            // not evidence that the already recognized speech should be discarded.
            return transcript
        }

        if let startTime,
           let endTime,
           startTime >= 0,
           endTime >= startTime {
            fragments.removeAll {
                $0.endTime > startTime + Self.overlapEpsilon
            }
            fragments.append(
                Fragment(
                    startTime: startTime,
                    endTime: endTime,
                    text: trimmed
                )
            )
            untimedTranscript = ""
            return transcript
        }

        let current = transcript
        fragments.removeAll()
        untimedTranscript = mergeUntimedHypothesis(trimmed, with: current)
        return untimedTranscript
    }

    private func mergeUntimedHypothesis(_ value: String, with current: String) -> String {
        guard !current.isEmpty else { return value }
        if value == current { return current }
        if value.hasPrefix(current) || current.hasPrefix(value) {
            return value
        }

        let maximumOverlap = min(current.count, value.count)
        if maximumOverlap > 0 {
            for overlapLength in stride(from: maximumOverlap, through: 1, by: -1) {
                let currentSuffix = current.suffix(overlapLength)
                let valuePrefix = value.prefix(overlapLength)
                if currentSuffix == valuePrefix {
                    return current + value.dropFirst(overlapLength)
                }
            }
        }
        return appendTranscriptSegment(value, to: current)
    }
}

private final class AppleRecognitionState: @unchecked Sendable {
    struct Status {
        let finalReceived: Bool
        let transcript: String
        let errorMessage: String?
    }

    private let lock = NSLock()
    private var generation: UUID?
    private var acceptingEvents = false
    private var transcriptAccumulator = AppleTranscriptAccumulator()
    private var finalReceived = false
    private var errorMessage: String?

    func reset(generation: UUID) {
        lock.lock()
        self.generation = generation
        acceptingEvents = true
        transcriptAccumulator.reset()
        finalReceived = false
        errorMessage = nil
        lock.unlock()
    }

    func applyTranscript(
        _ value: String,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        isFinal: Bool,
        generation: UUID
    ) -> Status? {
        lock.lock()
        guard self.generation == generation, acceptingEvents else {
            lock.unlock()
            return nil
        }
        let transcript = transcriptAccumulator.apply(
            value,
            startTime: startTime,
            endTime: endTime
        )
        if isFinal {
            finalReceived = true
        }
        let status = Status(
            finalReceived: finalReceived,
            transcript: transcript,
            errorMessage: errorMessage
        )
        lock.unlock()
        return status
    }

    func recordError(_ message: String, generation: UUID) -> Status? {
        lock.lock()
        guard self.generation == generation, acceptingEvents else {
            lock.unlock()
            return nil
        }
        if !finalReceived, errorMessage == nil {
            errorMessage = message
        }
        let status = Status(
            finalReceived: finalReceived,
            transcript: transcriptAccumulator.transcript,
            errorMessage: errorMessage
        )
        lock.unlock()
        return status
    }

    func status(generation: UUID) -> Status? {
        lock.lock()
        defer { lock.unlock() }
        guard self.generation == generation else { return nil }
        return Status(
            finalReceived: finalReceived,
            transcript: transcriptAccumulator.transcript,
            errorMessage: errorMessage
        )
    }

    func cancel(generation: UUID) {
        lock.lock()
        if self.generation == generation, errorMessage == nil {
            errorMessage = UIStrings.localized(
                english: "Apple Speech recognition was canceled.",
                simplifiedChinese: "Apple 语音识别已取消。"
            )
        }
        lock.unlock()
    }

    func stopAcceptingEvents(generation: UUID) {
        lock.lock()
        if self.generation == generation {
            acceptingEvents = false
        }
        lock.unlock()
    }
}

final class AppleSpeechTranscriber: NSObject, StreamingSpeechTranscribing {
    private let handlers = LockedTranscriptionHandlers()
    var partialTranscriptHandler: ((String) -> Void)? {
        get { handlers.partialHandler }
        set { handlers.partialHandler = newValue }
    }
    var finalTranscriptHandler: ((String) -> Void)? {
        get { handlers.finalHandler }
        set { handlers.finalHandler = newValue }
    }
    var errorHandler: ((String) -> Void)? {
        get { handlers.errorHandler }
        set { handlers.errorHandler = newValue }
    }

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let recognitionState = AppleRecognitionState()
    private let resourceLock = NSLock()
    private let captureOperationLock = NSRecursiveLock()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeGeneration: UUID?
    private var tapInstalled = false

    init(localeIdentifier: String) {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        super.init()
    }

    func start() async throws {
        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw makeError(
                code: 1,
                message: UIStrings.localized(
                    english: "Speech Recognition access is required.",
                    simplifiedChinese: "需要开启语音识别权限。"
                )
            )
        }

        let microphoneGranted = await requestMicrophoneAccess()
        guard microphoneGranted else {
            throw makeError(
                code: 2,
                message: UIStrings.localized(
                    english: "Microphone access is required.",
                    simplifiedChinese: "需要开启麦克风权限。"
                )
            )
        }
        try Task.checkCancellation()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw makeError(
                code: 3,
                message: UIStrings.localized(
                    english: "Apple Speech recognition is unavailable for the selected language.",
                    simplifiedChinese: "当前语言的 Apple 语音识别不可用。"
                )
            )
        }
        guard speechRecognizer.supportsOnDeviceRecognition else {
            throw makeError(
                code: 4,
                message: UIStrings.localized(
                    english: "The selected language does not support on-device Apple Speech recognition.",
                    simplifiedChinese: "当前语言不支持 Apple 设备端语音识别。"
                )
            )
        }

        cleanupCurrent(cancelTask: true)
        let generation = UUID()
        recognitionState.reset(generation: generation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw makeError(
                code: 5,
                message: UIStrings.localized(
                    english: "No microphone input format is currently available.",
                    simplifiedChinese: "当前没有可用的麦克风输入格式。"
                )
            )
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        resourceLock.lock()
        activeGeneration = generation
        recognitionRequest = request
        resourceLock.unlock()

        let task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let bestTranscription = result.bestTranscription
                let transcript = bestTranscription.formattedString
                let segments = bestTranscription.segments
                let startTime = segments.map(\.timestamp).min()
                let endTime = segments
                    .map { $0.timestamp + $0.duration }
                    .max()
                guard let status = self.recognitionState.applyTranscript(
                    transcript,
                    startTime: startTime,
                    endTime: endTime,
                    isFinal: result.isFinal,
                    generation: generation
                ) else { return }
                if !status.transcript.isEmpty {
                    self.handlers.partialHandler?(status.transcript)
                }
                if result.isFinal {
                    self.handlers.finalHandler?(status.transcript)
                    self.endAudioCapture(generation: generation)
                }
                if status.finalReceived {
                    return
                }
            }

            if let error {
                guard let status = self.recognitionState.recordError(
                    error.localizedDescription,
                    generation: generation
                ) else { return }
                if !status.finalReceived {
                    self.handlers.errorHandler?(error.localizedDescription)
                    self.cleanup(generation: generation, cancelTask: true)
                }
            }
        }

        resourceLock.lock()
        let taskIsCurrent = activeGeneration == generation
        if taskIsCurrent {
            recognitionTask = task
        }
        resourceLock.unlock()
        guard taskIsCurrent else {
            task.cancel()
            let message = recognitionState.status(generation: generation)?.errorMessage
                ?? UIStrings.localized(
                    english: "Starting Apple Speech recognition was canceled.",
                    simplifiedChinese: "Apple 语音识别启动已取消。"
                )
            throw makeError(code: 6, message: message)
        }

        captureOperationLock.lock()
        resourceLock.lock()
        guard activeGeneration == generation else {
            resourceLock.unlock()
            captureOperationLock.unlock()
            task.cancel()
            throw CancellationError()
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.resourceLock.lock()
            let request = self.activeGeneration == generation ? self.recognitionRequest : nil
            self.resourceLock.unlock()
            request?.append(buffer)
        }
        tapInstalled = true
        resourceLock.unlock()
        do {
            audioEngine.prepare()
            try audioEngine.start()
            captureOperationLock.unlock()
        } catch {
            captureOperationLock.unlock()
            cleanup(generation: generation, cancelTask: true)
            throw error
        }

        if let errorMessage = recognitionState.status(generation: generation)?.errorMessage {
            cleanup(generation: generation, cancelTask: true)
            throw makeError(code: 6, message: errorMessage)
        }
    }

    func appendAudio(_ data: Data) async throws {
        // Apple Speech owns its AVAudioEngine path and does not accept external chunks.
    }

    func stop() async throws -> String {
        guard let generation = currentGeneration() else {
            throw makeError(
                code: 7,
                message: UIStrings.localized(
                    english: "Apple Speech recognition has not started.",
                    simplifiedChinese: "Apple 语音识别尚未启动。"
                )
            )
        }
        endAudioCapture(generation: generation)

        do {
            let text = try await waitForRealtimeCondition(
                timeout: 3,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for the final Apple Speech result.",
                    simplifiedChinese: "Apple 语音识别最终结果超时。"
                )
            ) {
                guard let status = self.recognitionState.status(generation: generation) else {
                    throw CancellationError()
                }
                if let errorMessage = status.errorMessage {
                    throw self.makeError(code: 6, message: errorMessage)
                }
                return status.finalReceived ? status.transcript : nil
            }
            cleanup(generation: generation, cancelTask: false)
            handlers.finalHandler?(text)
            return text
        } catch {
            cleanup(generation: generation, cancelTask: true)
            throw error
        }
    }

    func cancel() {
        guard let generation = currentGeneration() else { return }
        recognitionState.cancel(generation: generation)
        cleanup(generation: generation, cancelTask: true)
    }

    private func endAudioCapture(generation: UUID) {
        captureOperationLock.lock()
        defer { captureOperationLock.unlock() }

        resourceLock.lock()
        guard activeGeneration == generation else {
            resourceLock.unlock()
            return
        }
        let shouldRemoveTap = tapInstalled
        tapInstalled = false
        let request = recognitionRequest
        resourceLock.unlock()

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if shouldRemoveTap {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
    }

    private func cleanup(generation: UUID, cancelTask: Bool) {
        captureOperationLock.lock()
        defer { captureOperationLock.unlock() }

        endAudioCapture(generation: generation)

        resourceLock.lock()
        guard activeGeneration == generation else {
            resourceLock.unlock()
            return
        }
        let task = recognitionTask
        recognitionTask = nil
        recognitionRequest = nil
        activeGeneration = nil
        resourceLock.unlock()

        recognitionState.stopAcceptingEvents(generation: generation)

        if cancelTask {
            task?.cancel()
        }
    }

    private func cleanupCurrent(cancelTask: Bool) {
        guard let generation = currentGeneration() else { return }
        cleanup(generation: generation, cancelTask: cancelTask)
    }

    private func currentGeneration() -> UUID? {
        resourceLock.lock()
        defer { resourceLock.unlock() }
        return activeGeneration
    }

    private func makeError(code: Int, message: String) -> NSError {
        NSError(
            domain: "AppleSpeechTranscriber",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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
