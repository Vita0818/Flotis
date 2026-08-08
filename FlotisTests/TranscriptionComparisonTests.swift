import Foundation
import XCTest
@testable import Flotis

final class TranscriptionComparisonTests: XCTestCase {
    func testComparisonPreferencesRequireTwoModelsPersistAndCapAtFour() throws {
        let suiteName = "com.flotis.tests.comparison.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (rootURL, fileURL) = makeConfigurationLocation()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let key = "comparison"
        let configurationStore = FlotisConfigurationStore(fileURL: fileURL)
        let selectors = (0..<5).map { "openrouter/openai/model-\($0)" }
        var provider = FlotisProviderConfiguration(
            connection: .openAIHTTP,
            apiKey: "test-key"
        )
        provider.name = "OpenRouter"
        provider.models = Dictionary(uniqueKeysWithValues: selectors.map { selector in
            let modelID = FlotisModelSelector(rawValue: selector)!.modelID
            return (modelID, FlotisModelConfiguration())
        })
        let document = FlotisConfigurationDocument(
            model: selectors[0],
            providerOrder: ["openrouter"],
            enabledProviders: ["openrouter"],
            comparison: FlotisComparisonConfiguration(enabled: false, models: []),
            provider: ["openrouter": provider]
        )
        XCTAssertTrue(configurationStore.installInitialDocument(document))
        let store = TranscriptionComparisonStore(
            defaults: defaults,
            storageKey: key,
            configurationStore: configurationStore
        )
        XCTAssertFalse(store.setEnabled(true))
        XCTAssertEqual(store.lastError, UIStrings.comparisonNeedsTwoConnections)

        XCTAssertTrue(store.setModel(selectors[0], selected: true))
        XCTAssertTrue(store.setModel(selectors[1], selected: true))
        XCTAssertTrue(store.setEnabled(true))
        XCTAssertTrue(store.isEnabled)

        XCTAssertTrue(store.setModel(selectors[2], selected: true))
        XCTAssertTrue(store.setModel(selectors[3], selected: true))
        XCTAssertFalse(store.setModel(selectors[4], selected: true))
        XCTAssertEqual(store.selectedModelSelectors, Array(selectors.prefix(4)))

        let reloaded = TranscriptionComparisonStore(
            defaults: defaults,
            storageKey: key,
            configurationStore: configurationStore
        )
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(reloaded.selectedModelSelectors, Array(selectors.prefix(4)))

        XCTAssertTrue(reloaded.setModel(selectors[0], selected: false))
        XCTAssertTrue(reloaded.setModel(selectors[1], selected: false))
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertTrue(reloaded.setModel(selectors[2], selected: false))
        XCTAssertFalse(reloaded.isEnabled)
    }

