import Foundation

enum SpeechProviderKind: String, Codable, CaseIterable, Identifiable {
    case appleSpeechLive
    case openAIRealtimeTranscription
    case openAIHTTPTranscription

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeechLive:
            return "Apple Speech Live"
        case .openAIRealtimeTranscription:
            return "OpenAI Realtime"
        case .openAIHTTPTranscription:
            return "OpenAI HTTP"
        }
    }
}

struct SpeechProviderConfig: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var kind: SpeechProviderKind

    var model: String
    var language: String?
    var apiKeyReference: String?

    var baseURL: String
    var endpointPath: String

    var realtimeURL: String?
    var realtimePath: String?

    var inputAudioFormat: String?
    var sampleRate: Int?
    var channels: Int?

    var prompt: String?
    var temperature: Double?
    var enableServerVAD: Bool

    static let appleSpeechID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    static let openAIRealtimeID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    static let openAIHTTPID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    static let appleSpeech = SpeechProviderConfig(
        id: appleSpeechID,
        name: "Apple Speech",
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

    static let openAIRealtime = SpeechProviderConfig(
        id: openAIRealtimeID,
        name: "OpenAI Realtime",
        kind: .openAIRealtimeTranscription,
        model: "gpt-4o-mini-transcribe",
        language: "zh",
        apiKeyReference: "flotis.speechprovider.openai.realtime.apikey",
        baseURL: "https://api.openai.com",
        endpointPath: "/v1/audio/transcriptions",
        realtimeURL: "wss://api.openai.com",
        realtimePath: "/v1/realtime",
        inputAudioFormat: "pcm16",
        sampleRate: 24000,
        channels: 1,
        prompt: nil,
        temperature: nil,
        enableServerVAD: true
    )

    static let openAIHTTP = SpeechProviderConfig(
        id: openAIHTTPID,
        name: "OpenAI HTTP Transcription",
        kind: .openAIHTTPTranscription,
        model: "gpt-4o-mini-transcribe",
        language: "zh",
        apiKeyReference: "flotis.speechprovider.openai.http.apikey",
        baseURL: "https://api.openai.com",
        endpointPath: "/v1/audio/transcriptions",
        realtimeURL: nil,
        realtimePath: nil,
        inputAudioFormat: nil,
        sampleRate: 16000,
        channels: 1,
        prompt: nil,
        temperature: 0.0,
        enableServerVAD: false
    )

    static let defaultProviders: [SpeechProviderConfig] = [
        .appleSpeech,
        .openAIRealtime,
        .openAIHTTP
    ]
}

typealias TranscriptionProviderConfig = SpeechProviderConfig
