import Foundation

enum SpeechProviderKind: String, Codable, CaseIterable, Identifiable {
    case appleSpeechLive
    case openAIRealtimeTranscription
    case openAIHTTPTranscription

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeechLive:
            return UIStrings.appleSpeech
        case .openAIRealtimeTranscription:
            return UIStrings.realtimeTranscription
        case .openAIHTTPTranscription:
            return UIStrings.httpTranscription
        }
    }
}

enum SpeechProviderEndpointStyle: String, Codable, Equatable {
    case none
    case secureWebSocket
    case secureHTTP
}

enum TranscriptionTransport: String, Codable, Equatable {
    case local
    case realtimeWebSocket
    case fileUploadHTTP
}

enum TranscriptionAuthenticationType: String, Codable, Equatable {
    case none
    case bearer
    case xAPIKey = "x-api-key"
}

enum TranscriptionResponseMode: String, Codable, Equatable {
    case json
    case serverSentEvents = "sse"
}

enum TranscriptionAdapterID: String, Codable, CaseIterable, Identifiable {
    case appleOnDevice = "apple-on-device"
    case openAIAudioTranscriptionsHTTPV1 = "openai-audio-transcriptions-http-v1"
    case openAIRealtimeTranscriptionGA = "openai-realtime-transcription-ga"
    case dashScopeParaformerWSV1 = "dashscope-paraformer-ws-v1"
    case volcengineBigASRWSV3 = "volcengine-bigasr-ws-v3"
    case glmASRHTTPSSEV4 = "glm-asr-http-sse-v4"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice:
            return UIStrings.appleSpeech
        case .openAIAudioTranscriptionsHTTPV1:
            return "OpenAI-compatible \(UIStrings.httpTranscription)"
        case .openAIRealtimeTranscriptionGA:
            return "OpenAI Realtime GA"
        case .dashScopeParaformerWSV1:
            return UIStrings.qwenParaformerRealtime
        case .volcengineBigASRWSV3:
            return UIStrings.volcengineBigASRRealtime
        case .glmASRHTTPSSEV4:
            return UIStrings.glmASRHTTPStream
        }
    }
}

struct SpeechProviderProtocolSchema: Equatable {
    let adapterID: TranscriptionAdapterID
    let adapterVersion: String
    let kind: SpeechProviderKind
    let transport: TranscriptionTransport
    let authenticationType: TranscriptionAuthenticationType
    let endpointStyle: SpeechProviderEndpointStyle
    let requiresAPIKey: Bool
    let supportsEditableModel: Bool
    let supportsLanguage: Bool
    let supportsPrompt: Bool
    let supportsTemperature: Bool
    let supportsVolcengineTwoPass: Bool
    let fixedModel: String?
    let defaultModel: String?
    let fixedModelName: String?
    let fixedInputAudioFormat: String?
    let defaultInputAudioFormat: String?
    let allowedInputAudioFormats: Set<String>
    let fixedSampleRate: Int?
    let fixedChannels: Int?
    let responseMode: TranscriptionResponseMode?
    let maximumRecordingDurationSeconds: Int?
    let maximumUploadBytes: Int?
    let trustedHostSuffixes: [String]

    func isTrusted(host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return trustedHostSuffixes.contains { suffix in
            normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
        }
    }
}

