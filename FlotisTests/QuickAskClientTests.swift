import XCTest
@testable import Flotis

final class QuickAskClientTests: XCTestCase {
    override func tearDown() {
        QuickAskMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testSendsStrictChatCompletionsRequest() async throws {
        let requestExpectation = expectation(description: "request")
        QuickAskMockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.openai.com/v1/chat/completions"
            )
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer test-api-key"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )
            let body = try XCTUnwrap(request.httpBody ?? Self.readBodyStream(request.httpBodyStream))
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["model"] as? String, "gpt-test")
            XCTAssertEqual(json["max_tokens"] as? Int, 2_048)
            XCTAssertNil(json["stream"])
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
            XCTAssertEqual(messages.last?["content"] as? String, "hello")
            requestExpectation.fulfill()
            return QuickAskMockURLProtocol.Response(
                status: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(#"{"choices":[{"message":{"role":"assistant","content":"world"}}]}"#.utf8)
            )
        }

        let reply = try await makeClient().complete(
            messages: [QuickAskMessage(role: .user, content: "hello")],
            configuration: makeConfiguration()
        )

        XCTAssertEqual(reply, "world")
        await fulfillment(of: [requestExpectation], timeout: 1)
    }

    func testRejectsPlainHTTPBeforeNetworkCall() async {
        QuickAskMockURLProtocol.handler = { _ in
            XCTFail("HTTP configuration must fail before networking")
            return .init(status: 500, headers: [:], data: Data())
        }
        var configuration = makeConfiguration()
        configuration.baseURL = "http://localhost:1234/v1"
        configuration.customEndpointApproved = true

        do {
            _ = try await makeClient().complete(
                messages: [QuickAskMessage(role: .user, content: "hello")],
                configuration: configuration
            )
            XCTFail("Expected configuration failure")
        } catch let error as QuickAskError {
            guard case .configuration = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomHTTPSHostRequiresExplicitApproval() throws {
        var configuration = makeConfiguration()
        configuration.baseURL = "https://gateway.example.com/v1"
        configuration.customEndpointApproved = false

        XCTAssertEqual(
            configuration.validationError(),
            .customHostApprovalRequired("gateway.example.com")
        )

        configuration.customEndpointApproved = true
        XCTAssertNil(configuration.validationError())
        XCTAssertEqual(
            try QuickAskEndpointResolver.endpointURL(for: configuration).absoluteString,
            "https://gateway.example.com/v1/chat/completions"
        )
    }

    func testServerErrorRedactsExactAPIKeyAndBoundsMessage() {
        let apiKey = "secret-value-without-provider-prefix"
        let longMessage = "echo \(apiKey) " + String(repeating: "x", count: 1_000)
        let data = try! JSONSerialization.data(
            withJSONObject: ["error": ["message": longMessage]]
        )

        let error = QuickAskClient.error(for: 500, data: data, apiKey: apiKey)
        guard case .server(let status, let message) = error else {
            return XCTFail("Expected server error")
        }
        XCTAssertEqual(status, 500)
        XCTAssertFalse(message.contains(apiKey))
        XCTAssertTrue(message.contains("[REDACTED]"))
        XCTAssertLessThanOrEqual(message.count, 512)
    }

    func testRejectsNonJSONSuccessResponse() async {
        QuickAskMockURLProtocol.handler = { _ in
            QuickAskMockURLProtocol.Response(
                status: 200,
                headers: ["Content-Type": "text/plain"],
                data: Data("not json".utf8)
            )
        }

        do {
            _ = try await makeClient().complete(
                messages: [QuickAskMessage(role: .user, content: "hello")],
                configuration: makeConfiguration()
            )
            XCTFail("Expected unexpected response")
        } catch let error as QuickAskError {
            XCTAssertEqual(error, .unexpectedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectionMapsTimeoutWithoutPersistingContent() async {
        QuickAskMockURLProtocol.handler = { _ in throw URLError(.timedOut) }

        let result = await makeClient().testConnection(
            configuration: makeConfiguration()
        )

        XCTAssertEqual(result.status, .requestTimeout)
    }

    private func makeClient() -> QuickAskClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QuickAskMockURLProtocol.self]
        return QuickAskClient(session: URLSession(configuration: configuration))
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func makeConfiguration() -> QuickAskConfiguration {
        QuickAskConfiguration(
            baseURL: "https://api.openai.com/v1",
            path: "/chat/completions",
            model: "gpt-test",
            apiKey: "test-api-key",
            temperature: 0.7,
            maxTokens: 2_048,
            timeoutSeconds: 120,
            systemPrompt: "Be concise.",
            customEndpointApproved: false
        )
    }
}

private final class QuickAskMockURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let headers: [String: String]
        let data: Data
    }

    static var handler: ((URLRequest) throws -> Response)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let result = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
