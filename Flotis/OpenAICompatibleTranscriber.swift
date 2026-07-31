import Foundation
import AVFoundation

let maximumTranscriptionUploadBytes = 25 * 1_024 * 1_024

protocol HTTPTranscriptionUploading: AnyObject {
    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, URLResponse)
    func cancel()
}

final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirectSessionDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Do not replay an Authorization-bearing multipart upload to a redirect target.
        // The caller receives the original 3xx and can surface a configuration error.
        completionHandler(nil)
    }
}

final class URLSessionHTTPTranscriptionTransport: HTTPTranscriptionUploading {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        session = URLSession(
            configuration: configuration,
            delegate: NoRedirectSessionDelegate.shared,
            delegateQueue: nil
        )
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, URLResponse) {
        try await session.upload(for: request, fromFile: fileURL)
    }

    func cancel() {
        session.invalidateAndCancel()
    }
}

private final class ActiveHTTPUploadTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var active: (token: UUID, transport: HTTPTranscriptionUploading)?

    func install(_ transport: HTTPTranscriptionUploading) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard active == nil else { return nil }
        let token = UUID()
        active = (token, transport)
        return token
    }

    func finish(token: UUID) {
        let transport: HTTPTranscriptionUploading?
        lock.lock()
        if active?.token == token {
            transport = active?.transport
            active = nil
        } else {
            transport = nil
        }
        lock.unlock()
        transport?.cancel()
    }

    func isActive(token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active?.token == token
    }

    func cancel(token: UUID? = nil) {
        let transport: HTTPTranscriptionUploading?
        lock.lock()
        if token == nil || active?.token == token {
            transport = active?.transport
            active = nil
        } else {
            transport = nil
        }
        lock.unlock()
        transport?.cancel()
    }
}

private final class ActiveHTTPSession: @unchecked Sendable {
    private let lock = NSLock()
    private var active: (token: UUID, session: URLSession)?

    func install(_ session: URLSession) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard active == nil else { return nil }
        let token = UUID()
        active = (token, session)
        return token
    }

    func finish(token: UUID) {
        let session: URLSession?
        lock.lock()
        if active?.token == token {
            session = active?.session
            active = nil
        } else {
            session = nil
        }
        lock.unlock()
        // The request has either produced its terminal response or is unwinding.
        // Cancel invalidation also closes an SSE connection that sent [DONE] without EOF.
        session?.invalidateAndCancel()
    }

    func isActive(token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active?.token == token
    }

    func cancel(token: UUID? = nil) {
        let session: URLSession?
        lock.lock()
        if token == nil || active?.token == token {
            session = active?.session
            active = nil
        } else {
            session = nil
        }
        lock.unlock()
        session?.invalidateAndCancel()
    }
}

private struct MultipartBodyFile {
    let url: URL
    let boundary: String
    let byteCount: Int

    static func create(
        fields: [(name: String, value: String)],
        fileURL: URL,
        mimeType: String
    ) throws -> MultipartBodyFile {
        FlotisTemporaryFiles.removeStaleFiles(withPrefix: FlotisTemporaryFiles.multipartPrefix)

        let boundary = "FlotisBoundary-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            FlotisTemporaryFiles.multipartPrefix + UUID().uuidString + ".body"
        )

        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw makeHTTPError(
                domain: "MultipartBodyFile",
                code: 1,
                message: UIStrings.localized(
                    english: "Could not create the temporary transcription upload file.",
                    simplifiedChinese: "无法创建转写上传临时文件。"
                )
            )
        }

        do {
            let output = try FileHandle(forWritingTo: bodyURL)
            defer { try? output.close() }

            for field in fields {
                try Task.checkCancellation()
                let safeName = sanitizedHeaderValue(field.name)
                try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
                try output.write(contentsOf: Data(
                    "Content-Disposition: form-data; name=\"\(safeName)\"\r\n\r\n".utf8
                ))
                try output.write(contentsOf: Data(field.value.utf8))
                try output.write(contentsOf: Data("\r\n".utf8))
            }

            let safeFilename = sanitizedHeaderValue(fileURL.lastPathComponent)
            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try output.write(contentsOf: Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n".utf8
            ))
            try output.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: 256 * 1_024), !chunk.isEmpty else {
                    break
                }
                try output.write(contentsOf: chunk)
            }

            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }

        let byteCount = (try? bodyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount > 0 else {
            try? FileManager.default.removeItem(at: bodyURL)
            throw makeHTTPError(
                domain: "MultipartBodyFile",
                code: 2,
                message: UIStrings.localized(
                    english: "The temporary transcription upload file is empty.",
                    simplifiedChinese: "转写上传临时文件为空。"
                )
            )
        }
        return MultipartBodyFile(url: bodyURL, boundary: boundary, byteCount: byteCount)
    }

    private static func sanitizedHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
    }
}