extension TranscriptionAdapterID {
    var schema: SpeechProviderProtocolSchema {
        switch self {
        case .appleOnDevice:
            return SpeechProviderProtocolSchema(
                adapterID: self,
                adapterVersion: "1",
                kind: .appleSpeechLive,
                transport: .local,
                authenticationType: .none,
                endpointStyle: .none,
                requiresAPIKey: false,
                supportsEditableModel: false,
                supportsLanguage: true,
                supportsPrompt: false,
                supportsTemperature: false,
                supportsVolcengineTwoPass: false,
                fixedModel: nil,
                defaultModel: nil,
                fixedModelName: nil,
                fixedInputAudioFormat: nil,
                defaultInputAudioFormat: nil,
                allowedInputAudioFormats: [],
                fixedSampleRate: nil,
                fixedChannels: nil,
                responseMode: nil,
                maximumRecordingDurationSeconds: nil,
                maximumUploadBytes: nil,
                trustedHostSuffixes: []
            )
        case .openAIAudioTranscriptionsHTTPV1:
            return SpeechProviderProtocolSchema(
                adapterID: self,
                adapterVersion: "1",
                kind: .openAIHTTPTranscription,
                transport: .fileUploadHTTP,
                authenticationType: .bearer,
                endpointStyle: .secureHTTP,
                requiresAPIKey: true,
                supportsEditableModel: true,
                supportsLanguage: true,
                supportsPrompt: true,
                supportsTemperature: true,
                supportsVolcengineTwoPass: false,
                fixedModel: nil,
                defaultModel: "gpt-4o-mini-transcribe",
                fixedModelName: nil,
                fixedInputAudioFormat: nil,
                defaultInputAudioFormat: "wav",
                allowedInputAudioFormats: ["wav", "m4a"],
                fixedSampleRate: 16_000,
                fixedChannels: 1,
                responseMode: .json,
                maximumRecordingDurationSeconds: nil,
                maximumUploadBytes: nil,
                trustedHostSuffixes: ["api.openai.com"]
            )
        case .openAIRealtimeTranscriptionGA:
            return SpeechProviderProtocolSchema(
                adapterID: self,
                adapterVersion: "ga",
                kind: .openAIRealtimeTranscription,
                transport: .realtimeWebSocket,
                authenticationType: .bearer,
                endpointStyle: .secureWebSocket,
                requiresAPIKey: true,
                supportsEditableModel: true,
                supportsLanguage: true,
                supportsPrompt: false,
                supportsTemperature: false,
                supportsVolcengineTwoPass: false,
                fixedModel: nil,
                defaultModel: "gpt-realtime-whisper",
                fixedModelName: nil,
                fixedInputAudioFormat: "pcm16",
                defaultInputAudioFormat: "pcm16",
                allowedInputAudioFormats: ["pcm16"],
                fixedSampleRate: 24_000,
                fixedChannels: 1,
                responseMode: nil,
                maximumRecordingDurationSeconds: nil,
                maximumUploadBytes: nil,
                trustedHostSuffixes: ["api.openai.com"]
            )
        case .dashScopeParaformerWSV1:
            return SpeechProviderProtocolSchema(
                adapterID: self,
                adapterVersion: "1",
                kind: .openAIRealtimeTranscription,
                transport: .realtimeWebSocket,
                authenticationType: .bearer,
                endpointStyle: .secureWebSocket,
                requiresAPIKey: true,
                supportsEditableModel: false,
                supportsLanguage: true,
                supportsPrompt: false,
                supportsTemperature: false,
                supportsVolcengineTwoPass: false,
                fixedModel: "paraformer-realtime-v2",
                defaultModel: "paraformer-realtime-v2",
                fixedModelName: nil,
                fixedInputAudioFormat: "pcm",
                defaultInputAudioFormat: "pcm",
                allowedInputAudioFormats: ["pcm"],
                fixedSampleRate: 16_000,
                fixedChannels: 1,
                responseMode: nil,
                maximumRecordingDurationSeconds: nil,
                maximumUploadBytes: nil,
                trustedHostSuffixes: ["dashscope.aliyuncs.com", "maas.aliyuncs.com"]
            )
        case .volcengineBigASRWSV3:
            return SpeechProviderProtocolSchema(
                adapterID: self,
                adapterVersion: "3",
                kind: .openAIRealtimeTranscription,
                transport: .realtimeWebSocket,
                authenticationType: .xAPIKey,
                endpointStyle: .secureWebSocket,
                requiresAPIKey: true,
                supportsEditableModel: false,
                supportsLanguage: false,
                supportsPrompt: false,
                supportsTemperature: false,
                supportsVolcengineTwoPass: true,
                fixedModel: nil,
                defaultModel: nil,
                fixedModelName: "bigmodel",
                fixedInputAudioFormat: "pcm",
                defaultInputAudioFormat: "pcm",
                allowedInputAudioFormats: ["pcm"],
                fixedSampleRate: 16_000,
                fixedChannels: 1,
                responseMode: nil,
                maximumRecordingDurationSeconds: nil,
                maximumUploadBytes: nil,
                trustedHostSuffixes: ["openspeech.bytedance.com"]
            )
        case .glmASRHTTPSSEV4:
            return SpeechProviderProtocolSchema(
                adapterID: self,
                adapterVersion: "4",
                kind: .openAIHTTPTranscription,
                transport: .fileUploadHTTP,
                authenticationType: .bearer,
                endpointStyle: .secureHTTP,
                requiresAPIKey: true,
                supportsEditableModel: false,
                supportsLanguage: false,
                supportsPrompt: true,
                supportsTemperature: false,
                supportsVolcengineTwoPass: false,
                fixedModel: "glm-asr-2512",
                defaultModel: "glm-asr-2512",
                fixedModelName: nil,
                fixedInputAudioFormat: "wav",
                defaultInputAudioFormat: "wav",
                allowedInputAudioFormats: ["wav"],
                fixedSampleRate: 16_000,
                fixedChannels: 1,
                responseMode: .serverSentEvents,
                maximumRecordingDurationSeconds: 30,
                maximumUploadBytes: 25 * 1_024 * 1_024,
                trustedHostSuffixes: ["open.bigmodel.cn"]
            )
        }
    }
}

enum SpeechProviderWireProtocol: String, Codable, CaseIterable, Identifiable {
    case appleSpeech
    case openAIRealtime
    case openAIHTTP
    case dashScopeParaformerRealtime
    case volcengineBigASRRealtime
    case glmASRHTTPStream

    var id: String { rawValue }

    var adapterID: TranscriptionAdapterID {
        switch self {
        case .appleSpeech: return .appleOnDevice
        case .openAIRealtime: return .openAIRealtimeTranscriptionGA
        case .openAIHTTP: return .openAIAudioTranscriptionsHTTPV1
        case .dashScopeParaformerRealtime: return .dashScopeParaformerWSV1
        case .volcengineBigASRRealtime: return .volcengineBigASRWSV3
        case .glmASRHTTPStream: return .glmASRHTTPSSEV4
        }
    }

    init(adapterID: TranscriptionAdapterID) {
        switch adapterID {
        case .appleOnDevice: self = .appleSpeech
        case .openAIAudioTranscriptionsHTTPV1: self = .openAIHTTP
        case .openAIRealtimeTranscriptionGA: self = .openAIRealtime
        case .dashScopeParaformerWSV1: self = .dashScopeParaformerRealtime
        case .volcengineBigASRWSV3: self = .volcengineBigASRRealtime
        case .glmASRHTTPSSEV4: self = .glmASRHTTPStream
        }
    }

