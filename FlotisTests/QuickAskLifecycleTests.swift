import XCTest
@testable import Flotis

final class QuickAskLifecycleTests: XCTestCase {
    private var temporaryDirectory: URL?

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    @MainActor
    func testSendBuildsEphemeralConversationAndCloseClearsMessagesAndDraft() async throws {
        let service = StubQuickAskService(result: .success("answer"))
        let (store, _) = try makeConfiguredStore()
        let session = QuickAskSession(service: service, configurationStore: store)
        session.draft = "question"

        session.sendDraft()
        await waitUntil { session.messages.count == 2 }

        XCTAssertEqual(session.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.messages.map(\.content), ["question", "answer"])
        XCTAssertEqual(service.receivedMessages.map(\.content), ["question"])
        XCTAssertEqual(service.receivedConfiguration?.model, "gpt-test-2")
        XCTAssertEqual(service.receivedConfiguration?.providerName, "Test Provider")

        session.draft = "private unsent draft"
        session.close()
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(session.draft, "")
        XCTAssertNil(session.lastError)
        XCTAssertFalse(session.isRequesting)
    }

    @MainActor
    func testCloseCancelsInFlightRequestAndPreventsStaleReply() async throws {
        let cancellation = expectation(description: "service cancelled")
        let service = HangingQuickAskService(cancellationExpectation: cancellation)
        let (store, _) = try makeConfiguredStore()
        let session = QuickAskSession(service: service, configurationStore: store)
        session.draft = "pending question"

        session.sendDraft()
        XCTAssertTrue(session.isRequesting)
        XCTAssertEqual(session.messages.count, 1)
        session.close()

        await fulfillment(of: [cancellation], timeout: 1)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(session.draft, "")
        XCTAssertFalse(session.isRequesting)
    }

    @MainActor
    func testFailureKeepsUserMessageAndSurfacesBoundedError() async throws {
        let service = StubQuickAskService(
            result: .failure(.server(status: 500, message: "failed"))
        )
        let (store, _) = try makeConfiguredStore()
        let session = QuickAskSession(service: service, configurationStore: store)

        session.send("question")
        await waitUntil { !session.isRequesting }

        XCTAssertEqual(session.messages.map(\.content), ["question"])
        XCTAssertEqual(session.lastError, .server(status: 500, message: "failed"))
    }

    func testProviderModelsCatalogPersistsAndPreservesOtherCanonicalPartitions() throws {
        let root = makeTemporaryDirectory()
        let fileURL = root.appendingPathComponent("config.json")
        let canonicalStore = FlotisConfigurationStore(fileURL: fileURL)
        let hotkeyStore = HotkeyConfigurationStore(configurationStore: canonicalStore)
        let quickAskStore = QuickAskConfigurationStore(configurationStore: canonicalStore)

        let providerID = try XCTUnwrap(saveTestProvider(in: quickAskStore))
        let customVoice = KeyboardShortcutDescriptor(
            keyCode: 11,
            modifiers: .controlOption
        )
        XCTAssertTrue(hotkeyStore.setShortcut(customVoice, for: .toggleVoice))

        let reloaded = QuickAskConfigurationStore(configurationStore: canonicalStore)
        XCTAssertEqual(reloaded.providerGroups.map(\.id), [providerID])
        XCTAssertEqual(reloaded.providerGroups[0].modelIDs, ["gpt-test", "gpt-test-2"])
        XCTAssertEqual(reloaded.configuration.model, "gpt-test-2")
        XCTAssertEqual(reloaded.configuration.modelDisplayName, "Quality")
        XCTAssertEqual(reloaded.configuration.apiKey, "test-api-key")

        guard case .loaded(let document) = canonicalStore.load() else {
            return XCTFail("Expected canonical config.json")
        }
        XCTAssertEqual(document.quickAsk, quickAskStore.catalog)
        XCTAssertEqual(document.shortcuts?.toggleVoice, customVoice)
        XCTAssertEqual(document.shortcuts?.toggleQuickAsk, .toggleQuickAsk)
        XCTAssertEqual(document.provider, [:])
        XCTAssertEqual(
            document.comparison,
            FlotisComparisonConfiguration(enabled: false, models: [])
        )
    }