private enum HTTPTranscriptionSupport {
    static func endpointURL(
        baseURL: String,
        endpointPath: String,
        errorDomain: String
    ) throws -> URL {
        let trimmedPath = endpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("//"),
              !trimmedPath.contains("?"),
              !trimmedPath.contains("#"),
              !trimmedPath.contains("\\"),
              URL(string: trimmedPath)?.scheme == nil,
              var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw makeHTTPError(
                domain: errorDomain,
                code: 1,
                message: UIStrings.localized(
                    english: "The transcription URL must be a valid https:// address without embedded credentials.",
                    simplifiedChinese: "转写地址必须是有效且不含凭据的 https:// 地址。"
                )
            )
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw makeHTTPError(
                domain: errorDomain,
                code: 1,
                message: UIStrings.localized(
                    english: "The base URL or endpoint path is invalid.",
                    simplifiedChinese: "基础地址或接口路径非法。"
                )
            )
        }
        return url
    }

    static func validateFile(
        _ fileURL: URL,
        allowedExtensions: Set<String>,
        maximumBytes: Int,
        maximumDuration: TimeInterval? = nil,
        errorDomain: String
    ) async throws {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let standardizedURL = fileURL.standardizedFileURL
        let values = try standardizedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard standardizedURL.isFileURL,
              values.isRegularFile == true,
              fileManager.isReadableFile(atPath: standardizedURL.path),
              fileSize > 0 else {
            throw makeHTTPError(
                domain: errorDomain,
                code: 5,
                message: UIStrings.localized(
                    english: "The audio file to transcribe is missing, empty, or unreadable.",
                    simplifiedChinese: "待转写音频文件不存在、为空或不可读。"
                )
            )
        }
        guard fileSize <= maximumBytes else {
            throw makeHTTPError(
                domain: errorDomain,
                code: 6,
                message: UIStrings.localized(
                    english: "The audio file exceeds the \(maximumBytes / 1_024 / 1_024) MB upload limit.",
                    simplifiedChinese: "音频文件超过 \(maximumBytes / 1_024 / 1_024) MB 上传限制。"
                )
            )
        }

        let fileExtension = standardizedURL.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else {
            let formats = allowedExtensions.sorted().joined(separator: "/")
            throw makeHTTPError(
                domain: errorDomain,
                code: 7,
                message: UIStrings.localized(
                    english: "This audio format is not supported. Use \(formats).",
                    simplifiedChinese: "音频格式不受支持；请使用 \(formats)。"
                )
            )
        }

        if let maximumDuration {
            let duration = try await AVURLAsset(url: standardizedURL).load(.duration).seconds
            guard duration.isFinite, duration > 0, duration <= maximumDuration else {
                throw makeHTTPError(
                    domain: errorDomain,
                    code: 8,
                    message: UIStrings.localized(
                        english: "Audio duration must be greater than 0 and no longer than \(Int(maximumDuration)) seconds.",
                        simplifiedChinese: "音频时长必须大于 0 且不超过 \(Int(maximumDuration)) 秒。"
                    )
                )
            }
        }
        try Task.checkCancellation()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        return URLSession(
            configuration: configuration,
            delegate: NoRedirectSessionDelegate.shared,
            delegateQueue: nil
        )
    }

    static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3", "mpeg", "mpga": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "flac": return "audio/flac"
        case "ogg", "oga": return "audio/ogg"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }
}

