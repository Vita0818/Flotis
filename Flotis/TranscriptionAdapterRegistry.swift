import Foundation

enum TranscriptionRuntimeKind: String, Equatable {
    case ownedCapture
    case pcmStream
    case recordedFile
}

struct PCMStreamRuntimeConfiguration: Equatable {
    let sampleRate: Int
    let channels: Int
    let bufferCapacity: Int
}

struct RecordedFileRuntimeConfiguration: Equatable {
    let format: RecordedAudioFormat
    let sampleRate: Int
    let channels: Int
    let maximumRecordingDurationSeconds: Int?
    let stopLeadSeconds: Int
    let maximumUploadBytes: Int?
}

enum TranscriptionRuntimePlan {
    case ownedCapture(
        transcriber: StreamingSpeechTranscribing,
        automaticallyStopsOnFinal: Bool
    )
    case pcmStream(
        transcriber: StreamingSpeechTranscribing,
        audio: PCMStreamRuntimeConfiguration
    )
    case recordedFile(
        transcriber: FileSpeechTranscribing,
        audio: RecordedFileRuntimeConfiguration
    )

    var kind: TranscriptionRuntimeKind {
        switch self {
        case .ownedCapture:
            return .ownedCapture
        case .pcmStream:
            return .pcmStream
        case .recordedFile:
            return .recordedFile
        }
    }

    func cancel() {
        switch self {
        case .ownedCapture(let transcriber, _), .pcmStream(let transcriber, _):
            transcriber.cancel()
        case .recordedFile(let transcriber, _):
            transcriber.cancel()
        }
    }
}

struct TranscriptionAdapterDescriptor {
    let id: TranscriptionAdapterID
    let runtimeKind: TranscriptionRuntimeKind
    let requiresAPIKey: Bool
    let makeRuntime: (
        _ connection: SpeechProviderConfig,
        _ apiKey: String?,
        _ fallbackLocaleIdentifier: String
    ) throws -> TranscriptionRuntimePlan
}

enum TranscriptionAdapterRegistryError: LocalizedError, Equatable {
    case duplicateAdapter(TranscriptionAdapterID)
    case missingAdapter(TranscriptionAdapterID)
    case missingAPIKey
    case invalidRuntimeConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .duplicateAdapter(let id):
            return UIStrings.localized(
                english: "Duplicate transcription protocol adapter: \(id.rawValue).",
                simplifiedChinese: "重复的转写协议适配器：\(id.rawValue)。"
            )
        case .missingAdapter(let id):
            return UIStrings.localized(
                english: "This version does not support the transcription protocol: \(id.rawValue).",
                simplifiedChinese: "当前版本不支持转写协议：\(id.rawValue)。"
            )
        case .missingAPIKey:
            return UIStrings.localized(
                english: "Configure and save an API Key for this transcription connection first.",
                simplifiedChinese: "请先配置并保存该转写连接的 API Key。"
            )
        case .invalidRuntimeConfiguration(let message):
            return message
        }
    }
}

final class TranscriptionAdapterRegistry {
    static let shared: TranscriptionAdapterRegistry = {
        do {
            return try TranscriptionAdapterRegistry.live()
        } catch {
            preconditionFailure(
                UIStrings.localized(
                    english: "Could not create the transcription protocol registry: \(error.localizedDescription)",
                    simplifiedChinese: "无法创建转写协议 registry：\(error.localizedDescription)"
                )
            )
        }
    }()

    private let descriptorsByID: [TranscriptionAdapterID: TranscriptionAdapterDescriptor]

    init(descriptors: [TranscriptionAdapterDescriptor]) throws {
        var result: [TranscriptionAdapterID: TranscriptionAdapterDescriptor] = [:]
        for descriptor in descriptors {
            guard result[descriptor.id] == nil else {
                throw TranscriptionAdapterRegistryError.duplicateAdapter(descriptor.id)
            }
            result[descriptor.id] = descriptor
        }
        descriptorsByID = result
    }

    var registeredAdapterIDs: Set<TranscriptionAdapterID> {
        Set(descriptorsByID.keys)
    }

    func descriptor(for id: TranscriptionAdapterID) throws -> TranscriptionAdapterDescriptor {
        guard let descriptor = descriptorsByID[id] else {
            throw TranscriptionAdapterRegistryError.missingAdapter(id)
        }
        return descriptor
    }

