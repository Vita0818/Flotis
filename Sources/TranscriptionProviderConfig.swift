import Foundation

struct TranscriptionProviderConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "OpenAI"
    var baseURL: String = "https://api.openai.com"
    var endpointPath: String = "/v1/audio/transcriptions"
    var model: String = "whisper-1" // "gpt-4o-mini-transcribe" doesn't strictly exist for whisper yet, but will allow whatever
    var apiKeyReference: String? = "flotis.externalprovider.apikey"
    var language: String? = "zh"
    var temperature: Double? = 0.0
}
