import Foundation

final class TranscriptionProviderStore {
    static let shared = TranscriptionProviderStore()
    private let configKey = "flotis.providerConfig"
    
    private init() {}
    
    func loadConfig() -> TranscriptionProviderConfig {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let config = try? JSONDecoder().decode(TranscriptionProviderConfig.self, from: data) {
            return config
        }
        return TranscriptionProviderConfig()
    }
    
    func saveConfig(_ config: TranscriptionProviderConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
}
