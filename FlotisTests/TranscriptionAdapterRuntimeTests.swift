import XCTest
@testable import Flotis

final class TranscriptionAdapterRuntimeTests: XCTestCase {
    func testLiveRegistryRegistersSixUniqueAdaptersAndRejectsDuplicate() throws {
        let registry = try TranscriptionAdapterRegistry.live()
        XCTAssertEqual(registry.registeredAdapterIDs, Set(TranscriptionAdapterID.allCases))
        XCTAssertEqual(registry.registeredAdapterIDs.count, 6)

        let descriptor = try registry.descriptor(for: .appleOnDevice)
        XCTAssertThrowsError(
            try TranscriptionAdapterRegistry(descriptors: [descriptor, descriptor])
        ) { error in
            XCTAssertEqual(
                error as? TranscriptionAdapterRegistryError,
                .duplicateAdapter(.appleOnDevice)
            )
        }
    }

    func testEveryAdapterBuildsOnlyItsDeclaredGenericRuntimePlan() throws {
        let factory = TranscriptionRuntimeFactory(registry: try .live())
        let expected: [TranscriptionAdapterID: TranscriptionRuntimeKind] = [
            .appleOnDevice: .ownedCapture,
            .openAIAudioTranscriptionsHTTPV1: .recordedFile,
            .openAIRealtimeTranscriptionGA: .pcmStream,
            .dashScopeParaformerWSV1: .pcmStream,
            .volcengineBigASRWSV3: .pcmStream,
            .glmASRHTTPSSEV4: .recordedFile
        ]

        for connection in TranscriptionConnection.defaultProviders {
            let plan = try factory.makeRuntime(
                connection: connection,
                apiKey: connection.protocolSchema.requiresAPIKey ? "unit-test-key" : nil,
                fallbackLocaleIdentifier: "zh-CN"
            )
            XCTAssertEqual(plan.kind, expected[connection.adapterID], connection.adapterID.rawValue)
            plan.cancel()
        }
    }

