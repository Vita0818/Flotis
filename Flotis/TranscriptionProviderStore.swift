import Foundation

struct SpeechProviderStoreSnapshot: Codable {
    var providers: [SpeechProviderConfig]
    var activeProviderID: UUID
}

final class SpeechProviderStore: ObservableObject {
    static let shared = SpeechProviderStore()

    @Published private(set) var providers: [SpeechProviderConfig] = []
    @Published var activeProviderID: UUID
    @Published var lastError: String?

    private let configKey = "flotis.speechProviders.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        activeProviderID = SpeechProviderConfig.appleSpeechID
        load()
    }

    var activeProvider: SpeechProviderConfig {
        providers.first { $0.id == activeProviderID } ?? SpeechProviderConfig.appleSpeech
    }

    func setActiveProvider(id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeProviderID = id
        save()
    }

    func addProvider(kind: SpeechProviderKind) {
        let provider: SpeechProviderConfig
        switch kind {
        case .appleSpeechLive:
            provider = SpeechProviderConfig(
                id: UUID(),
                name: UIStrings.appleSpeech,
                kind: .appleSpeechLive,
                model: "",
                language: "zh-CN",
                apiKeyReference: nil,
                baseURL: "",
                endpointPath: "",
                realtimeURL: nil,
                realtimePath: nil,
                inputAudioFormat: nil,
                sampleRate: nil,
                channels: 1,
                prompt: nil,
                temperature: nil,
                enableServerVAD: false
            )
        case .openAIRealtimeTranscription:
            var copy = SpeechProviderConfig.openAIRealtime
            copy.id = UUID()
            copy.name = UIStrings.customRealtime
            copy.apiKeyReference = "flotis.speechprovider.\(copy.id.uuidString).apikey"
            provider = copy
        case .openAIHTTPTranscription:
            var copy = SpeechProviderConfig.openAIHTTP
            copy.id = UUID()
            copy.name = UIStrings.customHTTP
            copy.apiKeyReference = "flotis.speechprovider.\(copy.id.uuidString).apikey"
            provider = copy
        }

        providers.append(provider)
        activeProviderID = provider.id
        save()
    }

    func updateProvider(_ provider: SpeechProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        var updated = provider
        if updated.kind == .appleSpeechLive {
            updated.apiKeyReference = nil
        } else if updated.apiKeyReference == nil {
            updated.apiKeyReference = "flotis.speechprovider.\(updated.id.uuidString).apikey"
        }
        providers[index] = updated
        save()
    }

    func deleteProvider(id: UUID) {
        guard providers.count > 1 else {
            lastError = "至少需要保留一个语音提供商。"
            return
        }

        if let provider = providers.first(where: { $0.id == id }),
           let reference = provider.apiKeyReference {
            KeychainSecretStore.shared.delete(for: reference)
        }

        providers.removeAll { $0.id == id }
        if activeProviderID == id {
            activeProviderID = providers.first?.id ?? SpeechProviderConfig.appleSpeechID
        }
        save()
    }

    func hasAPIKey(for provider: SpeechProviderConfig) -> Bool {
        guard let reference = provider.apiKeyReference else { return false }
        return !(KeychainSecretStore.shared.load(for: reference) ?? "").isEmpty
    }

    func saveAPIKey(_ apiKey: String, for provider: SpeechProviderConfig) -> Bool {
        guard let reference = provider.apiKeyReference else { return false }
        return KeychainSecretStore.shared.save(secret: apiKey, for: reference)
    }

    func loadConfig() -> SpeechProviderConfig {
        activeProvider
    }

    func saveConfig(_ config: SpeechProviderConfig) {
        updateProvider(config)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let snapshot = try? decoder.decode(SpeechProviderStoreSnapshot.self, from: data),
           !snapshot.providers.isEmpty {
            providers = snapshot.providers.map(localizedProviderName)
            activeProviderID = snapshot.providers.contains(where: { $0.id == snapshot.activeProviderID })
                ? snapshot.activeProviderID
                : snapshot.providers[0].id
            return
        }

        providers = SpeechProviderConfig.defaultProviders
        activeProviderID = SpeechProviderConfig.appleSpeechID
        save()
    }

    private func localizedProviderName(_ provider: SpeechProviderConfig) -> SpeechProviderConfig {
        var localized = provider
        localized.name = provider.displayNameForUI
        return localized
    }

    private func save() {
        let snapshot = SpeechProviderStoreSnapshot(
            providers: providers,
            activeProviderID: activeProviderID
        )

        do {
            let data = try encoder.encode(snapshot)
            UserDefaults.standard.set(data, forKey: configKey)
            lastError = nil
        } catch {
            lastError = "语音提供商配置保存失败。"
        }
    }
}

typealias TranscriptionProviderStore = SpeechProviderStore