final class OpenAIHTTPTranscriber: FileSpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)?

    private let config: SpeechProviderConfig
    private let apiKey: String
    private let transportFactory: () -> HTTPTranscriptionUploading
    private let activeTransport = ActiveHTTPUploadTransport()

    init(
        config: SpeechProviderConfig,
        apiKey: String,
        transportFactory: @escaping () -> HTTPTranscriptionUploading = {
            URLSessionHTTPTranscriptionTransport()
        }
    ) {
        self.config = config
        self.apiKey = apiKey
        self.transportFactory = transportFactory
    }

    func transcribeFile(_ fileURL: URL) async throws -> String {
        let errorDomain = "OpenAIHTTPTranscriber"
        let endpointURL = try HTTPTranscriptionSupport.endpointURL(
            baseURL: config.baseURL,
            endpointPath: config.endpointPath,
            errorDomain: errorDomain
        )

        // Install the cancellable transport before file inspection/body construction so
        // concrete cancel() also invalidates work requested during those phases.
        let transport = transportFactory()
        guard let token = activeTransport.install(transport) else {
            transport.cancel()
            throw makeHTTPError(
                domain: errorDomain,
                code: 9,
                message: UIStrings.localized(
                    english: "A file transcription request is already in progress.",
                    simplifiedChinese: "已有文件转写请求正在进行。"
                )
            )
        }
        defer { activeTransport.finish(token: token) }

        try await HTTPTranscriptionSupport.validateFile(
            fileURL,
            allowedExtensions: ["flac", "m4a", "mp3", "mp4", "mpeg", "mpga", "ogg", "wav", "webm"],
            maximumBytes: maximumTranscriptionUploadBytes,
            errorDomain: errorDomain
        )
        guard activeTransport.isActive(token: token) else { throw CancellationError() }

        var fields = [(name: "model", value: config.model)]
        if let language = config.language, !language.isEmpty {
            fields.append(("language", language))
        }
        if let prompt = config.prompt, !prompt.isEmpty {
            fields.append(("prompt", prompt))
        }
        if let temperature = config.temperature {
            fields.append(("temperature", "\(temperature)"))
        }
        fields.append(("response_format", "json"))

        let body = try MultipartBodyFile.create(
            fields: fields,
            fileURL: fileURL,
            mimeType: HTTPTranscriptionSupport.mimeType(for: fileURL)
        )
        defer { try? FileManager.default.removeItem(at: body.url) }
        guard activeTransport.isActive(token: token) else { throw CancellationError() }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.byteCount)", forHTTPHeaderField: "Content-Length")

        try Task.checkCancellation()
        do {
            return try await withTaskCancellationHandler(operation: {
                let (data, response) = try await transport.upload(for: request, fromFile: body.url)
                try Task.checkCancellation()
                let httpResponse = try validatedHTTPResponse(
                    response,
                    errorDomain: errorDomain
                )
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw makeHTTPError(
                        domain: errorDomain,
                        code: httpResponse.statusCode,
                        message: safeLimitedResponseText(data, redacting: [apiKey])
                            ?? "HTTP \(httpResponse.statusCode)"
                    )
                }

                guard responseMediaType(httpResponse) == "application/json" else {
                    throw makeHTTPError(
                        domain: errorDomain,
                        code: 11,
                        message: UIStrings.localized(
                            english: "The transcription response Content-Type must be application/json.",
                            simplifiedChinese: "转写响应 Content-Type 必须是 application/json。"
                        )
                    )
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw makeHTTPError(
                        domain: errorDomain,
                        code: 3,
                        message: UIStrings.localized(
                            english: "Could not parse the transcription response JSON.",
                            simplifiedChinese: "转写响应 JSON 解析失败。"
                        )
                    )
                }
                if let text = json["text"] as? String { return text }
                throw makeHTTPError(
                    domain: errorDomain,
                    code: 4,
                    message: UIStrings.localized(
                        english: "The transcription response does not contain a text field.",
                        simplifiedChinese: "转写响应中没有找到 text 字段。"
                    )
                )
            }, onCancel: {
                self.activeTransport.cancel(token: token)
            })
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    func cancel() {
        activeTransport.cancel()
    }
}

typealias OpenAICompatibleTranscriber = OpenAIHTTPTranscriber

