import XCTest

@MainActor
final class FlotisInputMethodServiceTests: XCTestCase {
    func testMatchingSessionDeliversOriginalText() {
        let service = FlotisInputMethodService()
        let endpoint = ClientEndpointStub()
        let sessionID = service.activate(endpoint: endpoint)
        let originalText = "  exact transcript 文本  "
        XCTAssertEqual(service.currentSessionID, sessionID)

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: sessionID, text: originalText)
        )

        XCTAssertEqual(result, .deliveredToClient)
        XCTAssertEqual(endpoint.insertedTexts, [originalText])
    }

    func testUnsupportedProtocolIsRejectedBeforeDelivery() {
        let service = FlotisInputMethodService()
        let endpoint = ClientEndpointStub()
        let sessionID = service.activate(endpoint: endpoint)

        let result = service.submit(
            FlotisInputMethodCommitRequest(
                protocolVersion: FlotisInputMethodCommitRequest.currentProtocolVersion + 1,
                sessionID: sessionID,
                text: "hello"
            )
        )

        XCTAssertEqual(result, .rejected(.unsupportedProtocol))
        XCTAssertTrue(endpoint.insertedTexts.isEmpty)
    }

    func testWhitespaceOnlyTextIsRejectedBeforeDelivery() {
        let service = FlotisInputMethodService()
        let endpoint = ClientEndpointStub()
        let sessionID = service.activate(endpoint: endpoint)

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: sessionID, text: " \n\t ")
        )

        XCTAssertEqual(result, .rejected(.emptyText))
        XCTAssertTrue(endpoint.insertedTexts.isEmpty)
    }

    func testOversizedTextIsRejectedBeforeDelivery() {
        let service = FlotisInputMethodService()
        let endpoint = ClientEndpointStub()
        let sessionID = service.activate(endpoint: endpoint)
        let oversizedText = String(
            repeating: "a",
            count: FlotisInputMethodSessionGate.maximumTextByteCount + 1
        )

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: sessionID, text: oversizedText)
        )

        XCTAssertEqual(result, .rejected(.textTooLarge))
        XCTAssertTrue(endpoint.insertedTexts.isEmpty)
    }

    func testNewActivationInvalidatesPreviousSession() {
        let service = FlotisInputMethodService()
        let firstEndpoint = ClientEndpointStub()
        let firstSessionID = service.activate(endpoint: firstEndpoint)
        let secondEndpoint = ClientEndpointStub()
        _ = service.activate(endpoint: secondEndpoint)

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: firstSessionID, text: "stale")
        )

        XCTAssertEqual(result, .rejected(.staleSession))
        XCTAssertTrue(firstEndpoint.insertedTexts.isEmpty)
        XCTAssertTrue(secondEndpoint.insertedTexts.isEmpty)
    }

    func testDeactivationInvalidatesSession() {
        let service = FlotisInputMethodService()
        let endpoint = ClientEndpointStub()
        let sessionID = service.activate(endpoint: endpoint)
        service.deactivate(endpoint: endpoint, sessionID: sessionID)
        XCTAssertNil(service.currentSessionID)

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: sessionID, text: "too late")
        )

        XCTAssertEqual(result, .rejected(.staleSession))
        XCTAssertTrue(endpoint.insertedTexts.isEmpty)
    }

    func testReleasedEndpointIsReportedWithoutDelivery() {
        let service = FlotisInputMethodService()
        let sessionID: UUID
        do {
            let endpoint = ClientEndpointStub()
            sessionID = service.activate(endpoint: endpoint)
        }

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: sessionID, text: "hello")
        )

        XCTAssertEqual(result, .rejected(.endpointUnavailable))
    }

    func testClientRejectionIsReported() {
        let service = FlotisInputMethodService()
        let endpoint = ClientEndpointStub(acceptsInsertion: false)
        let sessionID = service.activate(endpoint: endpoint)

        let result = service.submit(
            FlotisInputMethodCommitRequest(sessionID: sessionID, text: "hello")
        )

        XCTAssertEqual(result, .rejected(.clientUnavailable))
        XCTAssertEqual(endpoint.insertedTexts, ["hello"])
    }
}

@MainActor
private final class ClientEndpointStub: FlotisInputMethodClientEndpoint {
    let acceptsInsertion: Bool
    private(set) var insertedTexts: [String] = []

    init(acceptsInsertion: Bool = true) {
        self.acceptsInsertion = acceptsInsertion
    }

    func insertCommittedText(_ text: String) -> Bool {
        insertedTexts.append(text)
        return acceptsInsertion
    }
}
