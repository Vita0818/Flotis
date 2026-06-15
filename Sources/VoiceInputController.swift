import Foundation

@MainActor
final class VoiceInputController {
    let appState: AppState
    private var activeTranscriber: SpeechTranscribing?
    private var isProcessing = false
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func toggleRecording() {
        if isProcessing { return }
        
        switch appState.voiceState {
        case .idle, .failed:
            startRecording()
        case .recording:
            stopRecordingAndInject()
        default:
            break
        }
    }
    
    private func startRecording() {
        appState.voiceState = .requestingPermission
        appState.transcriptPreview = ""
        
        switch appState.voiceMode {
        case .appleSpeech:
            activeTranscriber = AppleSpeechTranscriber(localeIdentifier: appState.selectedSpeechLocale)
        case .externalProvider:
            let config = TranscriptionProviderStore.shared.loadConfig()
            guard let ref = config.apiKeyReference, let apiKey = KeychainSecretStore.shared.load(for: ref), !apiKey.isEmpty else {
                appState.voiceState = .failed("请先配置外部转写提供商的 API Key。")
                return
            }
            activeTranscriber = OpenAICompatibleTranscriber(config: config, apiKey: apiKey)
        }
        
        activeTranscriber?.partialTranscriptHandler = { [weak self] text in
            DispatchQueue.main.async {
                self?.appState.transcriptPreview = text
            }
        }
        
        Task {
            do {
                try await activeTranscriber?.start()
                appState.voiceState = .recording
            } catch {
                appState.voiceState = .failed(error.localizedDescription)
                activeTranscriber = nil
            }
        }
    }
    
    private func stopRecordingAndInject() {
        guard appState.voiceState == .recording else { return }
        appState.voiceState = .transcribing
        isProcessing = true
        
        Task {
            do {
                let finalTranscript = try await activeTranscriber?.stop() ?? ""
                
                guard !finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    appState.voiceState = .idle
                    appState.transcriptPreview = ""
                    isProcessing = false
                    activeTranscriber = nil
                    return
                }
                
                appState.transcriptPreview = finalTranscript
                appState.voiceState = .injecting
                
                ClipboardPasteInjector.shared.inject(text: finalTranscript) { [weak self] success in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if success {
                            self.appState.voiceState = .idle
                            // Keep the preview for a brief moment then clear
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if self.appState.voiceState == .idle {
                                    self.appState.transcriptPreview = ""
                                }
                            }
                        } else {
                            self.appState.voiceState = .failed("注入失败，可能没有权限")
                        }
                        self.isProcessing = false
                        self.activeTranscriber = nil
                    }
                }
            } catch {
                appState.voiceState = .failed(error.localizedDescription)
                isProcessing = false
                activeTranscriber = nil
            }
        }
    }
}