    var displayName: String { adapterID.displayName }
    var schema: SpeechProviderProtocolSchema { adapterID.schema }

    func supports(kind: SpeechProviderKind) -> Bool {
        schema.kind == kind
    }
}

struct TranscriptionEndpoint: Codable, Equatable {
    var baseURL: String
    var path: String
    var customEndpointApproved: Bool?

    init(baseURL: String = "", path: String = "", customEndpointApproved: Bool? = nil) {
        self.baseURL = baseURL
        self.path = path
        self.customEndpointApproved = customEndpointApproved
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case path
        case customEndpointApproved
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(customEndpointApproved, forKey: .customEndpointApproved)
    }
}

struct TranscriptionAuthentication: Codable, Equatable {
    var type: TranscriptionAuthenticationType
    var apiKeyReference: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case apiKeyReference
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(apiKeyReference, forKey: .apiKeyReference)
    }
}

struct TranscriptionAudioConfiguration: Codable, Equatable {
    var format: String? = nil
    var sampleRate: Int? = nil
    var channels: Int? = nil

    var isEmpty: Bool { format == nil && sampleRate == nil && channels == nil }

    private enum CodingKeys: String, CodingKey {
        case format
        case sampleRate
        case channels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(channels, forKey: .channels)
    }
}

struct TranscriptionConnectionOptions: Codable, Equatable {
    var prompt: String? = nil
    var temperature: Double? = nil
    var responseMode: TranscriptionResponseMode? = nil
    var resourceID: String? = nil
    var modelName: String? = nil
    var twoPassRecognition: Bool? = nil

    var isEmpty: Bool {
        prompt == nil
            && temperature == nil
            && responseMode == nil
            && resourceID == nil
            && modelName == nil
            && twoPassRecognition == nil
    }

    private enum CodingKeys: String, CodingKey {
        case prompt
        case temperature
        case responseMode
        case resourceID
        case modelName
        case twoPassRecognition
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(responseMode, forKey: .responseMode)
        try container.encodeIfPresent(resourceID, forKey: .resourceID)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encodeIfPresent(twoPassRecognition, forKey: .twoPassRecognition)
    }
}

enum TranscriptionConnectionTestOutcome: String, Codable, Equatable {
    case succeeded
    case failed
}

struct TranscriptionConnectionTestRecord: Codable, Equatable {
    var testedAt: Date
    var adapterVersion: String
    var outcome: TranscriptionConnectionTestOutcome
    var safeSummary: String
    var configurationFingerprint: String

    init(
        testedAt: Date = Date(),
        adapterVersion: String,
        outcome: TranscriptionConnectionTestOutcome,
        safeSummary: String,
        configurationFingerprint: String
    ) {
        self.testedAt = testedAt
        self.adapterVersion = adapterVersion
        self.outcome = outcome
        self.safeSummary = Self.sanitize(summary: safeSummary)
        self.configurationFingerprint = configurationFingerprint
    }

    private static func sanitize(summary: String) -> String {
        var singleLine = summary
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let redactionPatterns = [
            "(?i)bearer\\s+[^\\s,;]+",
            "(?i)(authorization|api[-_ ]?key|x-api-key)\\s*[:=]\\s*[^\\s,;]+",
            "(?i)sk-[a-z0-9_-]+"
        ]
        for pattern in redactionPatterns {
            singleLine = singleLine.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
        return String(singleLine.prefix(240))
    }
}

struct TranscriptionConnection: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var adapterID: TranscriptionAdapterID
    var endpoint: TranscriptionEndpoint?
    private var storedModel: String?
    var language: String?
    var authentication: TranscriptionAuthentication
    var audio: TranscriptionAudioConfiguration
    var options: TranscriptionConnectionOptions
    var credentialRevision: Int
    var lastConnectionTest: TranscriptionConnectionTestRecord?

    init(
        id: UUID,
        name: String,
        adapterID: TranscriptionAdapterID,
        endpoint: TranscriptionEndpoint? = nil,
        model: String? = nil,
        language: String? = nil,
        authentication: TranscriptionAuthentication? = nil,
        audio: TranscriptionAudioConfiguration = .init(),
        options: TranscriptionConnectionOptions = .init(),
        credentialRevision: Int = 0,
        lastConnectionTest: TranscriptionConnectionTestRecord? = nil
    ) {
        self.id = id
        self.name = name
        self.adapterID = adapterID
        self.endpoint = endpoint
        storedModel = trimmedOptional(model)
        self.language = trimmedOptional(language)
        self.authentication = authentication ?? TranscriptionAuthentication(
            type: adapterID.schema.authenticationType,
            apiKeyReference: nil
        )
        self.audio = audio
        self.options = options
        self.credentialRevision = max(0, credentialRevision)
        self.lastConnectionTest = lastConnectionTest
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case adapterID
        case endpoint
        case model
        case language
        case authentication
        case audio
        case options
        case credentialRevision
        case lastConnectionTest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        adapterID = try container.decode(TranscriptionAdapterID.self, forKey: .adapterID)
        endpoint = try container.decodeIfPresent(TranscriptionEndpoint.self, forKey: .endpoint)
        storedModel = try container.decodeIfPresent(String.self, forKey: .model)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        authentication = try container.decodeIfPresent(
            TranscriptionAuthentication.self,
            forKey: .authentication
        ) ?? TranscriptionAuthentication(type: adapterID.schema.authenticationType, apiKeyReference: nil)
        audio = try container.decodeIfPresent(
            TranscriptionAudioConfiguration.self,
            forKey: .audio
        ) ?? TranscriptionAudioConfiguration()
        options = try container.decodeIfPresent(
            TranscriptionConnectionOptions.self,
            forKey: .options
        ) ?? TranscriptionConnectionOptions()
        credentialRevision = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .credentialRevision) ?? 0
        )
        lastConnectionTest = try container.decodeIfPresent(
            TranscriptionConnectionTestRecord.self,
            forKey: .lastConnectionTest
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(adapterID, forKey: .adapterID)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(trimmedOptional(storedModel), forKey: .model)
        try container.encodeIfPresent(trimmedOptional(language), forKey: .language)
        if authentication.type != .none || authentication.apiKeyReference != nil {
            try container.encode(authentication, forKey: .authentication)
        }
        if !audio.isEmpty {
            try container.encode(audio, forKey: .audio)
        }
        if !options.isEmpty {
            try container.encode(options, forKey: .options)
        }
        if credentialRevision != 0 {
            try container.encode(credentialRevision, forKey: .credentialRevision)
        }
        try container.encodeIfPresent(lastConnectionTest, forKey: .lastConnectionTest)
    }
}