    func testOpenAIHTTPTesterBuildsStrictMultipartWAVRequest() async throws {
        let transport = FakeHTTPTransport(
            statusCode: 200,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: Data(#"{"text":"fixture accepted"}"#.utf8)
        )
        let tester = try makeTester(httpTransport: transport)
        let connection = SpeechProviderConfig.openAIHTTP

        let record = try await tester.test(
            connection: connection,
            apiKey: "unit-test-key"
        )

        XCTAssertEqual(record.outcome, .succeeded)
        XCTAssertEqual(record.adapterVersion, connection.protocolSchema.adapterVersion)
        XCTAssertEqual(record.configurationFingerprint, connection.connectionTestFingerprint)
        XCTAssertFalse(record.safeSummary.contains("fixture accepted"))
        XCTAssertFalse(record.safeSummary.contains("unit-test-key"))

        let captured = try XCTUnwrap(transport.captured)
        XCTAssertEqual(captured.request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(
            captured.request.value(forHTTPHeaderField: "Authorization"),
            "Bearer unit-test-key"
        )
        XCTAssertTrue(
            captured.request.value(forHTTPHeaderField: "Content-Type")?
                .hasPrefix("multipart/form-data; boundary=") == true
        )
        XCTAssertNotNil(captured.body.range(of: Data("RIFF".utf8)))

        let bodyText = String(decoding: captured.body, as: UTF8.self)
        XCTAssertTrue(bodyText.contains("name=\"file\""))
        XCTAssertTrue(bodyText.contains("filename=\""))
        XCTAssertTrue(bodyText.contains(".wav\""))
        XCTAssertTrue(bodyText.contains("Content-Type: audio/wav"))
        XCTAssertTrue(bodyText.contains("name=\"model\""))
        XCTAssertTrue(bodyText.contains("gpt-4o-mini-transcribe"))
        XCTAssertTrue(bodyText.contains("name=\"response_format\""))
        XCTAssertFalse(bodyText.contains("name=\"prompt\""))
        XCTAssertFalse(bodyText.contains("name=\"temperature\""))
    }

    func testSameHTTPAdapterKeepsCustomEndpointAndModelIsolated() async throws {
        let transport = FakeHTTPTransport(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"text":"custom accepted"}"#.utf8)
        )
        let tester = try makeTester(httpTransport: transport)
        var connection = SpeechProviderConfig.openAIHTTP
        connection.id = UUID()
        connection.name = "Internal ASR"
        connection.baseURL = "https://asr.example.com"
        connection.endpointPath = "/custom/transcribe"
        connection.model = "whisper-large-v3"
        connection.isCustomEndpointApproved = true
        connection = connection.normalizedForProtocol()

        _ = try await tester.test(connection: connection, apiKey: "second-key")

        let captured = try XCTUnwrap(transport.captured)
        XCTAssertEqual(captured.request.url?.absoluteString, "https://asr.example.com/custom/transcribe")
        XCTAssertEqual(
            captured.request.value(forHTTPHeaderField: "Authorization"),
            "Bearer second-key"
        )
        let bodyText = String(decoding: captured.body, as: UTF8.self)
        XCTAssertTrue(bodyText.contains("whisper-large-v3"))
        XCTAssertFalse(bodyText.contains("gpt-4o-mini-transcribe"))
    }

    func testOpenAIHTTPRejectsWrongContentTypeAndNonTopLevelText() async throws {
        let wrongContentType = FakeHTTPTransport(
            statusCode: 200,
            headers: ["Content-Type": "text/plain"],
            body: Data(#"{"text":"not accepted"}"#.utf8)
        )
        let wrongContentTester = try makeTester(httpTransport: wrongContentType)
        do {
            _ = try await wrongContentTester.test(
                connection: .openAIHTTP,
                apiKey: "unit-test-key"
            )
            XCTFail("错误 Content-Type 不应被接受")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Content-Type"))
        }

        let nestedText = FakeHTTPTransport(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"data":{"text":"must not be guessed"}}"#.utf8)
        )
        let nestedTester = try makeTester(httpTransport: nestedText)
        do {
            _ = try await nestedTester.test(
                connection: .openAIHTTP,
                apiKey: "unit-test-key"
            )
            XCTFail("非顶层 text 不应被猜测为兼容响应")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("text"))
        }
    }

    func testConnectionTestAcceptsEmptyTranscriptAndMatchesSelectedM4AFormat() async throws {
        let emptyText = FakeHTTPTransport(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"text":""}"#.utf8)
        )
        let emptyTester = try makeTester(httpTransport: emptyText)
        let emptyRecord = try await emptyTester.test(
            connection: .openAIHTTP,
            apiKey: "unit-test-key"
        )
        XCTAssertEqual(emptyRecord.outcome, .succeeded)
        XCTAssertTrue(emptyRecord.safeSummary.contains("响应结构"))

