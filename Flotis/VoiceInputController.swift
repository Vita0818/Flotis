import AppKit
import Foundation

protocol TranscriptClipboardWriting {
    func writeTranscript(_ text: String) -> Bool
}

struct SystemTranscriptClipboardWriter: TranscriptClipboardWriting {
    func writeTranscript(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

@MainActor
final class VoiceInputController {
    let appState: AppState

    private let providerStore: SpeechProviderStore
    private let runtimeFactory: TranscriptionRuntimeFactory
    private let secretStore: SecretStoring
    private let transcriptClipboardWriter: TranscriptClipboardWriting
    private var activeRuntime: TranscriptionRuntimePlan?
    private var realtimeAudioCapture: StreamingAudioCapture?
    private var audioRecorder: AudioRecorder?

    private var operationTask: Task<Void, Never>?
    private var realtimeAudioWriterTask: Task<Void, Error>?
    private var realtimeAudioContinuation: AsyncStream<Data>.Continuation?
    private var recordingLimitTask: Task<Void, Never>?

    private var sessionGeneration: UInt64 = 0
    private var isTransitioning = false

    init(
        appState: AppState,
        providerStore: SpeechProviderStore = .shared,
        runtimeFactory: TranscriptionRuntimeFactory = .shared,
        secretStore: SecretStoring = LocalSecretStore.shared,
        transcriptClipboardWriter: TranscriptClipboardWriting = SystemTranscriptClipboardWriter()
    ) {
        self.appState = appState
        self.providerStore = providerStore
        self.runtimeFactory = runtimeFactory
        self.secretStore = secretStore
        self.transcriptClipboardWriter = transcriptClipboardWriter
    }

    func toggleRecording() {
        switch appState.voiceState.hotkeyAction {
        case .start:
            guard !isTransitioning else { return }
            start()
        case .stop:
            guard !isTransitioning else { return }
            stopAndPrepareReview()
        case .cancel:
            cancel()
        case .copyAndReturn:
            copyReviewedTranscriptAndReset()
        case .none:
            return
        }
    }

    func cancel() {
        invalidateSessionAndCancelResources()
        appState.voiceState = .idle
        appState.transcriptPreview = ""
        appState.pasteError = nil
    }

    private func start() {
        let provider = providerStore.activeProvider
        if let validationError = runtimeValidationError(for: provider) {
            failWithoutActiveSession(validationError)
            return
        }

        do {
            let requiresAPIKey = try runtimeFactory.requiresAPIKey(for: provider)
            let resolvedAPIKey = requiresAPIKey ? apiKey(for: provider) : nil
            if requiresAPIKey, resolvedAPIKey == nil {
                throw TranscriptionAdapterRegistryError.missingAPIKey
            }
            let runtime = try runtimeFactory.makeRuntime(
                connection: provider,
                apiKey: resolvedAPIKey,
                fallbackLocaleIdentifier: appState.selectedSpeechLocale
            )
            let sessionID = beginSession(runtime: runtime)
            appState.transcriptPreview = ""
            appState.pasteError = nil

            switch runtime {
            case .ownedCapture(let transcriber, let automaticallyStopsOnFinal):
                startOwnedCapture(
                    transcriber: transcriber,
                    automaticallyStopsOnFinal: automaticallyStopsOnFinal,
                    sessionID: sessionID
                )
            case .pcmStream(let transcriber, let audio):
                startPCMStream(
                    transcriber: transcriber,
                    audio: audio,
                    sessionID: sessionID
                )
            case .recordedFile(let transcriber, let audio):
                startRecordedFile(
                    transcriber: transcriber,
                    audio: audio,
                    sessionID: sessionID
                )
            }
        } catch {
            failWithoutActiveSession(error.localizedDescription)
        }
    }

    private func startOwnedCapture(
        transcriber: StreamingSpeechTranscribing,
        automaticallyStopsOnFinal: Bool,
        sessionID: UInt64
    ) {
        isTransitioning = true
        appState.voiceState = .requestingPermission

        configureStreamingHandlers(
            for: transcriber,
            sessionID: sessionID,
            automaticallyStopOnFinal: automaticallyStopsOnFinal
        )

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transcriber.start()
                guard self.isCurrent(sessionID) else {
                    transcriber.cancel()
                    return
                }
                self.operationTask = nil
                self.appState.voiceState = .recording
                self.isTransitioning = false
            } catch is CancellationError {
                // A newer session or an explicit cancel owns the UI now.
            } catch {
                self.fail(error.localizedDescription, for: sessionID)
            }
        }
    }