    func testMultipleQuickAskProvidersRemainIsolatedAndSaveSelectsActiveRoute() throws {
        let root = makeTemporaryDirectory()
        let store = QuickAskConfigurationStore(
            configurationStore: FlotisConfigurationStore(
                fileURL: root.appendingPathComponent("config.json")
            )
        )
        let firstID = try XCTUnwrap(saveTestProvider(in: store))

        var secondOptions = makeProviderOptions()
        secondOptions.baseURL = "https://openrouter.ai/api/v1"
        let secondID = try XCTUnwrap(store.saveProviderGroup(
            existingProviderID: nil,
            name: "OpenRouter",
            options: secondOptions,
            modelIDs: ["openai/chat-model"],
            modelDisplayNames: ["openai/chat-model": "Router Chat"],
            selectedModelID: "openai/chat-model",
            savingAPIKey: "router-key"
        ))

        XCTAssertEqual(store.providerGroups.map(\.id), [firstID, secondID])
        XCTAssertEqual(store.configuration.providerID, secondID)
        XCTAssertEqual(store.configuration.model, "openai/chat-model")
        XCTAssertEqual(
            store.providerGroup(id: firstID)?.configuration.options.apiKey,
            "test-api-key"
        )
        XCTAssertEqual(
            store.providerGroup(id: secondID)?.configuration.options.apiKey,
            "router-key"
        )

        XCTAssertNotNil(store.saveProviderGroup(
            existingProviderID: firstID,
            name: "Test Provider",
            options: makeProviderOptions(),
            modelIDs: ["gpt-test", "gpt-test-2"],
            modelDisplayNames: ["gpt-test-2": "Quality"],
            selectedModelID: "gpt-test",
            savingAPIKey: nil
        ))
        XCTAssertEqual(store.configuration.providerID, firstID)
        XCTAssertEqual(store.configuration.model, "gpt-test")
        XCTAssertEqual(store.providerGroups.map(\.id), [firstID, secondID])
    }

    func testCredentialDestinationChangeClearsOldKeyUnlessNewKeyIsSubmitted() throws {
        let root = makeTemporaryDirectory()
        let store = QuickAskConfigurationStore(
            configurationStore: FlotisConfigurationStore(
                fileURL: root.appendingPathComponent("config.json")
            )
        )
        let providerID = try XCTUnwrap(saveTestProvider(in: store))
        var changed = makeProviderOptions()
        changed.baseURL = "https://openrouter.ai/api/v1"

        XCTAssertNotNil(store.saveProviderGroup(
            existingProviderID: providerID,
            name: "Test Provider",
            options: changed,
            modelIDs: ["gpt-test", "gpt-test-2"],
            modelDisplayNames: [:],
            selectedModelID: "gpt-test",
            savingAPIKey: nil
        ))
        XCTAssertFalse(store.hasAPIKey(providerID: providerID))

        XCTAssertNotNil(store.saveProviderGroup(
            existingProviderID: providerID,
            name: "Test Provider",
            options: changed,
            modelIDs: ["gpt-test", "gpt-test-2"],
            modelDisplayNames: [:],
            selectedModelID: "gpt-test",
            savingAPIKey: "new-key"
        ))
        XCTAssertTrue(store.hasAPIKey(providerID: providerID))
        XCTAssertEqual(store.configuration.apiKey, "new-key")
    }

    func testDeletingActiveProviderSelectsRemainingRouteThenAllowsEmptyCatalog() throws {
        let root = makeTemporaryDirectory()
        let store = QuickAskConfigurationStore(
            configurationStore: FlotisConfigurationStore(
                fileURL: root.appendingPathComponent("config.json")
            )
        )
        let firstID = try XCTUnwrap(saveTestProvider(in: store))
        let secondID = try XCTUnwrap(store.saveProviderGroup(
            existingProviderID: nil,
            name: "Second Provider",
            options: makeProviderOptions(),
            modelIDs: ["second-model"],
            modelDisplayNames: [:],
            selectedModelID: "second-model",
            savingAPIKey: nil
        ))

        XCTAssertTrue(store.deleteProviderGroup(id: secondID))
        XCTAssertEqual(store.configuration.providerID, firstID)
        XCTAssertTrue(store.deleteProviderGroup(id: firstID))
        XCTAssertTrue(store.providerGroups.isEmpty)
        XCTAssertNil(store.activeConfiguration)
        XCTAssertEqual(store.activeModelSelector, "")
    }

    @MainActor
    func testConversationContentNeverEntersCanonicalConfiguration() async throws {
        let service = StubQuickAskService(result: .success("private answer"))
        let (store, fileURL) = try makeConfiguredStore()
        let session = QuickAskSession(service: service, configurationStore: store)

        session.send("private question")
        await waitUntil { session.messages.count == 2 }
        let text = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)