    static func live(
        openAIHTTPTransportFactory: @escaping () -> HTTPTranscriptionUploading = {
            URLSessionHTTPTranscriptionTransport()
        },
        openAIRealtimeSocketFactory: @escaping RealtimeWebSocketFactory = liveRealtimeWebSocketFactory
    ) throws -> TranscriptionAdapterRegistry {
        try TranscriptionAdapterRegistry(descriptors: [
            TranscriptionAdapterDescriptor(
                id: .appleOnDevice,
                runtimeKind: .ownedCapture,
                requiresAPIKey: false
            ) { connection, _, fallbackLocaleIdentifier in
                let requestedLocale = connection.language?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let localeIdentifier = requestedLocale?.isEmpty == false
                    ? requestedLocale!
                    : fallbackLocaleIdentifier
                return .ownedCapture(
                    transcriber: AppleSpeechTranscriber(localeIdentifier: localeIdentifier),
                    automaticallyStopsOnFinal: true
                )
            },
            TranscriptionAdapterDescriptor(
                id: .openAIAudioTranscriptionsHTTPV1,
                runtimeKind: .recordedFile,
                requiresAPIKey: true
            ) { connection, apiKey, _ in
                let key = try requiredAPIKey(apiKey)
                let format = try recordedAudioFormat(connection.inputAudioFormat)
                return .recordedFile(
                    transcriber: OpenAIHTTPTranscriber(
                        config: connection,
                        apiKey: key,
                        transportFactory: openAIHTTPTransportFactory
                    ),
                    audio: RecordedFileRuntimeConfiguration(
                        format: format,
                        sampleRate: connection.sampleRate ?? 16_000,
                        channels: connection.channels ?? 1,
                        maximumRecordingDurationSeconds: connection.maximumRecordingDurationSeconds,
                        stopLeadSeconds: 0,
                        maximumUploadBytes: connection.maximumUploadBytes
                            ?? maximumTranscriptionUploadBytes
                    )
                )
            },
            TranscriptionAdapterDescriptor(
                id: .openAIRealtimeTranscriptionGA,
                runtimeKind: .pcmStream,
                requiresAPIKey: true
            ) { connection, apiKey, _ in
                let key = try requiredAPIKey(apiKey)
                return .pcmStream(
                    transcriber: OpenAIRealtimeTranscriber(
                        config: connection,
                        apiKey: key,
                        socketFactory: openAIRealtimeSocketFactory
                    ),
                    audio: PCMStreamRuntimeConfiguration(
                        sampleRate: connection.sampleRate ?? 24_000,
                        channels: connection.channels ?? 1,
                        bufferCapacity: 512
                    )
                )
            },
            TranscriptionAdapterDescriptor(
                id: .dashScopeParaformerWSV1,
                runtimeKind: .pcmStream,
                requiresAPIKey: true
            ) { connection, apiKey, _ in
                let key = try requiredAPIKey(apiKey)
                return .pcmStream(
                    transcriber: DashScopeParaformerRealtimeTranscriber(
                        config: connection,
                        apiKey: key
                    ),
                    audio: PCMStreamRuntimeConfiguration(
                        sampleRate: connection.sampleRate ?? 16_000,
                        channels: connection.channels ?? 1,
                        bufferCapacity: 512
                    )
                )
            },
            TranscriptionAdapterDescriptor(
                id: .volcengineBigASRWSV3,
                runtimeKind: .pcmStream,
                requiresAPIKey: true
            ) { connection, apiKey, _ in
                let key = try requiredAPIKey(apiKey)
                return .pcmStream(
                    transcriber: VolcengineBigASRRealtimeTranscriber(
                        config: connection,
                        apiKey: key
                    ),
                    audio: PCMStreamRuntimeConfiguration(
                        sampleRate: connection.sampleRate ?? 16_000,
                        channels: connection.channels ?? 1,
                        bufferCapacity: 512
                    )
                )
            },
            TranscriptionAdapterDescriptor(
                id: .glmASRHTTPSSEV4,
                runtimeKind: .recordedFile,
                requiresAPIKey: true
            ) { connection, apiKey, _ in
                let key = try requiredAPIKey(apiKey)
                return .recordedFile(
                    transcriber: GLMASRHTTPTranscriber(config: connection, apiKey: key),
                    audio: RecordedFileRuntimeConfiguration(
                        format: .wav,
                        sampleRate: connection.sampleRate ?? 16_000,
                        channels: connection.channels ?? 1,
                        maximumRecordingDurationSeconds: connection.maximumRecordingDurationSeconds,
                        stopLeadSeconds: 1,
                        maximumUploadBytes: connection.maximumUploadBytes
                    )
                )
            }
        ])
    }
}

struct TranscriptionRuntimeFactory {
    static let shared = TranscriptionRuntimeFactory(registry: .shared)

    let registry: TranscriptionAdapterRegistry

    func requiresAPIKey(for connection: SpeechProviderConfig) throws -> Bool {
        try registry.descriptor(for: connection.adapterID).requiresAPIKey
    }

    func makeRuntime(
        connection: SpeechProviderConfig,
        apiKey: String?,
        fallbackLocaleIdentifier: String
    ) throws -> TranscriptionRuntimePlan {
        let normalized = connection.normalizedForProtocol()
        if let validationError = normalized.configurationValidationError() {
            throw TranscriptionAdapterRegistryError.invalidRuntimeConfiguration(validationError)
        }
        let descriptor = try registry.descriptor(for: normalized.adapterID)
        if descriptor.requiresAPIKey {
            _ = try requiredAPIKey(apiKey)
        }
        return try descriptor.makeRuntime(normalized, apiKey, fallbackLocaleIdentifier)
    }
}

private func requiredAPIKey(_ apiKey: String?) throws -> String {
    let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
        throw TranscriptionAdapterRegistryError.missingAPIKey
    }
    return trimmed
}

private func recordedAudioFormat(_ value: String?) throws -> RecordedAudioFormat {
    switch value?.lowercased() ?? "wav" {
    case "wav":
        return .wav
    case "m4a", "mp4":
        return .m4a
    default:
        throw TranscriptionAdapterRegistryError.invalidRuntimeConfiguration(
            UIStrings.localized(
                english: "The current recorder does not support the selected file format.",
                simplifiedChinese: "当前录音器不支持所选文件格式。"
            )
        )
    }
}