    private func startPCMStream(
        transcriber: StreamingSpeechTranscribing,
        audio: PCMStreamRuntimeConfiguration,
        sessionID: UInt64
    ) {
        isTransitioning = true
        appState.voiceState = .connecting

        let capture = StreamingAudioCapture()
        configureStreamingHandlers(for: transcriber, sessionID: sessionID, automaticallyStopOnFinal: false)

        var streamContinuation: AsyncStream<Data>.Continuation?
        let audioStream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(audio.bufferCapacity)) {
            streamContinuation = $0
        }
        guard let continuation = streamContinuation else {
            fail(
                UIStrings.localized(
                    english: "Could not create the realtime audio queue.",
                    simplifiedChinese: "实时音频队列创建失败。"
                ),
                for: sessionID
            )
            return
        }

        capture.audioChunkHandler = { [weak self] data in
            switch continuation.yield(data) {
            case .enqueued:
                break
            case .dropped:
                continuation.finish()
                Task { @MainActor [weak self] in
                    self?.fail(
                        UIStrings.localized(
                            english: "The network could not keep up with the recording. Recording was stopped to prevent audio loss.",
                            simplifiedChinese: "网络发送速度跟不上录音，已停止以避免丢失音频。"
                        ),
                        for: sessionID
                    )
                }
            case .terminated:
                break
            @unknown default:
                continuation.finish()
            }
        }
        capture.errorHandler = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.fail(message, for: sessionID)
            }
        }

        realtimeAudioCapture = capture
        realtimeAudioContinuation = continuation

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transcriber.start()
                guard self.isCurrent(sessionID) else {
                    transcriber.cancel()
                    return
                }

                let writerTask = Task<Void, Error> { @MainActor [weak self] in
                    do {
                        for await data in audioStream {
                            try Task.checkCancellation()
                            try await transcriber.appendAudio(data)
                        }
                    } catch {
                        self?.fail(error.localizedDescription, for: sessionID)
                        throw error
                    }
                }
                self.realtimeAudioWriterTask = writerTask

                try await capture.start(
                    sampleRate: audio.sampleRate,
                    channels: audio.channels
                )
                guard self.isCurrent(sessionID) else {
                    capture.cancel()
                    continuation.finish()
                    writerTask.cancel()
                    transcriber.cancel()
                    return
                }

                self.operationTask = nil
                self.appState.voiceState = .streaming
                self.isTransitioning = false
            } catch is CancellationError {
                continuation.finish()
                transcriber.cancel()
            } catch {
                continuation.finish()
                self.fail(error.localizedDescription, for: sessionID)
            }
        }
    }

    private func startRecordedFile(
        transcriber: FileSpeechTranscribing,
        audio: RecordedFileRuntimeConfiguration,
        sessionID: UInt64
    ) {
        isTransitioning = true
        appState.voiceState = .requestingPermission
        let recorder = AudioRecorder()
        audioRecorder = recorder
        transcriber.partialTranscriptHandler = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(sessionID) else { return }
                self.appState.transcriptPreview = text
            }
        }

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await recorder.startRecording(
                    format: audio.format,
                    sampleRate: audio.sampleRate,
                    channels: audio.channels
                )
                guard self.isCurrent(sessionID) else {
                    recorder.cancelRecording()
                    return
                }

                self.operationTask = nil
                self.appState.voiceState = .recording
                self.isTransitioning = false

                if let maximumDuration = audio.maximumRecordingDurationSeconds {
                    let safeMaximum = max(
                        1,
                        maximumDuration - audio.stopLeadSeconds
                    )
                    self.startRecordingCountdown(
                        sessionID: sessionID,
                        maximumSeconds: safeMaximum
                    )
                } else {
                    self.appState.transcriptPreview = UIStrings.dictating
                }
            } catch is CancellationError {
                recorder.cancelRecording()
            } catch {
                self.fail(error.localizedDescription, for: sessionID)
            }
        }
    }

    private func stopAndPrepareReview() {
        guard let runtime = activeRuntime else {
            appState.voiceState = .idle
            return
        }
        let sessionID = sessionGeneration

        switch runtime {
        case .ownedCapture, .pcmStream:
            stopStreamingAndPrepareReview(sessionID: sessionID)
        case .recordedFile:
            stopRecordedFileAndPrepareReview(sessionID: sessionID)
        }
    }

    private func stopStreamingAndPrepareReview(sessionID: UInt64) {
        guard isCurrent(sessionID),
              let runtime = activeRuntime else { return }
        let transcriber: StreamingSpeechTranscribing
        switch runtime {
        case .ownedCapture(let owned, _), .pcmStream(let owned, _):
            transcriber = owned
        case .recordedFile:
            return
        }
        isTransitioning = true
        appState.voiceState = .stopping

        realtimeAudioCapture?.stop()
        realtimeAudioContinuation?.finish()
        let writerTask = realtimeAudioWriterTask

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let writerTask {
                    try await writerTask.value
                }
                guard self.isCurrent(sessionID) else { return }

                let text = try await transcriber.stop()
                guard self.isCurrent(sessionID) else { return }

                self.releaseCompletedSessionResources()
                self.prepareTranscriptForReview(text, sessionID: sessionID)
            } catch is CancellationError {
                // Explicit cancel or a newer session invalidated this stop.
            } catch {
                self.fail(error.localizedDescription, for: sessionID)
            }
        }
    }

    private func stopRecordedFileAndPrepareReview(sessionID: UInt64) {
        guard isCurrent(sessionID),
              let recorder = audioRecorder,
              let runtime = activeRuntime else {
            fail(
                UIStrings.localized(
                    english: "HTTP transcription did not start correctly.",
                    simplifiedChinese: "HTTP 转写未正确启动。"
                ),
                for: sessionID
            )
            return
        }
        let transcriber: FileSpeechTranscribing
        let audio: RecordedFileRuntimeConfiguration
        guard case .recordedFile(let plannedTranscriber, let plannedAudio) = runtime else {
            fail(
                UIStrings.localized(
                    english: "The file transcription runtime type does not match.",
                    simplifiedChinese: "文件转写 runtime 类型不匹配。"
                ),
                for: sessionID
            )
            return
        }
        transcriber = plannedTranscriber
        audio = plannedAudio

        isTransitioning = true
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        appState.voiceState = .transcribing
        appState.transcriptPreview = UIStrings.uploading

        guard let fileURL = recorder.stopRecording() else {
            fail(
                UIStrings.localized(
                    english: "Could not create the recording file.",
                    simplifiedChinese: "录音文件创建失败。"
                ),
                for: sessionID
            )
            return
        }
        audioRecorder = nil

        if let maximumUploadBytes = audio.maximumUploadBytes,
           let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumUploadBytes {
            try? FileManager.default.removeItem(at: fileURL)
            fail(
                UIStrings.recordingExceedsUploadLimit(
                    megabytes: maximumUploadBytes / 1_024 / 1_024
                ),
                for: sessionID
            )
            return
        }

        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: fileURL)
            }

            do {
                let text = try await transcriber.transcribeFile(fileURL)
                guard self.isCurrent(sessionID) else { return }

                self.releaseCompletedSessionResources()
                self.prepareTranscriptForReview(text, sessionID: sessionID)
            } catch is CancellationError {
                // Explicit cancel owns the state transition.
            } catch {
                self.fail(error.localizedDescription, for: sessionID)
            }
        }
    }

    private func startRecordingCountdown(sessionID: UInt64, maximumSeconds: Int) {
        recordingLimitTask?.cancel()
        recordingLimitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: maximumSeconds, through: 1, by: -1) {
                guard self.isCurrent(sessionID), self.appState.voiceState == .recording else { return }
                self.appState.transcriptPreview = UIStrings.recordingSecondsRemaining(remaining)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }

            guard self.isCurrent(sessionID), self.appState.voiceState == .recording else { return }
            self.recordingLimitTask = nil
            self.stopAndPrepareReview()
        }
    }

    private func prepareTranscriptForReview(_ rawText: String, sessionID: UInt64) {
        guard isCurrent(sessionID) else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            appState.transcriptPreview = ""
            fail(UIStrings.emptyTranscript, for: sessionID)
            return
        }

        appState.transcriptPreview = text
        appState.voiceState = .reviewing
        appState.pasteError = nil
        isTransitioning = false
    }

    private func copyReviewedTranscriptAndReset() {
        guard !isTransitioning, appState.voiceState == .reviewing else { return }
        let reviewedText = appState.transcriptPreview
        guard !reviewedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showShortStatus(UIStrings.emptyTranscript)
            return
        }

        guard transcriptClipboardWriter.writeTranscript(reviewedText) else {
            appState.pasteError = UIStrings.copyReviewedTranscriptFailed
            return
        }

        invalidateSessionAndCancelResources()
        appState.voiceState = .idle
        appState.transcriptPreview = ""
        appState.pasteError = nil
    }

    private func configureStreamingHandlers(
        for transcriber: StreamingSpeechTranscribing,
        sessionID: UInt64,
        automaticallyStopOnFinal: Bool
    ) {
        transcriber.partialTranscriptHandler = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(sessionID) else { return }
                self.appState.transcriptPreview = text
            }
        }
        transcriber.finalTranscriptHandler = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(sessionID) else { return }
                self.appState.transcriptPreview = text
                if automaticallyStopOnFinal,
                   self.appState.voiceState == .recording,
                   !self.isTransitioning {
                    self.stopStreamingAndPrepareReview(sessionID: sessionID)
                }
            }
        }
        transcriber.errorHandler = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.fail(message, for: sessionID)
            }
        }
    }

    private func apiKey(for provider: SpeechProviderConfig) -> String? {
        guard let reference = provider.apiKeyReference else { return nil }
        let key = (secretStore.load(for: reference) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func runtimeValidationError(for provider: SpeechProviderConfig) -> String? {
        provider.configurationValidationError()
    }

    private func beginSession(runtime: TranscriptionRuntimePlan) -> UInt64 {
        invalidateSessionAndCancelResources()
        activeRuntime = runtime
        isTransitioning = false
        return sessionGeneration
    }

    private func isCurrent(_ sessionID: UInt64) -> Bool {
        sessionGeneration == sessionID
    }

    private func invalidateSessionAndCancelResources() {
        sessionGeneration &+= 1
        operationTask?.cancel()
        realtimeAudioContinuation?.finish()
        realtimeAudioWriterTask?.cancel()
        recordingLimitTask?.cancel()
        activeRuntime?.cancel()
        realtimeAudioCapture?.cancel()
        audioRecorder?.cancelRecording()

        operationTask = nil
        realtimeAudioContinuation = nil
        realtimeAudioWriterTask = nil
        recordingLimitTask = nil
        activeRuntime = nil
        realtimeAudioCapture = nil
        audioRecorder = nil
        isTransitioning = false
    }

    private func releaseCompletedSessionResources() {
        recordingLimitTask?.cancel()
        realtimeAudioContinuation?.finish()

        operationTask = nil
        realtimeAudioContinuation = nil
        realtimeAudioWriterTask = nil
        recordingLimitTask = nil
        activeRuntime = nil
        realtimeAudioCapture = nil
        audioRecorder = nil
        isTransitioning = false
    }

    private func fail(_ message: String, for sessionID: UInt64) {
        guard isCurrent(sessionID) else { return }
        invalidateSessionAndCancelResources()
        appState.voiceState = .failed(message)
    }

    private func failWithoutActiveSession(_ message: String) {
        invalidateSessionAndCancelResources()
        appState.voiceState = .failed(message)
    }

    private func showShortStatus(_ message: String) {
        appState.pasteError = message
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            if self?.appState.pasteError == message {
                self?.appState.pasteError = nil
            }
        }
    }
}