        XCTAssertFalse(text.contains("private question"))
        XCTAssertFalse(text.contains("private answer"))
    }

    @MainActor
    func testPanelPositionPrefersLeftAndClampsToVisibleFrame() {
        let left = QuickAskPanelController.resolvedOrigin(
            capsuleFrame: NSRect(x: 800, y: 300, width: 96, height: 36),
            panelSize: NSSize(width: 420, height: 560),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        XCTAssertEqual(left.x, 368, accuracy: 0.001)
        XCTAssertEqual(left.y, 38, accuracy: 0.001)

        let right = QuickAskPanelController.resolvedOrigin(
            capsuleFrame: NSRect(x: 10, y: 10, width: 96, height: 36),
            panelSize: NSSize(width: 420, height: 560),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        XCTAssertEqual(right.x, 118, accuracy: 0.001)
        XCTAssertEqual(right.y, 0, accuracy: 0.001)
    }

    func testPanelTitleBarStartsNativeDragWithoutStealingControlsOrContent() {
        let contentSize = NSSize(width: 420, height: 560)

        XCTAssertFalse(QuickAskPanelInteraction.allowsSystemManagedMovement)
        XCTAssertEqual(
            QuickAskPanelInteraction.mouseDownAction(
                clickCount: 1,
                location: NSPoint(x: 120, y: 540),
                contentSize: contentSize
            ),
            .beginDrag
        )
        XCTAssertEqual(
            QuickAskPanelInteraction.mouseDownAction(
                clickCount: 1,
                location: NSPoint(x: 390, y: 540),
                contentSize: contentSize
            ),
            .forward
        )
        XCTAssertEqual(
            QuickAskPanelInteraction.mouseDownAction(
                clickCount: 1,
                location: NSPoint(x: 120, y: 500),
                contentSize: contentSize
            ),
            .forward
        )
        XCTAssertEqual(
            QuickAskPanelInteraction.mouseDownAction(
                clickCount: 2,
                location: NSPoint(x: 120, y: 540),
                contentSize: contentSize
            ),
            .forward
        )
    }

    @MainActor
    func testPanelUsesCapsuleOrderingContractWhileRemainingKeyable() {
        let panel = QuickAskPanel(
            contentRect: NSRect(origin: .zero, size: QuickAskPanelController.panelSize)
        )

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    private func makeConfiguredStore() throws -> (QuickAskConfigurationStore, URL) {
        let root = makeTemporaryDirectory()
        let fileURL = root.appendingPathComponent("config.json")
        let store = QuickAskConfigurationStore(
            configurationStore: FlotisConfigurationStore(fileURL: fileURL)
        )
        XCTAssertNotNil(saveTestProvider(in: store))
        return (store, fileURL)
    }

    @discardableResult
    private func saveTestProvider(in store: QuickAskConfigurationStore) -> String? {
        store.saveProviderGroup(
            existingProviderID: nil,
            name: "Test Provider",
            options: makeProviderOptions(),
            modelIDs: ["gpt-test", "gpt-test-2"],
            modelDisplayNames: ["gpt-test-2": "Quality"],
            selectedModelID: "gpt-test-2",
            savingAPIKey: "test-api-key"
        )
    }

    private func makeProviderOptions() -> QuickAskProviderOptions {
        QuickAskProviderOptions(
            baseURL: "https://api.openai.com/v1",
            path: "/chat/completions",
            apiKey: nil,
            temperature: 0.7,
            maxTokens: 2_048,
            timeoutSeconds: 120,
            systemPrompt: "Be concise.",
            customEndpointApproved: false
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisQuickAskTests-\(UUID().uuidString)",
            isDirectory: true
        )
        temporaryDirectory = root
        return root
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class StubQuickAskService: QuickAskServicing {
    let result: Result<String, QuickAskError>
    private(set) var receivedMessages: [QuickAskMessage] = []
    private(set) var receivedConfiguration: QuickAskConfiguration?

    init(result: Result<String, QuickAskError>) {
        self.result = result
    }

    func complete(
        messages: [QuickAskMessage],
        configuration: QuickAskConfiguration
    ) async throws -> String {
        receivedMessages = messages
        receivedConfiguration = configuration
        return try result.get()
    }
}

private final class HangingQuickAskService: QuickAskServicing {
    private let cancellationExpectation: XCTestExpectation

    init(cancellationExpectation: XCTestExpectation) {
        self.cancellationExpectation = cancellationExpectation
    }

    func complete(
        messages: [QuickAskMessage],
        configuration: QuickAskConfiguration
    ) async throws -> String {
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return "late answer"
        } catch {
            cancellationExpectation.fulfill()
            throw QuickAskError.cancelled
        }
    }
}
