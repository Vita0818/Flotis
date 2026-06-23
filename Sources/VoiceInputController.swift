import Foundation

@MainActor
final class VoiceInputController {
    let appState: AppState

    private let providerStore: SpeechProviderStore
    private var activeStreamingTranscriber: StreamingSpeechTranscribing?
    private var realtimeAudioCapture: StreamingAudioCapture?
    private var audioRecorder: AudioRecorder?
    private var activeProvider: SpeechProviderConfig?
    private var isTransitioning = false

    init(appState: AppState, providerStore: SpeechProviderStore = .shared) {
        self.appState = appState
        self.providerStore = providerStore
    }

    func toggleRecording() {
        switch appState.voiceState {
        case .idle, .failed:
            guard !isTransitioning else { return }
            start()
        case .recording, .streaming:
            guard !isTransitioning else { return }
            stopAndInject()
        case .requestingPermission, .connecting, .stopping, .transcribing, .injecting:
            showShortStatus("语音输入正在处理中。")
        }
    }

    func cancel() {
        activeStreamingTranscriber?.cancel()
        realtimeAudioCapture?.cancel()
        audioRecorder?.cancelRecording()
        activeStreamingTranscriber = nil
        realtimeAudioCapture = nil
        audioRecorder = nil
        activeProvider = nil
        isTransitioning = false
        appState.voiceState = .idle
        appState.transcriptPreview = ""
    }

    private func start() {
        let provider = providerStore.activeProvider
        activeProvider = provider
        appState.transcriptPreview = ""

        switch provider.kind {
        case .appleSpeechLive:
            startAppleSpeech(provider: provider)
        case .openAIRealtimeTranscription:
            startRealtime(provider: provider)
        case .openAIHTTPTranscription:
            startHTTPRecording(provider: provider)
        }
    }

    private func startAppleSpeech(provider: SpeechProviderConfig) {
        isTransitioning = true
        appState.voiceState = .requestingPermission

        let localeIdentifier = provider.language?.isEmpty == false
            ? provider.language!
            : appState.selectedSpeechLocale
        let transcriber = AppleSpeechTranscriber(localeIdentifier: localeIdentifier)
        configureStreamingHandlers(for: transcriber)
        activeStreamingTranscriber = transcriber

        Task {
            do {
                try await transcriber.start()
                self.appState.voiceState = .recording
                self.isTransitioning = false
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func startRealtime(provider: SpeechProviderConfig) {
        guard let apiKey = apiKey(for: provider) else {
            fail("请先配置该 Realtime provider 的 API Key。")
            return
        }

        isTransitioning = true
        appState.voiceState = .connecting
        let transcriber = OpenAIRealtimeTranscriber(config: provider, apiKey: apiKey)
        let capture = StreamingAudioCapture()
        configureStreamingHandlers(for: transcriber)
        capture.audioChunkHandler = { [weak self] data in
            Task { @MainActor in
                await self?.appendRealtimeAudio(data)
            }
        }
        capture.errorHandler = { [weak self] message in
            Task { @MainActor in
                self?.fail(message)
            }
        }

        activeStreamingTranscriber = transcriber
        realtimeAudioCapture = capture

        Task {
            do {
                try await transcriber.start()
                try await capture.start(
                    sampleRate: provider.sampleRate ?? 24000,
                    channels: provider.channels ?? 1
                )
                self.appState.voiceState = .streaming
                self.isTransitioning = false
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func startHTTPRecording(provider: SpeechProviderConfig) {
        guard apiKey(for: provider) != nil else {
            fail("请先配置该 HTTP provider 的 API Key。")
            return
        }

        isTransitioning = true
        appState.voiceState = .requestingPermission
        let recorder = AudioRecorder()
        audioRecorder = recorder

        Task {
            do {
                try await recorder.startRecording()
                self.appState.voiceState = .recording
                self.appState.transcriptPreview = "正在听写…"
                self.isTransitioning = false
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func stopAndInject() {
        guard let provider = activeProvider else {
            appState.voiceState = .idle
            return
        }

        switch provider.kind {
        case .appleSpeechLive, .openAIRealtimeTranscription:
            stopStreamingAndInject()
        case .openAIHTTPTranscription:
            stopHTTPAndInject(provider: provider)
        }
    }

    private func stopStreamingAndInject() {
        guard let transcriber = activeStreamingTranscriber else { return }
        isTransitioning = true
        appState.voiceState = .stopping
        realtimeAudioCapture?.stop()

        Task {
            do {
                let text = try await transcriber.stop()
                self.activeStreamingTranscriber = nil
                self.realtimeAudioCapture = nil
                self.activeProvider = nil
                self.isTransitioning = false
                self.injectFinalTranscript(text)
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func stopHTTPAndInject(provider: SpeechProviderConfig) {
        guard let recorder = audioRecorder,
              let apiKey = apiKey(for: provider) else {
            fail("HTTP 转写未正确启动。")
            return
        }

        isTransitioning = true
        appState.voiceState = .transcribing
        appState.transcriptPreview = "上传中…"

        guard let fileURL = recorder.stopRecording() else {
            fail("录音文件创建失败。")
            return
        }
        audioRecorder = nil

        Task {
            defer {
                try? FileManager.default.removeItem(at: fileURL)
            }

            do {
                let transcriber = OpenAIHTTPTranscriber(apiKey: apiKey)
                let text = try await transcriber.transcribeFile(fileURL, config: provider)
                self.activeProvider = nil
                self.isTransitioning = false
                self.injectFinalTranscript(text)
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func appendRealtimeAudio(_ data: Data) async {
        guard case .streaming = appState.voiceState,
              let transcriber = activeStreamingTranscriber else { return }

        do {
            try await transcriber.appendAudio(data)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func injectFinalTranscript(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            appState.voiceState = .idle
            appState.transcriptPreview = ""
            return
        }

        appState.transcriptPreview = text
        appState.voiceState = .injecting

        ClipboardPasteInjector.shared.inject(text: text) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.appState.voiceState = .idle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.appState.voiceState == .idle {
                            self.appState.transcriptPreview = ""
                        }
                    }
                } else {
                    self.appState.voiceState = .failed("注入失败，可能没有权限。")
                }
                self.isTransitioning = false
            }
        }
    }

    private func configureStreamingHandlers(for transcriber: StreamingSpeechTranscribing) {
        transcriber.partialTranscriptHandler = { [weak self] text in
            DispatchQueue.main.async {
                self?.appState.transcriptPreview = text
            }
        }
        transcriber.finalTranscriptHandler = { [weak self] text in
            DispatchQueue.main.async {
                self?.appState.transcriptPreview = text
            }
        }
        transcriber.errorHandler = { [weak self] message in
            DispatchQueue.main.async {
                self?.fail(message)
            }
        }
    }

    private func apiKey(for provider: SpeechProviderConfig) -> String? {
        guard let reference = provider.apiKeyReference else { return nil }
        let key = KeychainSecretStore.shared.load(for: reference) ?? ""
        return key.isEmpty ? nil : key
    }

    private func fail(_ message: String) {
        activeStreamingTranscriber?.cancel()
        realtimeAudioCapture?.cancel()
        audioRecorder?.cancelRecording()
        activeStreamingTranscriber = nil
        realtimeAudioCapture = nil
        audioRecorder = nil
        activeProvider = nil
        isTransitioning = false
        appState.voiceState = .failed(message)
    }

    private func showShortStatus(_ message: String) {
        appState.pasteError = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.appState.pasteError == message {
                self?.appState.pasteError = nil
            }
        }
    }
}