typealias SpeechProviderConfig = TranscriptionConnection
typealias TranscriptionProviderConfig = TranscriptionConnection

extension TranscriptionConnection {
    static let appleSpeechID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    static let openAIRealtimeID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    static let openAIHTTPID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    static let qwenParaformerRealtimeID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    static let volcengineBigASRRealtimeID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    static let glmASRHTTPStreamID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    static let appleSpeech = TranscriptionConnection(
        id: appleSpeechID,
        name: UIStrings.appleSpeech,
        adapterID: .appleOnDevice,
        language: "zh-CN"
    ).normalizedForProtocol()

    static let openAIRealtime = TranscriptionConnection(
        id: openAIRealtimeID,
        name: "OpenAI \(UIStrings.realtimeTranscription)",
        adapterID: .openAIRealtimeTranscriptionGA,
        endpoint: TranscriptionEndpoint(
            baseURL: "wss://api.openai.com",
            path: "/v1/realtime"
        ),
        model: "gpt-realtime-whisper",
        language: "zh",
        authentication: TranscriptionAuthentication(
            type: .bearer,
            apiKeyReference: "flotis.speechprovider.openai.realtime.apikey"
        ),
        audio: TranscriptionAudioConfiguration(format: "pcm16", sampleRate: 24_000, channels: 1)
    ).normalizedForProtocol()

    static let openAIHTTP = TranscriptionConnection(
        id: openAIHTTPID,
        name: "OpenAI \(UIStrings.httpTranscription)",
        adapterID: .openAIAudioTranscriptionsHTTPV1,
        endpoint: TranscriptionEndpoint(
            baseURL: "https://api.openai.com",
            path: "/v1/audio/transcriptions"
        ),
        model: "gpt-4o-mini-transcribe",
        language: "zh",
        authentication: TranscriptionAuthentication(
            type: .bearer,
            apiKeyReference: "flotis.speechprovider.openai.http.apikey"
        ),
        audio: TranscriptionAudioConfiguration(format: "wav", sampleRate: 16_000, channels: 1),
        options: TranscriptionConnectionOptions(responseMode: .json)
    ).normalizedForProtocol()

    static let qwenParaformerRealtime = TranscriptionConnection(
        id: qwenParaformerRealtimeID,
        name: UIStrings.qwenParaformerRealtime,
        adapterID: .dashScopeParaformerWSV1,
        endpoint: TranscriptionEndpoint(
            baseURL: "wss://dashscope.aliyuncs.com",
            path: "/api-ws/v1/inference"
        ),
        model: "paraformer-realtime-v2",
        language: "zh",
        authentication: TranscriptionAuthentication(
            type: .bearer,
            apiKeyReference: "flotis.speechprovider.qwen.paraformer.apikey"
        ),
        audio: TranscriptionAudioConfiguration(format: "pcm", sampleRate: 16_000, channels: 1)
    ).normalizedForProtocol()

    static let volcengineBigASRRealtime = TranscriptionConnection(
        id: volcengineBigASRRealtimeID,
        name: UIStrings.volcengineBigASRRealtime,
        adapterID: .volcengineBigASRWSV3,
        endpoint: TranscriptionEndpoint(
            baseURL: "wss://openspeech.bytedance.com",
            path: "/api/v3/sauc/bigmodel_async"
        ),
        authentication: TranscriptionAuthentication(
            type: .xAPIKey,
            apiKeyReference: "flotis.speechprovider.volcengine.bigasr.apikey"
        ),
        audio: TranscriptionAudioConfiguration(format: "pcm", sampleRate: 16_000, channels: 1),
        options: TranscriptionConnectionOptions(
            resourceID: "volc.seedasr.sauc.duration",
            modelName: "bigmodel",
            twoPassRecognition: true
        )
    ).normalizedForProtocol()