final class GLMASRHTTPTranscriber: FileSpeechTranscribing {
    private let handlerLock = NSLock()
    private var storedPartialTranscriptHandler: ((String) -> Void)?
    var partialTranscriptHandler: ((String) -> Void)? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return storedPartialTranscriptHandler
        }
        set {
            handlerLock.lock()
            storedPartialTranscriptHandler = newValue
            handlerLock.unlock()
        }
    }

    private let config: SpeechProviderConfig
    private let apiKey: String
    private let sessions = ActiveHTTPSession()

    init(config: SpeechProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    func transcribeFile(_ fileURL: URL) async throws -> String {
        let errorDomain = "GLMASRHTTPTranscriber"
        let endpointURL = try HTTPTranscriptionSupport.endpointURL(
            baseURL: config.baseURL,
            endpointPath: config.endpointPath,
            errorDomain: errorDomain
        )

        let session = HTTPTranscriptionSupport.makeSession()
        guard let token = sessions.install(session) else {
            session.invalidateAndCancel()
            throw makeHTTPError(
                domain: errorDomain,
                code: 9,
                message: UIStrings.localized(
                    english: "A file transcription request is already in progress.",
                    simplifiedChinese: "已有文件转写请求正在进行。"
                )
            )
        }
        defer { sessions.finish(token: token) }

        try await HTTPTranscriptionSupport.validateFile(
            fileURL,
            allowedExtensions: ["mp3", "wav"],
            maximumBytes: maximumTranscriptionUploadBytes,
            maximumDuration: 30,
            errorDomain: errorDomain
        )
        guard sessions.isActive(token: token) else { throw CancellationError() }

        var fields = [
            (name: "model", value: config.model),
            (name: "stream", value: "true")
        ]
        if let prompt = config.prompt, !prompt.isEmpty {
            fields.append(("prompt", prompt))
        }

        let body = try MultipartBodyFile.create(
            fields: fields,
            fileURL: fileURL,
            mimeType: HTTPTranscriptionSupport.mimeType(for: fileURL)
        )
        defer { try? FileManager.default.removeItem(at: body.url) }
        guard sessions.isActive(token: token) else { throw CancellationError() }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("\(body.byteCount)", forHTTPHeaderField: "Content-Length")
        guard let bodyStream = InputStream(url: body.url) else {
            throw makeHTTPError(
                domain: errorDomain,
                code: 10,
                message: UIStrings.localized(
                    english: "Could not open the temporary transcription upload file.",
                    simplifiedChinese: "无法打开转写上传临时文件。"
                )
            )
        }
        request.httpBodyStream = bodyStream

        try Task.checkCancellation()
        do {
            return try await withTaskCancellationHandler(operation: {
                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw makeHTTPError(
                        domain: errorDomain,
                        code: 2,
                        message: UIStrings.localized(
                            english: "The network response is invalid.",
                            simplifiedChinese: "网络响应无效。"
                        )
                    )
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    var errorText = ""
                    for try await line in bytes.lines {
                        if errorText.utf8.count >= 8_192 { break }
                        let remainingCharacters = max(0, 8_192 - errorText.count)
                        errorText += String(line.prefix(remainingCharacters)) + "\n"
                    }
                    throw makeHTTPError(
                        domain: errorDomain,
                        code: httpResponse.statusCode,
                        message: safeLimitedResponseText(Data(errorText.utf8), redacting: [apiKey])
                            ?? "HTTP \(httpResponse.statusCode)"
                    )
                }

                try validateGLMSSEContentType(httpResponse)

                var parser = GLMSSEAccumulator(redacting: [apiKey])

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    if let partial = try parser.consume(line: line) {
                        self.emitPartial(partial)
                    }
                    if parser.receivedDone { break }
                }

                return try parser.finish()
            }, onCancel: {
                self.sessions.cancel(token: token)
            })
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    func cancel() {
        sessions.cancel()
    }

    private func emitPartial(_ text: String) {
        let handler = partialTranscriptHandler
        handler?(text)
    }

}

struct GLMSSEAccumulator {
    private(set) var receivedDone = false
    private var accumulated = ""
    private var finalTranscript = ""
    private let redactedSecrets: [String]

    init(redacting secrets: [String] = []) {
        redactedSecrets = secrets
    }

