import AVFoundation
import Foundation
import Speech

final class TranscriptionConnectionTester {
    typealias SecretLoader = (String) -> String?
    typealias LocalCapabilityProbe = (SpeechProviderConfig) async throws -> Void

    static let shared = TranscriptionConnectionTester()

    private let runtimeFactory: TranscriptionRuntimeFactory
    private let secretLoader: SecretLoader
    private let localCapabilityProbe: LocalCapabilityProbe

    init(
        runtimeFactory: TranscriptionRuntimeFactory = .shared,
        secretLoader: @escaping SecretLoader = { reference in
            SpeechProviderStore.shared.load(for: reference)
        },
        localCapabilityProbe: @escaping LocalCapabilityProbe = probeAppleConnectionCapability
    ) {
        self.runtimeFactory = runtimeFactory
        self.secretLoader = secretLoader
        self.localCapabilityProbe = localCapabilityProbe
    }

    func test(
        connection: SpeechProviderConfig,
        apiKey explicitAPIKey: String?
    ) async throws -> TranscriptionConnectionTestRecord {
        let normalized = connection.normalizedForProtocol()
        if let validationError = normalized.configurationValidationError() {
            throw makeError(validationError)
        }

        var resolvedSecret: String?
        do {
            let requiresAPIKey = try runtimeFactory.requiresAPIKey(for: normalized)
            let apiKey = try resolveAPIKey(
                connection: normalized,
                explicitAPIKey: explicitAPIKey,
                required: requiresAPIKey
            )
            resolvedSecret = apiKey
            let runtime = try runtimeFactory.makeRuntime(
                connection: normalized,
                apiKey: apiKey,
                fallbackLocaleIdentifier: normalized.language ?? "zh-CN"
            )
            defer { runtime.cancel() }

            try await withTaskCancellationHandler(operation: {
                switch runtime {
                case .ownedCapture:
                    try await localCapabilityProbe(normalized)
                case .recordedFile(let transcriber, let audio):
                    let fixture = try GeneratedConnectionTestAudio.make(
                        sampleRate: audio.sampleRate,
                        recordedFormat: audio.format
                    )
                    defer { fixture.removeTemporaryFile() }
                    _ = try await transcriber.transcribeFile(fixture.fileURL)
                case .pcmStream(let transcriber, let audio):
                    let fixture = try GeneratedConnectionTestAudio.make(
                        sampleRate: audio.sampleRate
                    )
                    defer { fixture.removeTemporaryFile() }
                    try await transcriber.start()
                    for chunk in fixture.rawPCMChunks {
                        try Task.checkCancellation()
                        try await transcriber.appendAudio(chunk)
                    }
                    _ = try await transcriber.stop()
                }
            }, onCancel: {
                runtime.cancel()
            })

            return TranscriptionConnectionTestRecord(
                adapterVersion: normalized.protocolSchema.adapterVersion,
                outcome: .succeeded,
                safeSummary: UIStrings.localized(
                    english: "Connection, audio transport, and response structure test succeeded.",
                    simplifiedChinese: "连接、音频传输与响应结构测试成功。"
                ),
                configurationFingerprint: normalized.connectionTestFingerprint
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw makeError(
                sanitizedErrorSummary(
                    error.localizedDescription,
                    redacting: [resolvedSecret, explicitAPIKey].compactMap { $0 }
                )
            )
        }
    }

    private func resolveAPIKey(
        connection: SpeechProviderConfig,
        explicitAPIKey: String?,
        required: Bool
    ) throws -> String? {
        guard required else { return nil }

        let candidate: String
        if let explicitAPIKey {
            candidate = explicitAPIKey
        } else if let reference = connection.apiKeyReference {
            candidate = secretLoader(reference) ?? ""
        } else {
            candidate = ""
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionAdapterRegistryError.missingAPIKey
        }
        return trimmed
    }

}

private func probeAppleConnectionCapability(
    connection: SpeechProviderConfig
) async throws {
    try Task.checkCancellation()
    let localeIdentifier = connection.language?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let locale = Locale(
        identifier: localeIdentifier?.isEmpty == false ? localeIdentifier! : "zh-CN"
    )
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
        throw makeError(
            UIStrings.localized(
                english: "Apple Speech recognition is unavailable for the selected language.",
                simplifiedChinese: "当前语言的 Apple 语音识别不可用。"
            )
        )
    }
    guard recognizer.supportsOnDeviceRecognition else {
        throw makeError(
            UIStrings.localized(
                english: "The selected language does not support on-device Apple Speech recognition.",
                simplifiedChinese: "当前语言不支持 Apple 设备端语音识别。"
            )
        )
    }
}