    static let glmASRHTTPStream = TranscriptionConnection(
        id: glmASRHTTPStreamID,
        name: UIStrings.glmASRHTTPStream,
        adapterID: .glmASRHTTPSSEV4,
        endpoint: TranscriptionEndpoint(
            baseURL: "https://open.bigmodel.cn/api",
            path: "/paas/v4/audio/transcriptions"
        ),
        model: "glm-asr-2512",
        authentication: TranscriptionAuthentication(
            type: .bearer,
            apiKeyReference: "flotis.speechprovider.glm.asr.apikey"
        ),
        audio: TranscriptionAudioConfiguration(format: "wav", sampleRate: 16_000, channels: 1),
        options: TranscriptionConnectionOptions(responseMode: .serverSentEvents)
    ).normalizedForProtocol()

    static let defaultProviders: [TranscriptionConnection] = [
        .appleSpeech,
        .openAIRealtime,
        .openAIHTTP,
        .qwenParaformerRealtime,
        .volcengineBigASRRealtime,
        .glmASRHTTPStream
    ]

    static let v2AddedPresetIDs: Set<UUID> = [
        qwenParaformerRealtimeID,
        volcengineBigASRRealtimeID,
        glmASRHTTPStreamID
    ]

    var protocolSchema: SpeechProviderProtocolSchema { adapterID.schema }

    var kind: SpeechProviderKind {
        get { protocolSchema.kind }
        set {
            guard protocolSchema.kind != newValue else { return }
            switch newValue {
            case .appleSpeechLive:
                self = applyingAdapter(.appleOnDevice)
            case .openAIRealtimeTranscription:
                self = applyingAdapter(.openAIRealtimeTranscriptionGA)
            case .openAIHTTPTranscription:
                self = applyingAdapter(.openAIAudioTranscriptionsHTTPV1)
            }
        }
    }

    var wireProtocol: SpeechProviderWireProtocol? {
        get { SpeechProviderWireProtocol(adapterID: adapterID) }
        set {
            guard let newValue else { return }
            self = applyingAdapter(newValue.adapterID)
        }
    }

    var resolvedWireProtocol: SpeechProviderWireProtocol {
        SpeechProviderWireProtocol(adapterID: adapterID)
    }

    var model: String {
        get {
            if adapterID == .volcengineBigASRWSV3 {
                return nonEmpty(options.resourceID) ?? nonEmpty(storedModel) ?? ""
            }
            return storedModel ?? ""
        }
        set { storedModel = trimmedOptional(newValue) }
    }

    var apiKeyReference: String? {
        get { authentication.apiKeyReference }
        set { authentication.apiKeyReference = trimmedOptional(newValue) }
    }

    var baseURL: String {
        get { protocolSchema.endpointStyle == .secureHTTP ? endpoint?.baseURL ?? "" : "" }
        set { updateEndpointBaseURL(newValue) }
    }

    var endpointPath: String {
        get { protocolSchema.endpointStyle == .secureHTTP ? endpoint?.path ?? "" : "" }
        set { updateEndpointPath(newValue) }
    }

    var realtimeURL: String? {
        get {
            guard protocolSchema.endpointStyle == .secureWebSocket else { return nil }
            return trimmedOptional(endpoint?.baseURL)
        }
        set { updateEndpointBaseURL(newValue ?? "") }
    }

    var realtimePath: String? {
        get {
            guard protocolSchema.endpointStyle == .secureWebSocket else { return nil }
            return trimmedOptional(endpoint?.path)
        }
        set { updateEndpointPath(newValue ?? "") }
    }

    var inputAudioFormat: String? {
        get { audio.format }
        set { audio.format = trimmedOptional(newValue)?.lowercased() }
    }

    var sampleRate: Int? {
        get { audio.sampleRate }
        set { audio.sampleRate = newValue }
    }

    var channels: Int? {
        get { audio.channels }
        set { audio.channels = newValue }
    }

    var prompt: String? {
        get { options.prompt }
        set { options.prompt = trimmedOptional(newValue) }
    }

    var temperature: Double? {
        get { options.temperature }
        set { options.temperature = newValue }
    }

    var enableServerVAD: Bool {
        get { options.twoPassRecognition ?? false }
        set { options.twoPassRecognition = protocolSchema.supportsVolcengineTwoPass ? newValue : nil }
    }

    var resourceID: String? {
        get { options.resourceID }
        set { options.resourceID = trimmedOptional(newValue) }
    }

    var modelName: String? {
        get { options.modelName }
        set { options.modelName = trimmedOptional(newValue) }
    }

    var customEndpointApproved: Bool? {
        get { endpoint?.customEndpointApproved }
        set {
            guard endpoint != nil else { return }
            endpoint?.customEndpointApproved = newValue == true ? true : nil
        }
    }

    var maximumRecordingDurationSeconds: Int? {
        protocolSchema.maximumRecordingDurationSeconds
    }

    var maximumUploadBytes: Int? {
        protocolSchema.maximumUploadBytes
    }

    var isCustomEndpointApproved: Bool {
        get { customEndpointApproved == true }
        set { customEndpointApproved = newValue ? true : nil }
    }

    var volcengineResourceID: String {
        get { nonEmpty(options.resourceID) ?? nonEmpty(storedModel) ?? "volc.seedasr.sauc.duration" }
        set {
            options.resourceID = trimmedOptional(newValue)
            storedModel = nil
        }
    }

    var volcengineModelName: String {
        nonEmpty(options.modelName) ?? "bigmodel"
    }

    var enableVolcengineTwoPassRecognition: Bool {
        get { options.twoPassRecognition ?? false }
        set { options.twoPassRecognition = newValue }
    }