        let m4aTransport = FakeHTTPTransport(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"text":"fixture accepted"}"#.utf8)
        )
        let m4aTester = try makeTester(httpTransport: m4aTransport)
        var m4aConnection = SpeechProviderConfig.openAIHTTP
        m4aConnection.inputAudioFormat = "m4a"
        m4aConnection = m4aConnection.normalizedForProtocol()

        _ = try await m4aTester.test(connection: m4aConnection, apiKey: "unit-test-key")

        let captured = try XCTUnwrap(m4aTransport.captured)
        let bodyText = String(decoding: captured.body, as: UTF8.self)
        XCTAssertTrue(bodyText.contains(".m4a\""))
        XCTAssertTrue(bodyText.contains("Content-Type: audio/mp4"))
        XCTAssertNil(captured.body.range(of: Data("RIFF".utf8)))
    }

    func testErrorSummaryRedactsSecretsAndLimitsLength() throws {
        let raw = "Authorization: Bearer sk-unit-secret " + String(repeating: "x", count: 600)
        let summary = try XCTUnwrap(safeLimitedResponseText(Data(raw.utf8)))
        XCTAssertFalse(summary.contains("sk-unit-secret"))
        XCTAssertLessThanOrEqual(summary.count, 240)
    }

    func testConnectionTestRedactsOpaqueAPIKeyEchoedByCustomEndpoint() async throws {
        let opaqueKey = "opaque-custom-secret-value"
        let transport = FakeHTTPTransport(
            statusCode: 401,
            headers: ["Content-Type": "application/json"],
            body: Data(
                #"{"error":{"message":"credential opaque-custom-secret-value invalid"}}"#.utf8
            )
        )
        let tester = try makeTester(httpTransport: transport)

        do {
            _ = try await tester.test(connection: .openAIHTTP, apiKey: opaqueKey)
            XCTFail("401 响应不应通过连接测试")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(opaqueKey))
            XCTAssertTrue(error.localizedDescription.contains("[redacted]"))
        }
    }

    func testGLMSSERequiresMediaTypeValidJSONAndDoneTerminal() throws {
        let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions")!
        let validResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream; charset=utf-8"]
        )!
        XCTAssertNoThrow(try validateGLMSSEContentType(validResponse))

        let invalidResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        XCTAssertThrowsError(try validateGLMSSEContentType(invalidResponse))

        var parser = GLMSSEAccumulator()
        XCTAssertEqual(
            try parser.consume(line: #"data: {"type":"transcript.text.delta","delta":"你好"}"#),
            "你好"
        )
        XCTAssertEqual(
            try parser.consume(line: #"data: {"type":"transcript.text.done","text":"你好 Flotis"}"#),
            "你好 Flotis"
        )
        XCTAssertNil(try parser.consume(line: "data: [DONE]"))
        XCTAssertTrue(parser.receivedDone)
        XCTAssertEqual(try parser.finish(), "你好 Flotis")

        var emptyTerminal = GLMSSEAccumulator()
        XCTAssertNil(try emptyTerminal.consume(line: "data: [DONE]"))
        XCTAssertEqual(try emptyTerminal.finish(), "")

        var missingTerminal = GLMSSEAccumulator()
        _ = try missingTerminal.consume(
            line: #"data: {"type":"transcript.text.delta","delta":"partial"}"#
        )
        XCTAssertThrowsError(try missingTerminal.finish()) { error in
            XCTAssertTrue(error.localizedDescription.contains("[DONE]"))
        }

        var malformed = GLMSSEAccumulator()
        XCTAssertThrowsError(try malformed.consume(line: "data: not-json"))

        let opaqueKey = "opaque-glm-secret-value"
        var secretError = GLMSSEAccumulator(redacting: [opaqueKey])
        XCTAssertThrowsError(
            try secretError.consume(
                line: #"data: {"error":{"message":"credential opaque-glm-secret-value invalid"}}"#
            )
        ) { error in
            XCTAssertFalse(error.localizedDescription.contains(opaqueKey))
            XCTAssertTrue(error.localizedDescription.contains("[redacted]"))
        }
    }

    func testOpenAIRealtimeScriptedLifecycleUsesGASessionAppendCommitAndCompletion() async throws {
        let socket = ScriptedRealtimeSocket()
        let registry = try TranscriptionAdapterRegistry.live(
            openAIRealtimeSocketFactory: { request in
                socket.record(request: request)
                return socket
            }
        )
        let tester = TranscriptionConnectionTester(
            runtimeFactory: TranscriptionRuntimeFactory(registry: registry),
            secretLoader: { _ in nil },
            localCapabilityProbe: { _ in }
        )
        var connection = SpeechProviderConfig.openAIRealtime
        connection.model = "custom-realtime-transcription-model"
        connection = connection.normalizedForProtocol()

        let record = try await tester.test(
            connection: connection,
            apiKey: "unit-test-key"
        )
        XCTAssertEqual(record.outcome, .succeeded)
        XCTAssertEqual(record.configurationFingerprint, connection.connectionTestFingerprint)

        let request = try XCTUnwrap(socket.recordedRequest)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer unit-test-key"
        )
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "model" })?.value,
            "custom-realtime-transcription-model"
        )

        let messages = await socket.sentJSONMessages()
        let eventTypes = messages.compactMap { $0["type"] as? String }
        XCTAssertEqual(eventTypes.first, "session.update")
        XCTAssertTrue(eventTypes.contains("input_audio_buffer.append"))
        XCTAssertEqual(eventTypes.last, "input_audio_buffer.commit")

        let update = try XCTUnwrap(messages.first)
        let session = try XCTUnwrap(update["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(
            transcription["model"] as? String,
            "custom-realtime-transcription-model"
        )
        XCTAssertTrue(input["turn_detection"] is NSNull)
    }

    private func makeTester(
        httpTransport: FakeHTTPTransport
    ) throws -> TranscriptionConnectionTester {
        let registry = try TranscriptionAdapterRegistry.live(
            openAIHTTPTransportFactory: { httpTransport }
        )
        return TranscriptionConnectionTester(
            runtimeFactory: TranscriptionRuntimeFactory(registry: registry),
            secretLoader: { _ in nil },
            localCapabilityProbe: { _ in }
        )
    }
}