    mutating func consume(line: String) throws -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = String(trimmed.dropFirst("data:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" {
            receivedDone = true
            return nil
        }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw makeHTTPError(
                domain: "GLMASRHTTPTranscriber",
                code: 13,
                message: UIStrings.localized(
                    english: "The GLM-ASR SSE data event is not valid JSON.",
                    simplifiedChinese: "GLM-ASR SSE data 事件不是有效 JSON。"
                )
            )
        }
        if let error = glmSSEError(from: json) {
            throw makeHTTPError(
                domain: "GLMASRHTTPTranscriber",
                code: 3,
                message: safeLimitedResponseText(
                    Data(error.utf8),
                    redacting: redactedSecrets
                )
                    ?? UIStrings.localized(
                        english: "GLM-ASR returned a protocol error.",
                        simplifiedChinese: "GLM-ASR 返回协议错误。"
                    )
            )
        }

        switch json["type"] as? String ?? "" {
        case "transcript.text.delta":
            guard let delta = json["delta"] as? String else {
                throw makeHTTPError(
                    domain: "GLMASRHTTPTranscriber",
                    code: 14,
                    message: UIStrings.localized(
                        english: "The GLM-ASR delta event is missing the delta field.",
                        simplifiedChinese: "GLM-ASR delta 事件缺少 delta 字段。"
                    )
                )
            }
            accumulated += delta
            return accumulated
        case "transcript.text.done":
            finalTranscript = (json["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? accumulated
            return finalTranscript
        default:
            return nil
        }
    }

    func finish() throws -> String {
        guard receivedDone else {
            throw makeHTTPError(
                domain: "GLMASRHTTPTranscriber",
                code: 12,
                message: UIStrings.localized(
                    english: "The GLM-ASR SSE response did not receive the final [DONE] event.",
                    simplifiedChinese: "GLM-ASR SSE 响应未收到 [DONE] 终态。"
                )
            )
        }
        if !finalTranscript.isEmpty { return finalTranscript }
        if !accumulated.isEmpty { return accumulated }
        return ""
    }
}

func validateGLMSSEContentType(_ response: HTTPURLResponse) throws {
    guard responseMediaType(response) == "text/event-stream" else {
        throw makeHTTPError(
            domain: "GLMASRHTTPTranscriber",
            code: 11,
            message: UIStrings.localized(
                english: "The GLM-ASR response Content-Type must be text/event-stream.",
                simplifiedChinese: "GLM-ASR 响应 Content-Type 必须是 text/event-stream。"
            )
        )
    }
}

private func glmSSEError(from json: [String: Any]) -> String? {
    if let error = json["error"] as? [String: Any] {
        if let message = error["message"] as? String { return message }
        if let code = error["code"] as? String { return code }
    }
    return json["error"] as? String
}

private func validatedHTTPResponse(
    _ response: URLResponse,
    errorDomain: String
) throws -> HTTPURLResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw makeHTTPError(
            domain: errorDomain,
            code: 2,
            message: UIStrings.localized(
                english: "The network response is invalid.",
                simplifiedChinese: "网络响应无效。"
            )
        )
    }
    return httpResponse
}

func responseMediaType(_ response: HTTPURLResponse) -> String? {
    response.value(forHTTPHeaderField: "Content-Type")?
        .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

func safeLimitedResponseText(_ data: Data, redacting secrets: [String] = []) -> String? {
    let prefix = data.prefix(8_192)
    guard !prefix.isEmpty else { return nil }

    let candidate: String
    if let object = try? JSONSerialization.jsonObject(with: prefix) as? [String: Any],
       let error = object["error"] as? [String: Any],
       let message = error["message"] as? String {
        candidate = message
    } else if let object = try? JSONSerialization.jsonObject(with: prefix) as? [String: Any],
              let message = object["message"] as? String {
        candidate = message
    } else {
        candidate = String(data: prefix, encoding: .utf8) ?? ""
    }

    var sanitized = redactExactSecrets(candidate, secrets: secrets)
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let redactionPatterns = [
        "(?i)bearer\\s+[^\\s,;]+",
        "(?i)(authorization|api[-_ ]?key|x-api-key)\\s*[:=]\\s*[^\\s,;]+",
        "(?i)sk-[a-z0-9_-]+"
    ]
    for pattern in redactionPatterns {
        sanitized = sanitized.replacingOccurrences(
            of: pattern,
            with: "[redacted]",
            options: .regularExpression
        )
    }
    let limited = String(sanitized.prefix(240))
    return limited.isEmpty ? nil : limited
}

private func redactExactSecrets(_ text: String, secrets: [String]) -> String {
    var result = text
    for rawSecret in secrets {
        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { continue }
        result = result.replacingOccurrences(of: secret, with: "[redacted]")

        // Upstream code may already have bounded an error in the middle of a long
        // opaque key. Redact a matching key prefix as well, without relying on a
        // provider-specific `sk-` shape.
        guard secret.count >= 8 else { continue }
        let maximumPrefixLength = min(secret.count, 240)
        for length in stride(from: maximumPrefixLength, through: 8, by: -1) {
            let prefix = String(secret.prefix(length))
            if result.contains(prefix) {
                result = result.replacingOccurrences(of: prefix, with: "[redacted]")
                break
            }
        }
    }
    return result
}

private func makeHTTPError(domain: String, code: Int, message: String) -> NSError {
    NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
}