private struct GeneratedConnectionTestAudio {
    let fileURL: URL
    let rawPCMChunks: [Data]

    static func make(sampleRate: Int) throws -> GeneratedConnectionTestAudio {
        try make(sampleRate: sampleRate, recordedFormat: .wav)
    }

    static func make(
        sampleRate: Int,
        recordedFormat: RecordedAudioFormat
    ) throws -> GeneratedConnectionTestAudio {
        guard sampleRate == 16_000 || sampleRate == 24_000 else {
            throw makeError(
                UIStrings.localized(
                    english: "Connection test audio supports only 16000 or 24000 Hz.",
                    simplifiedChinese: "连接测试音频仅支持 16000 或 24000 Hz。"
                )
            )
        }

        let durationSeconds = 0.8
        let frameCount = Int(Double(sampleRate) * durationSeconds)
        var pcm = Data(capacity: frameCount * MemoryLayout<Int16>.size)

        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            let progress = Double(frame) / Double(max(1, frameCount - 1))
            let envelope = min(1, progress * 18) * min(1, (1 - progress) * 18)
            let changingFundamental = 170 + 45 * sin(2 * .pi * 2.2 * time)
            let sample = (
                sin(2 * .pi * changingFundamental * time)
                    + 0.42 * sin(2 * .pi * changingFundamental * 2 * time)
                    + 0.18 * sin(2 * .pi * changingFundamental * 3 * time)
            ) * envelope * 0.32
            var integer = Int16(max(-1, min(1, sample)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &integer) { pcm.append(contentsOf: $0) }
        }

        FlotisTemporaryFiles.removeStaleFiles(withPrefix: FlotisTemporaryFiles.audioPrefix)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            FlotisTemporaryFiles.audioPrefix
                + "Connection-Test-\(UUID().uuidString).\(recordedFormat.fileExtension)"
        )
        do {
            switch recordedFormat {
            case .wav:
                try makePCM16WAV(pcm: pcm, sampleRate: sampleRate)
                    .write(to: url, options: .atomic)
            case .m4a:
                try writeM4A(pcm: pcm, sampleRate: sampleRate, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        let chunkByteCount = max(2, sampleRate / 10 * MemoryLayout<Int16>.size)
        var chunks: [Data] = []
        var offset = 0
        while offset < pcm.count {
            let end = min(pcm.count, offset + chunkByteCount)
            chunks.append(pcm.subdata(in: offset..<end))
            offset = end
        }
        return GeneratedConnectionTestAudio(fileURL: url, rawPCMChunks: chunks)
    }

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func makePCM16WAV(pcm: Data, sampleRate: Int) -> Data {
        var result = Data()
        result.append(contentsOf: Data("RIFF".utf8))
        result.appendLittleEndian(UInt32(36 + pcm.count))
        result.append(contentsOf: Data("WAVE".utf8))
        result.append(contentsOf: Data("fmt ".utf8))
        result.appendLittleEndian(UInt32(16))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(UInt32(sampleRate))
        result.appendLittleEndian(UInt32(sampleRate * 2))
        result.appendLittleEndian(UInt16(2))
        result.appendLittleEndian(UInt16(16))
        result.append(contentsOf: Data("data".utf8))
        result.appendLittleEndian(UInt32(pcm.count))
        result.append(pcm)
        return result
    }

    private static func writeM4A(pcm: Data, sampleRate: Int, to url: URL) throws {
        let file = try AVAudioFile(
            forWriting: url,
            settings: RecordedAudioFormat.m4a.settings(sampleRate: sampleRate, channels: 1),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frameCount = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ), let channel = buffer.floatChannelData?[0] else {
            throw makeError(
                UIStrings.localized(
                    english: "Could not create the M4A connection test audio.",
                    simplifiedChinese: "无法创建 M4A 连接测试音频。"
                )
            )
        }
        buffer.frameLength = frameCount
        pcm.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for frame in 0..<Int(frameCount) {
                channel[frame] = Float(Int16(littleEndian: samples[frame])) / Float(Int16.max)
            }
        }
        try file.write(from: buffer)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func sanitizedErrorSummary(_ message: String, redacting secrets: [String]) -> String {
    let data = Data(message.utf8)
    return safeLimitedResponseText(data, redacting: secrets)
        ?? UIStrings.localized(
            english: "Connection test failed.",
            simplifiedChinese: "连接测试失败。"
        )
}

private func makeError(_ message: String) -> NSError {
    NSError(
        domain: "TranscriptionConnectionTester",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}