private final class FakeHTTPTransport: HTTPTranscriptionUploading {
    struct Captured {
        let request: URLRequest
        let body: Data
    }

    private let lock = NSLock()
    private let statusCode: Int
    private let headers: [String: String]
    private let responseBody: Data
    private var storedCaptured: Captured?
    private var cancelled = false

    var captured: Captured? {
        lock.withLock { storedCaptured }
    }

    init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        responseBody = body
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, URLResponse) {
        let body = try Data(contentsOf: fileURL)
        let wasCancelled = lock.withLock { () -> Bool in
            guard !cancelled else { return true }
            storedCaptured = Captured(request: request, body: body)
            return false
        }
        if wasCancelled {
            throw CancellationError()
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (responseBody, response)
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

private final class ScriptedRealtimeSocket: RealtimeWebSocket {
    private let state = ScriptedRealtimeSocketState()
    private let requestLock = NSLock()
    private var request: URLRequest?

    var recordedRequest: URLRequest? {
        requestLock.lock()
        defer { requestLock.unlock() }
        return request
    }

    func record(request: URLRequest) {
        requestLock.lock()
        self.request = request
        requestLock.unlock()
    }

    func resume() {}

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await state.send(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await state.receive()
    }

    func cancel(
        with closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { await state.close() }
    }

    func sentJSONMessages() async -> [[String: Any]] {
        await state.sentJSONMessages()
    }
}

private actor ScriptedRealtimeSocketState {
    typealias Message = URLSessionWebSocketTask.Message

    private var sentMessages: [Message] = []
    private var queuedMessages: [Message] = []
    private var waiters: [CheckedContinuation<Message, Error>] = []
    private var closed = false

    func send(_ message: Message) throws {
        guard !closed else { throw CancellationError() }
        sentMessages.append(message)
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.update":
            enqueueJSON(["type": "session.updated"])
        case "input_audio_buffer.commit":
            enqueueJSON([
                "type": "input_audio_buffer.committed",
                "item_id": "fixture-item"
            ])
            enqueueJSON([
                "type": "conversation.item.input_audio_transcription.completed",
                "item_id": "fixture-item",
                "content_index": 0,
                "transcript": "fixture transcript"
            ])
        default:
            break
        }
    }

    func receive() async throws -> Message {
        if !queuedMessages.isEmpty {
            return queuedMessages.removeFirst()
        }
        guard !closed else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() {
        closed = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume(throwing: CancellationError()) }
    }

    func sentJSONMessages() -> [[String: Any]] {
        sentMessages.compactMap { message in
            guard case .string(let text) = message,
                  let data = text.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    private func enqueueJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        let message = Message.string(text)
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: message)
        } else {
            queuedMessages.append(message)
        }
    }
}