    func testCorruptComparisonPreferencesAreNotOverwritten() throws {
        let suiteName = "com.flotis.tests.comparison-corrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (rootURL, fileURL) = makeConfigurationLocation()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let key = "comparison"
        let corruptData = Data("not-json".utf8)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try corruptData.write(to: fileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )

        let store = TranscriptionComparisonStore(
            defaults: defaults,
            storageKey: key,
            configurationStore: FlotisConfigurationStore(fileURL: fileURL)
        )
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.lastError, UIStrings.comparisonPreferencesUnavailable)
        XCTAssertEqual(try Data(contentsOf: fileURL), corruptData)
    }

    func testComparisonReviewSelectsFirstSuccessAndPreservesEditsWhileNavigating() {
        let appState = AppState()
        let firstID = UUID()
        let secondID = UUID()
        let failedID = UUID()
        appState.installComparisonCandidates([
            makeCandidate(id: failedID, text: "", failure: "Unavailable"),
            makeCandidate(id: firstID, text: "First result"),
            makeCandidate(id: secondID, text: "Second result")
        ])

        XCTAssertTrue(appState.isComparisonReview)
        XCTAssertEqual(appState.selectedTranscriptCandidateID, firstID)
        XCTAssertEqual(appState.transcriptPreview, "First result")
        XCTAssertFalse(appState.selectTranscriptCandidate(id: failedID))

        appState.updateReviewedTranscript("Edited first result")

        XCTAssertTrue(appState.navigateTranscriptCandidate(.next))
        XCTAssertEqual(appState.selectedTranscriptCandidateID, secondID)
        XCTAssertEqual(appState.transcriptPreview, "Second result")
        appState.updateReviewedTranscript("Edited second result")

        XCTAssertTrue(appState.navigateTranscriptCandidate(.next))
        XCTAssertEqual(appState.selectedTranscriptCandidateID, firstID)
        XCTAssertEqual(appState.transcriptPreview, "Edited first result")

        XCTAssertTrue(appState.navigateTranscriptCandidate(.previous))
        XCTAssertEqual(appState.selectedTranscriptCandidateID, secondID)
        XCTAssertEqual(appState.transcriptPreview, "Edited second result")
    }

    @MainActor
    func testComparisonCopyUsesCurrentKeyboardNavigatedCandidate() {
        let appState = AppState()
        appState.voiceState = .reviewing
        let firstID = UUID()
        let secondID = UUID()
        appState.installComparisonCandidates([
            makeCandidate(id: firstID, text: "First candidate"),
            makeCandidate(id: secondID, text: "Second candidate")
        ])
        let clipboard = ComparisonClipboardWriter()
        let controller = VoiceInputController(
            appState: appState,
            transcriptClipboardWriter: clipboard
        )

        XCTAssertEqual(appState.selectedTranscriptCandidateID, firstID)
        XCTAssertTrue(appState.canNavigateComparisonCandidates)
        controller.selectNextTranscriptCandidate()
        XCTAssertEqual(appState.selectedTranscriptCandidateID, secondID)
        appState.updateReviewedTranscript("Edited second candidate")
        controller.toggleRecording()

        XCTAssertEqual(clipboard.writtenTexts, ["Edited second candidate"])
        XCTAssertEqual(appState.voiceState, .idle)
        XCTAssertFalse(appState.isComparisonReview)
        XCTAssertEqual(appState.transcriptPreview, "")
    }

    func testFileComparisonUsesOneFileAndIsolatesProviderFailure() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Flotis-Comparison-Test-\(UUID().uuidString).wav")
        try Data("shared-audio".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let firstID = UUID()
        let secondID = UUID()
        let first = ComparisonFileTranscriber(result: .success(" First transcript "))
        let second = ComparisonFileTranscriber(
            result: .failure(
                NSError(
                    domain: "ComparisonTest",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Provider unavailable"]
                )
            )
        )
        let jobs = [
            FileTranscriptionComparisonJob(
                order: 0,
                connectionID: firstID,
                connectionName: "First",
                model: "model-a",
                destination: "a.example.com",
                transcriber: first,
                maximumUploadBytes: nil
            ),
            FileTranscriptionComparisonJob(
                order: 1,
                connectionID: secondID,
                connectionName: "Second",
                model: "model-b",
                destination: "b.example.com",
                transcriber: second,
                maximumUploadBytes: nil
            )
        ]

        let candidates = try await FileTranscriptionComparisonRunner().run(
            fileURL: fileURL,
            jobs: jobs
        )

        XCTAssertEqual(candidates.map(\.id), [firstID, secondID])
        XCTAssertTrue(candidates[0].isSuccessful)
        XCTAssertEqual(candidates[0].text, "First transcript")
        XCTAssertFalse(candidates[1].isSuccessful)
        XCTAssertEqual(candidates[1].failureMessage, "Provider unavailable")
        XCTAssertEqual(first.receivedFileURLs, [fileURL])
        XCTAssertEqual(second.receivedFileURLs, [fileURL])
    }

    private func makeCandidate(
        id: UUID,
        text: String,
        failure: String? = nil
    ) -> TranscriptCandidate {
        TranscriptCandidate(
            id: id,
            connectionName: "Connection",
            model: "Model",
            destination: "example.com",
            text: text,
            outcome: failure.map(TranscriptCandidate.Outcome.failed) ?? .succeeded,
            elapsedMilliseconds: 100
        )
    }

    private func makeConfigurationLocation() -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisComparisonConfigTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let file = root
            .appendingPathComponent("Flotis", isDirectory: true)
            .appendingPathComponent("config.json")
        return (root, file)
    }
}

private final class ComparisonClipboardWriter: TranscriptClipboardWriting {
    private(set) var writtenTexts: [String] = []

    func writeTranscript(_ text: String) -> Bool {
        writtenTexts.append(text)
        return true
    }
}

private final class ComparisonFileTranscriber: FileSpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)?

    private let lock = NSLock()
    private let result: Result<String, Error>
    private var storedFileURLs: [URL] = []
    private var isCancelled = false

    var receivedFileURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedFileURLs
    }

    init(result: Result<String, Error>) {
        self.result = result
    }

    func transcribeFile(_ fileURL: URL) async throws -> String {
        let cancelled = register(fileURL)
        if cancelled { throw CancellationError() }
        return try result.get()
    }

    private func register(_ fileURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedFileURLs.append(fileURL)
        return isCancelled
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}