    static func isValidVolcengineResourceID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("volc.")
            && trimmed.contains(".sauc.")
            && !trimmed.contains { $0.isWhitespace }
    }

    var credentialDestinationHost: String? {
        credentialDestinationComponents?.host?.lowercased()
    }

    var credentialDestinationIdentifier: String? {
        guard let components = credentialDestinationComponents,
              let host = components.host?.lowercased() else { return nil }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }

    var usesTrustedEndpoint: Bool {
        guard let components = credentialDestinationComponents,
              let host = components.host else {
            return protocolSchema.endpointStyle == .none
        }
        let effectivePort = components.port ?? Self.defaultPort(for: components.scheme)
        return effectivePort == 443 && protocolSchema.isTrusted(host: host)
    }

    var secretBoundaryIdentifier: String {
        guard let components = credentialDestinationComponents,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return "\(adapterID.rawValue)|local|0|\(authentication.type.rawValue)"
        }
        let port = components.port ?? Self.defaultPort(for: scheme)
        return "\(adapterID.rawValue)|\(scheme)|\(host)|\(port)|\(authentication.type.rawValue)"
    }

    var connectionTestFingerprint: String {
        struct Payload: Encodable {
            let adapterID: TranscriptionAdapterID
            let endpoint: TranscriptionEndpoint?
            let model: String?
            let language: String?
            let authenticationType: TranscriptionAuthenticationType
            let audio: TranscriptionAudioConfiguration
            let options: TranscriptionConnectionOptions
            let credentialRevision: Int
        }

        let endpointForFingerprint = endpoint.map {
            TranscriptionEndpoint(
                baseURL: $0.baseURL,
                path: $0.path,
                customEndpointApproved: nil
            )
        }
        let payload = Payload(
            adapterID: adapterID,
            endpoint: endpointForFingerprint,
            model: trimmedOptional(storedModel),
            language: trimmedOptional(language),
            authenticationType: authentication.type,
            audio: audio,
            options: options,
            credentialRevision: credentialRevision
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(payload)) ?? Data()
        return stableFingerprint(bytes)
    }

    var isConnectionTestCurrent: Bool {
        guard let record = lastConnectionTest else { return false }
        return record.adapterVersion == protocolSchema.adapterVersion
            && record.configurationFingerprint == connectionTestFingerprint
    }

    mutating func recordConnectionTest(
        outcome: TranscriptionConnectionTestOutcome,
        safeSummary: String,
        testedAt: Date = Date()
    ) {
        lastConnectionTest = TranscriptionConnectionTestRecord(
            testedAt: testedAt,
            adapterVersion: protocolSchema.adapterVersion,
            outcome: outcome,
            safeSummary: safeSummary,
            configurationFingerprint: connectionTestFingerprint
        )
    }

    func applyingAdapter(
        _ newAdapterID: TranscriptionAdapterID,
        apiKeyReference newReference: String? = nil
    ) -> TranscriptionConnection {
        var seed = TranscriptionConnection(
            id: id,
            name: name,
            adapterID: newAdapterID,
            authentication: TranscriptionAuthentication(
                type: newAdapterID.schema.authenticationType,
                apiKeyReference: newAdapterID.schema.requiresAPIKey
                    ? (newReference ?? Self.makeAPIKeyReference(providerID: id, adapterID: newAdapterID))
                    : nil
            ),
            credentialRevision: credentialRevision + 1
        )
        if let preset = TranscriptionProviderPreset.defaultPreset(for: newAdapterID) {
            seed = preset.applying(to: seed)
        }
        seed.authentication.apiKeyReference = newAdapterID.schema.requiresAPIKey
            ? (newReference ?? Self.makeAPIKeyReference(providerID: id, adapterID: newAdapterID))
            : nil
        seed.credentialRevision = credentialRevision + 1
        seed.lastConnectionTest = nil
        return seed.normalizedForProtocol()
    }

    func applyingWireProtocol(
        _ newProtocol: SpeechProviderWireProtocol,
        apiKeyReference newReference: String? = nil
    ) -> TranscriptionConnection {
        applyingAdapter(newProtocol.adapterID, apiKeyReference: newReference)
    }

    func normalizedForProtocol() -> TranscriptionConnection {
        var updated = self
        let schema = adapterID.schema

        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.storedModel = trimmedOptional(storedModel)
        updated.language = schema.supportsLanguage ? trimmedOptional(language) : nil
        updated.authentication.type = schema.authenticationType
        updated.authentication.apiKeyReference = schema.requiresAPIKey
            ? trimmedOptional(authentication.apiKeyReference)
            : nil
        updated.credentialRevision = max(0, credentialRevision)

        switch schema.endpointStyle {
        case .none:
            updated.endpoint = nil
        case .secureHTTP, .secureWebSocket:
            var normalizedEndpoint = endpoint ?? TranscriptionEndpoint()
            normalizedEndpoint.baseURL = trimTrailingSlashes(
                normalizedEndpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            normalizedEndpoint.path = normalizedEndpoint.path
                .trimmingCharacters(in: .whitespacesAndNewlines)
            updated.endpoint = normalizedEndpoint
        }

        if let fixedModel = schema.fixedModel {
            updated.storedModel = fixedModel
        } else if adapterID != .volcengineBigASRWSV3,
                  updated.storedModel == nil {
            updated.storedModel = schema.defaultModel
        }

        let requestedFormat = trimmedOptional(updated.audio.format)?.lowercased()
        if let fixedFormat = schema.fixedInputAudioFormat {
            updated.audio.format = fixedFormat
        } else if let requestedFormat,
                  schema.allowedInputAudioFormats.contains(requestedFormat) {
            updated.audio.format = requestedFormat
        } else {
            updated.audio.format = schema.defaultInputAudioFormat
        }
        updated.audio.sampleRate = schema.fixedSampleRate
        updated.audio.channels = schema.fixedChannels

        updated.options.prompt = schema.supportsPrompt ? trimmedOptional(options.prompt) : nil
        updated.options.temperature = schema.supportsTemperature ? options.temperature : nil
        updated.options.responseMode = schema.responseMode

        if schema.supportsVolcengineTwoPass {
            updated.options.resourceID = trimmedOptional(options.resourceID)
                ?? trimmedOptional(storedModel)
                ?? "volc.seedasr.sauc.duration"
            updated.options.modelName = schema.fixedModelName
            updated.options.twoPassRecognition = options.twoPassRecognition ?? true
            updated.storedModel = nil
        } else {
            updated.options.resourceID = nil
            updated.options.modelName = nil
            updated.options.twoPassRecognition = nil
        }

        if updated.usesTrustedEndpoint {
            updated.endpoint?.customEndpointApproved = nil
        }
        return updated
    }

    func configurationValidationError() -> String? {
        let normalized = normalizedForProtocol()
        let schema = normalized.protocolSchema

        if normalized.name.isEmpty {
            return UIStrings.providerNameRequired
        }
        if normalized.adapterID != .volcengineBigASRWSV3,
           (schema.supportsEditableModel || schema.fixedModel != nil),
           normalized.model.isEmpty {
            return UIStrings.providerModelRequired
        }

        switch schema.endpointStyle {
        case .none:
            break
        case .secureWebSocket:
            if let error = Self.validateEndpoint(
                base: normalized.endpoint?.baseURL,
                path: normalized.endpoint?.path,
                requiredScheme: "wss"
            ) {
                return error
            }
        case .secureHTTP:
            if let error = Self.validateEndpoint(
                base: normalized.endpoint?.baseURL,
                path: normalized.endpoint?.path,
                requiredScheme: "https"
            ) {
                return error
            }
        }

        if schema.endpointStyle != .none,
           !normalized.usesTrustedEndpoint,
           !normalized.isCustomEndpointApproved {
            return UIStrings.customEndpointConfirmationRequired
        }

        if normalized.adapterID == .volcengineBigASRWSV3 {
            if !Self.isValidVolcengineResourceID(normalized.volcengineResourceID) {
                return UIStrings.volcengineResourceIDInvalid
            }
            if normalized.volcengineModelName != "bigmodel" {
                return UIStrings.volcengineModelNameInvalid
            }
        }

        if let temperature = normalized.temperature,
           !(0.0...1.0).contains(temperature) {
            return UIStrings.temperatureRangeError
        }

        guard let format = normalized.inputAudioFormat else {
            if schema.defaultInputAudioFormat != nil {
                return UIStrings.audioParametersInvalid
            }
            return nil
        }
        if !schema.allowedInputAudioFormats.isEmpty,
           !schema.allowedInputAudioFormats.contains(format) {
            return UIStrings.audioParametersInvalid
        }
        if normalized.sampleRate != schema.fixedSampleRate
            || normalized.channels != schema.fixedChannels {
            return UIStrings.audioParametersInvalid
        }
        return nil
    }

    static func preset(for wireProtocol: SpeechProviderWireProtocol) -> TranscriptionConnection {
        defaultProviders.first { $0.adapterID == wireProtocol.adapterID }
            ?? .appleSpeech
    }

    static func makeAPIKeyReference(
        providerID: UUID,
        adapterID: TranscriptionAdapterID,
        nonce: UUID = UUID()
    ) -> String {
        "flotis.transcriptionconnection.\(providerID.uuidString.lowercased()).\(adapterID.rawValue).\(nonce.uuidString.lowercased()).apikey"
    }

    static func makeAPIKeyReference(
        providerID: UUID,
        wireProtocol: SpeechProviderWireProtocol,
        nonce: UUID = UUID()
    ) -> String {
        makeAPIKeyReference(providerID: providerID, adapterID: wireProtocol.adapterID, nonce: nonce)
    }

    var displayNameForUI: String { name }

    private var credentialDestinationComponents: URLComponents? {
        guard let endpoint else { return nil }
        return URLComponents(string: endpoint.baseURL)
    }

    private mutating func updateEndpointBaseURL(_ value: String) {
        guard protocolSchema.endpointStyle != .none else { return }
        var updated = endpoint ?? TranscriptionEndpoint()
        updated.baseURL = value
        endpoint = updated
    }

    private mutating func updateEndpointPath(_ value: String) {
        guard protocolSchema.endpointStyle != .none else { return }
        var updated = endpoint ?? TranscriptionEndpoint()
        updated.path = value
        endpoint = updated
    }

    private static func defaultPort(for scheme: String?) -> Int {
        switch scheme?.lowercased() {
        case "https", "wss": return 443
        default: return 0
        }
    }

    private static func validateEndpoint(
        base: String?,
        path: String?,
        requiredScheme: String
    ) -> String? {
        guard let base = trimmedOptional(base),
              let components = URLComponents(string: base),
              components.scheme?.lowercased() == requiredScheme,
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return requiredScheme == "wss"
                ? UIStrings.secureWebSocketRequired
                : UIStrings.secureHTTPRequired
        }

        guard let path = trimmedOptional(path),
              path.hasPrefix("/"),
              !path.hasPrefix("//"),
              !path.contains("://"),
              !path.contains("?"),
              !path.contains("#"),
              !path.contains("\\") else {
            return UIStrings.endpointPathInvalid
        }
        return nil
    }
}

