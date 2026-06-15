import SwiftUI

struct VoiceSettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    @State private var config = TranscriptionProviderStore.shared.loadConfig()
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Input Settings")
                .font(.headline)
            
            Picker("Mode", selection: $appState.voiceMode) {
                ForEach(VoiceInputMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            Divider()
            
            if appState.voiceMode == .appleSpeech {
                appleSpeechSettings
            } else {
                externalProviderSettings
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Save & Close") {
                    saveSettings()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 420)
        .onAppear {
            if let ref = config.apiKeyReference {
                apiKey = KeychainSecretStore.shared.load(for: ref) ?? ""
            }
        }
    }
    
    private var appleSpeechSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Speech uses on-device or Apple's servers for transcription.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("Language", selection: $appState.selectedSpeechLocale) {
                Text("中文 zh-CN").tag("zh-CN")
                Text("English en-US").tag("en-US")
            }
        }
    }
    
    private var externalProviderSettings: some View {
        Form {
            Section(header: Text("OpenAI-Compatible Provider").font(.caption)) {
                TextField("Provider Name", text: $config.name)
                TextField("Base URL", text: $config.baseURL)
                TextField("Endpoint Path", text: $config.endpointPath)
                TextField("Model", text: $config.model)
                TextField("Language (Optional)", text: Binding(
                    get: { config.language ?? "" },
                    set: { config.language = $0.isEmpty ? nil : $0 }
                ))
                
                SecureField("API Key", text: $apiKey)
            }
        }
    }
    
    private func saveSettings() {
        TranscriptionProviderStore.shared.saveConfig(config)
        if let ref = config.apiKeyReference, !apiKey.isEmpty {
            let _ = KeychainSecretStore.shared.save(secret: apiKey, for: ref)
        }
    }
}