struct TranscriptionProviderPreset: Identifiable, Equatable {
    let id: String
    let displayName: String
    let adapterID: TranscriptionAdapterID
    let defaults: TranscriptionConnection

    func applying(to connection: TranscriptionConnection) -> TranscriptionConnection {
        guard connection.adapterID == adapterID else { return connection }
        var applied = defaults
        applied.id = connection.id
        applied.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? displayName
            : connection.name
        applied.authentication.apiKeyReference = connection.authentication.apiKeyReference
        applied.credentialRevision = connection.credentialRevision
        applied.lastConnectionTest = nil
        return applied.normalizedForProtocol()
    }

    static let catalog: [TranscriptionProviderPreset] = TranscriptionConnection.defaultProviders.map {
        var defaults = $0
        defaults.authentication.apiKeyReference = nil
        defaults.credentialRevision = 0
        defaults.lastConnectionTest = nil
        return TranscriptionProviderPreset(
            id: $0.adapterID.rawValue,
            displayName: $0.name,
            adapterID: $0.adapterID,
            defaults: defaults
        )
    }

    static func defaultPreset(for adapterID: TranscriptionAdapterID) -> TranscriptionProviderPreset? {
        catalog.first { $0.adapterID == adapterID }
    }
}

// Exact v1/v2 persistence bridge. Canonical v3 encoding never writes these fields.
struct LegacySpeechProviderConfig: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: SpeechProviderKind
    var wireProtocol: SpeechProviderWireProtocol?
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
    var resourceID: String?
    var modelName: String?
    var customEndpointApproved: Bool?

    init(_ connection: TranscriptionConnection) {
        id = connection.id
        name = connection.name
        kind = connection.kind
        wireProtocol = connection.resolvedWireProtocol
        model = connection.model
        language = connection.language
        apiKeyReference = connection.apiKeyReference
        baseURL = connection.baseURL
        endpointPath = connection.endpointPath
        realtimeURL = connection.realtimeURL
        realtimePath = connection.realtimePath
        inputAudioFormat = connection.inputAudioFormat
        sampleRate = connection.sampleRate
        channels = connection.channels
        prompt = connection.prompt
        temperature = connection.temperature
        enableServerVAD = connection.enableServerVAD
        resourceID = connection.resourceID
        modelName = connection.modelName
        customEndpointApproved = connection.customEndpointApproved
    }

    func migratedConnection() -> TranscriptionConnection {
        let resolvedProtocol: SpeechProviderWireProtocol
        if let wireProtocol {
            resolvedProtocol = wireProtocol
        } else {
            switch kind {
            case .appleSpeechLive: resolvedProtocol = .appleSpeech
            case .openAIRealtimeTranscription: resolvedProtocol = .openAIRealtime
            case .openAIHTTPTranscription: resolvedProtocol = .openAIHTTP
            }
        }

        let adapterID = resolvedProtocol.adapterID
        let schema = adapterID.schema
        let endpoint: TranscriptionEndpoint?
        switch schema.endpointStyle {
        case .none:
            endpoint = nil
        case .secureHTTP:
            endpoint = TranscriptionEndpoint(
                baseURL: baseURL,
                path: endpointPath,
                customEndpointApproved: customEndpointApproved
            )
        case .secureWebSocket:
            endpoint = TranscriptionEndpoint(
                baseURL: realtimeURL ?? "",
                path: realtimePath ?? "",
                customEndpointApproved: customEndpointApproved
            )
        }

        let migratedModel: String?
        if adapterID == .openAIRealtimeTranscriptionGA,
           model == "gpt-4o-mini-transcribe" {
            migratedModel = schema.defaultModel
        } else if adapterID == .volcengineBigASRWSV3 {
            migratedModel = nil
        } else {
            migratedModel = trimmedOptional(model)
        }

        return TranscriptionConnection(
            id: id,
            name: name,
            adapterID: adapterID,
            endpoint: endpoint,
            model: migratedModel,
            language: language,
            authentication: TranscriptionAuthentication(
                type: schema.authenticationType,
                apiKeyReference: apiKeyReference
            ),
            audio: TranscriptionAudioConfiguration(
                format: inputAudioFormat,
                sampleRate: sampleRate,
                channels: channels
            ),
            options: TranscriptionConnectionOptions(
                prompt: prompt,
                temperature: temperature,
                responseMode: schema.responseMode,
                resourceID: resourceID,
                modelName: modelName,
                twoPassRecognition: schema.supportsVolcengineTwoPass ? enableServerVAD : nil
            )
        ).normalizedForProtocol()
    }
}

private func nonEmpty(_ value: String?) -> String? {
    trimmedOptional(value)
}

private func trimmedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func trimTrailingSlashes(_ value: String) -> String {
    var result = value
    while result.count > 1, result.hasSuffix("/") {
        result.removeLast()
    }
    return result
}

private func stableFingerprint(_ data: Data) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}
