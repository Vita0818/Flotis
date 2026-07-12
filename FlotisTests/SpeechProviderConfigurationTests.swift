import XCTest
@testable import Flotis

final class SpeechProviderConfigurationTests: XCTestCase {
    func testCanonicalAdapterIDsAreStableAndVersioned() {
        XCTAssertEqual(
            TranscriptionAdapterID.allCases.map(\.rawValue),
            [
                "apple-on-device",
                "openai-audio-transcriptions-http-v1",
                "openai-realtime-transcription-ga",
                "dashscope-paraformer-ws-v1",
                "volcengine-bigasr-ws-v3",
                "glm-asr-http-sse-v4"
            ]
        )
    }

    func testFreshV3StoreContainsOnlyAppleConnection() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SpeechProviderStore(defaults: defaults, secretStore: InMemorySecretStore())

        XCTAssertEqual(store.providers.map(\.adapterID), [.appleOnDevice])
        XCTAssertEqual(store.activeProviderID, TranscriptionConnection.appleSpeechID)
        XCTAssertNotNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
        XCTAssertNil(defaults.data(forKey: "flotis.speechProviders.v2"))
    }

    func testMakeNewConnectionIsPureDraftAndDoesNotPersistUntilCreate() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SpeechProviderStore(defaults: defaults, secretStore: InMemorySecretStore())
        let providersBeforeDraft = store.providers
        let snapshotBeforeDraft = defaults.data(forKey: "flotis.transcriptionConnections.v3")

        var draft = store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1)
        draft.name = "Cancelled draft"
        draft.model = "whisper-large-v3"

        XCTAssertEqual(store.providers, providersBeforeDraft)
        XCTAssertEqual(
            defaults.data(forKey: "flotis.transcriptionConnections.v3"),
            snapshotBeforeDraft
        )
        XCTAssertFalse(store.providers.contains { $0.id == draft.id })
    }

    func testUnsavedCredentialTestRecordRequiresExpectedRevisionForCreateAndUpdate() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SpeechProviderStore(defaults: defaults, secretStore: InMemorySecretStore())

        var testedCreate = store.makeNewConnection(
            adapterID: .openAIAudioTranscriptionsHTTPV1
        )
        testedCreate.credentialRevision = 1
        testedCreate.recordConnectionTest(outcome: .succeeded, safeSummary: "tested draft key")
        let createRecord = testedCreate.lastConnectionTest
        let createdID = store.createConnection(
            testedCreate,
            savingAPIKey: "first-unsaved-key"
        )!
        var persisted = store.providers.first { $0.id == createdID }!
        XCTAssertEqual(persisted.credentialRevision, 1)
        XCTAssertEqual(persisted.lastConnectionTest, createRecord)
        XCTAssertTrue(persisted.isConnectionTestCurrent)

        var staleCreate = store.makeNewConnection(
            adapterID: .openAIAudioTranscriptionsHTTPV1
        )
        staleCreate.recordConnectionTest(outcome: .succeeded, safeSummary: "revision zero")
        let staleCreatedID = store.createConnection(
            staleCreate,
            savingAPIKey: "second-unsaved-key"
        )!
        let staleCreated = store.providers.first { $0.id == staleCreatedID }!
        XCTAssertEqual(staleCreated.credentialRevision, 1)
        XCTAssertNil(staleCreated.lastConnectionTest)
        XCTAssertFalse(staleCreated.isConnectionTestCurrent)

        var testedUpdate = persisted
        testedUpdate.credentialRevision = persisted.credentialRevision + 1
        testedUpdate.recordConnectionTest(outcome: .succeeded, safeSummary: "tested replacement key")
        let updateRecord = testedUpdate.lastConnectionTest
        XCTAssertTrue(store.updateProvider(testedUpdate, savingAPIKey: "replacement-key"))
        persisted = store.providers.first { $0.id == createdID }!
        XCTAssertEqual(persisted.credentialRevision, 2)
        XCTAssertEqual(persisted.lastConnectionTest, updateRecord)
        XCTAssertTrue(persisted.isConnectionTestCurrent)

        var staleUpdate = persisted
        staleUpdate.recordConnectionTest(outcome: .succeeded, safeSummary: "stale replacement")
        XCTAssertTrue(store.updateProvider(staleUpdate, savingAPIKey: "third-key"))
        persisted = store.providers.first { $0.id == createdID }!
        XCTAssertEqual(persisted.credentialRevision, 3)
        XCTAssertNil(persisted.lastConnectionTest)
        XCTAssertFalse(persisted.isConnectionTestCurrent)
    }

    func testGenericHTTPDefaultsToPortableWAVWithoutOptionalPromptOrTemperature() {
        let provider = TranscriptionConnection.openAIHTTP.normalizedForProtocol()

        XCTAssertEqual(provider.adapterID, .openAIAudioTranscriptionsHTTPV1)
        XCTAssertEqual(provider.inputAudioFormat, "wav")
        XCTAssertEqual(provider.sampleRate, 16_000)
        XCTAssertEqual(provider.channels, 1)
        XCTAssertNil(provider.prompt)
        XCTAssertNil(provider.temperature)
        XCTAssertTrue(provider.protocolSchema.supportsEditableModel)
        XCTAssertTrue(
            TranscriptionConnection.openAIRealtime.protocolSchema.supportsEditableModel
        )
    }

    func testPresetFillsFieldsWithoutChangingConnectionIdentityOrAdapter() {
        let id = UUID()
        let reference = "existing-reference"
        var draft = TranscriptionConnection(
            id: id,
            name: "My endpoint",
            adapterID: .openAIAudioTranscriptionsHTTPV1
        )
        draft.apiKeyReference = reference

        let preset = TranscriptionProviderPreset.defaultPreset(
            for: .openAIAudioTranscriptionsHTTPV1
        )!
        let applied = preset.applying(to: draft)

        XCTAssertEqual(applied.id, id)
        XCTAssertEqual(applied.name, "My endpoint")
        XCTAssertEqual(applied.adapterID, draft.adapterID)
        XCTAssertEqual(applied.apiKeyReference, reference)
        XCTAssertEqual(applied.baseURL, "https://api.openai.com")

        let incompatible = TranscriptionProviderPreset.defaultPreset(
            for: .openAIRealtimeTranscriptionGA
        )!.applying(to: draft)
        XCTAssertEqual(incompatible, draft)
    }

    func testV2MigrationPreservesSixTypesCustomConnectionOrderNamesActiveAndReferences() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var connections = TranscriptionConnection.defaultProviders
        var custom = TranscriptionConnection.openAIHTTP
        custom.id = UUID()
        custom.name = "OpenAI HTTP"
        custom.baseURL = "https://asr.example.com"
        custom.endpointPath = "/v1/audio/transcriptions"
        custom.model = "whisper-large-v3"
        custom.inputAudioFormat = "m4a"
        custom.isCustomEndpointApproved = true
        custom.apiKeyReference = "legacy-custom-key-reference"
        connections.insert(custom, at: 2)

        let legacyProviders = connections.map(LegacySpeechProviderConfig.init)
        let legacy = SpeechProviderStoreSnapshotV2(
            schemaVersion: 2,
            presetCatalogVersion: 1,
            providers: legacyProviders,
            activeProviderID: custom.id
        )
        let v2Data = try JSONEncoder().encode(legacy)
        defaults.set(v2Data, forKey: "flotis.speechProviders.v2")

        let store = SpeechProviderStore(defaults: defaults, secretStore: InMemorySecretStore())

        XCTAssertEqual(store.providers.map(\.id), connections.map(\.id))
        XCTAssertEqual(store.providers.map(\.name), connections.map(\.name))
        XCTAssertEqual(store.activeProviderID, custom.id)
        XCTAssertEqual(
            store.providers.map(\.adapterID),
            [
                .appleOnDevice,
                .openAIRealtimeTranscriptionGA,
                .openAIAudioTranscriptionsHTTPV1,
                .openAIAudioTranscriptionsHTTPV1,
                .dashScopeParaformerWSV1,
                .volcengineBigASRWSV3,
                .glmASRHTTPSSEV4
            ]
        )
        let migratedCustom = store.providers.first { $0.id == custom.id }!
        XCTAssertEqual(migratedCustom.apiKeyReference, "legacy-custom-key-reference")
        XCTAssertEqual(migratedCustom.inputAudioFormat, "m4a")
        XCTAssertEqual(migratedCustom.displayNameForUI, "OpenAI HTTP")
        XCTAssertEqual(defaults.data(forKey: "flotis.speechProviders.v2"), v2Data)
        XCTAssertNotNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
    }

    func testV1MigrationUpgradesExactLegacyRealtimeDefaultAndAddsFormerV2Presets() {
        var legacyRealtime = TranscriptionConnection.openAIRealtime
        legacyRealtime.model = "gpt-4o-mini-transcribe"
        let legacy = SpeechProviderStoreSnapshotV1(
            providers: [.appleSpeech, legacyRealtime, .openAIHTTP],
            activeProviderID: TranscriptionConnection.openAIRealtimeID
        )

        let migrated = SpeechProviderSnapshotMigration.migrateV1(legacy)

        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.connections.count, 6)
        XCTAssertEqual(
            migrated.connections.first { $0.id == TranscriptionConnection.openAIRealtimeID }?.model,
            "gpt-realtime-whisper"
        )
        XCTAssertEqual(migrated.activeConnectionID, TranscriptionConnection.openAIRealtimeID)
    }

    func testSameAdapterSupportsMultipleIsolatedConnectionsAndSecrets() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = SpeechProviderStore(defaults: defaults, secretStore: secrets)

        var first = store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1)
        first.name = "Official"
        first.model = "gpt-4o-mini-transcribe"
        let firstID = store.createConnection(first, savingAPIKey: "first-key")!

        var second = store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1)
        second.name = "Internal"
        second.baseURL = "https://asr.example.com"
        second.model = "whisper-large-v3"
        second.isCustomEndpointApproved = true
        let secondID = store.createConnection(second, savingAPIKey: "second-key")!

        let persistedFirst = store.providers.first { $0.id == firstID }!
        let persistedSecond = store.providers.first { $0.id == secondID }!
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertNotEqual(persistedFirst.apiKeyReference, persistedSecond.apiKeyReference)
        XCTAssertEqual(secrets.secrets[persistedFirst.apiKeyReference!], "first-key")
        XCTAssertEqual(secrets.secrets[persistedSecond.apiKeyReference!], "second-key")
    }

    func testSecretBoundaryIncludesAdapterSchemeHostEffectivePortAndAuthentication() {
        var provider = TranscriptionConnection.openAIHTTP
        XCTAssertEqual(
            provider.secretBoundaryIdentifier,
            "openai-audio-transcriptions-http-v1|https|api.openai.com|443|bearer"
        )

        provider.baseURL = "https://asr.example.com:8443"
        provider.isCustomEndpointApproved = true
        XCTAssertEqual(
            provider.secretBoundaryIdentifier,
            "openai-audio-transcriptions-http-v1|https|asr.example.com|8443|bearer"
        )
    }

    func testBoundaryChangeRotatesReferenceAndDeletesOldSecretAfterPersistence() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = SpeechProviderStore(defaults: defaults, secretStore: secrets)

        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: "old-secret"
        )!
        var provider = store.providers.first { $0.id == id }!
        let oldReference = provider.apiKeyReference!
        provider.baseURL = "https://asr.example.com"
        provider.isCustomEndpointApproved = true

        XCTAssertTrue(store.updateProvider(provider, savingAPIKey: "new-secret"))
        let persisted = store.providers.first { $0.id == id }!
        XCTAssertNotEqual(persisted.apiKeyReference, oldReference)
        XCTAssertNil(secrets.secrets[oldReference])
        XCTAssertEqual(secrets.secrets[persisted.apiKeyReference!], "new-secret")
        XCTAssertTrue(secrets.deletedReferences.contains(oldReference))
    }

    func testBoundaryCleanupFailureRollsBackConfigAndNewSecret() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = SpeechProviderStore(defaults: defaults, secretStore: secrets)

        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: "old-secret"
        )!
        var provider = store.providers.first { $0.id == id }!
        let oldReference = provider.apiKeyReference!
        secrets.deletionFailures.insert(oldReference)
        provider.baseURL = "https://asr.example.com"
        provider.isCustomEndpointApproved = true

        XCTAssertFalse(store.updateProvider(provider, savingAPIKey: "new-secret"))
        let rolledBack = store.providers.first { $0.id == id }!
        XCTAssertEqual(rolledBack.apiKeyReference, oldReference)
        XCTAssertEqual(rolledBack.baseURL, "https://api.openai.com")
        XCTAssertEqual(secrets.secrets, [oldReference: "old-secret"])
        XCTAssertEqual(store.lastError, UIStrings.providerSecretCleanupFailed)

        let data = defaults.data(forKey: "flotis.transcriptionConnections.v3")!
        let snapshot = try JSONDecoder().decode(SpeechProviderStoreSnapshot.self, from: data)
        XCTAssertEqual(
            snapshot.connections.first { $0.id == id }?.apiKeyReference,
            oldReference
        )
    }

    func testDeleteCleanupFailureRollsBackProviderAndSnapshot() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = SpeechProviderStore(defaults: defaults, secretStore: secrets)
        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: "retained-secret"
        )!
        let reference = store.providers.first { $0.id == id }!.apiKeyReference!
        secrets.deletionFailures.insert(reference)

        XCTAssertFalse(store.deleteProvider(id: id))
        XCTAssertTrue(store.providers.contains { $0.id == id })
        XCTAssertEqual(secrets.secrets[reference], "retained-secret")

        let data = defaults.data(forKey: "flotis.transcriptionConnections.v3")!
        let snapshot = try JSONDecoder().decode(SpeechProviderStoreSnapshot.self, from: data)
        XCTAssertTrue(snapshot.connections.contains { $0.id == id })
    }

    func testCorruptV3UsesLastKnownGoodWithoutOverwritingCorruptBytes() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: "flotis.transcriptionConnections.v3")

        var recovered = TranscriptionConnection.openAIHTTP
        recovered.id = UUID()
        recovered.name = "Recovery Name"
        let recoverySnapshot = SpeechProviderStoreSnapshot(
            connections: [recovered],
            activeConnectionID: recovered.id
        )
        defaults.set(
            try JSONEncoder().encode(recoverySnapshot),
            forKey: "flotis.transcriptionConnections.v3.lastKnownGood"
        )

        let store = SpeechProviderStore(defaults: defaults, secretStore: InMemorySecretStore())

        XCTAssertEqual(store.providers.map(\.name), ["Recovery Name"])
        XCTAssertEqual(store.activeProviderID, recovered.id)
        XCTAssertEqual(defaults.data(forKey: "flotis.transcriptionConnections.v3"), corrupt)
        XCTAssertEqual(
            defaults.data(forKey: "flotis.transcriptionConnections.corruptBackup"),
            corrupt
        )
    }

    func testCorruptV2MigratesItsLastKnownGoodWithoutOverwritingLegacyBytes() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: "flotis.speechProviders.v2")

        var recovered = TranscriptionConnection.openAIHTTP
        recovered.id = UUID()
        recovered.name = "Recovered v2 connection"
        let legacy = SpeechProviderStoreSnapshotV2(
            schemaVersion: 2,
            presetCatalogVersion: 1,
            providers: [LegacySpeechProviderConfig(recovered)],
            activeProviderID: recovered.id
        )
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "flotis.speechProviders.v2.lastKnownGood"
        )

        let store = SpeechProviderStore(
            defaults: defaults,
            secretStore: InMemorySecretStore()
        )

        XCTAssertEqual(store.providers.map(\.name), ["Recovered v2 connection"])
        XCTAssertEqual(store.activeProviderID, recovered.id)
        XCTAssertEqual(defaults.data(forKey: "flotis.speechProviders.v2"), corrupt)
        XCTAssertEqual(
            defaults.data(forKey: "flotis.transcriptionConnections.corruptBackup"),
            corrupt
        )
        XCTAssertNotNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
    }

    func testCanonicalEncodingOmitsLegacyAndUnsupportedFields() throws {
        let appleData = try JSONEncoder().encode(TranscriptionConnection.appleSpeech)
        let appleJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: appleData) as? [String: Any]
        )

        XCTAssertNil(appleJSON["kind"])
        XCTAssertNil(appleJSON["wireProtocol"])
        XCTAssertNil(appleJSON["endpoint"])
        XCTAssertNil(appleJSON["authentication"])
        XCTAssertNil(appleJSON["audio"])
        XCTAssertNil(appleJSON["options"])
        XCTAssertNil(appleJSON["model"])

        let httpData = try JSONEncoder().encode(TranscriptionConnection.openAIHTTP)
        let httpJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: httpData) as? [String: Any]
        )
        let options = try XCTUnwrap(httpJSON["options"] as? [String: Any])
        XCTAssertNil(options["prompt"])
        XCTAssertNil(options["temperature"])
        XCTAssertNil(options["resourceID"])
        XCTAssertNil(options["twoPassRecognition"])
    }

    func testPlaintextAPIKeyNeverEntersV3Snapshot() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = SpeechProviderStore(defaults: defaults, secretStore: secrets)
        let plaintext = "unit-test-secret-must-not-be-persisted"

        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: plaintext
        )!
        let data = defaults.data(forKey: "flotis.transcriptionConnections.v3")!
        let serialized = String(data: data, encoding: .utf8)!

        XCTAssertFalse(serialized.contains(plaintext))
        XCTAssertTrue(serialized.contains(store.providers.first { $0.id == id }!.apiKeyReference!))
    }

    func testConnectionTestFingerprintExcludesNameAndIncludesConfigurationAndCredentialRevision() {
        var provider = TranscriptionConnection.openAIHTTP
        let original = provider.connectionTestFingerprint

        provider.name = "Renamed"
        XCTAssertEqual(provider.connectionTestFingerprint, original)

        provider.model = "whisper-large-v3"
        XCTAssertNotEqual(provider.connectionTestFingerprint, original)
        let modelChanged = provider.connectionTestFingerprint

        provider.credentialRevision += 1
        XCTAssertNotEqual(provider.connectionTestFingerprint, modelChanged)
    }

    func testConnectionTestInvalidatesOnModelAndCredentialChangesButNotRename() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = SpeechProviderStore(defaults: defaults, secretStore: secrets)
        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: "first-key"
        )!

        XCTAssertTrue(
            store.recordConnectionTest(
                providerID: id,
                outcome: .succeeded,
                safeSummary: "ok\nAuthorization: redacted"
            )
        )
        var provider = store.providers.first { $0.id == id }!
        XCTAssertTrue(provider.isConnectionTestCurrent)
        XCTAssertFalse(provider.lastConnectionTest!.safeSummary.contains("\n"))
        XCTAssertFalse(provider.lastConnectionTest!.safeSummary.lowercased().contains("authorization"))

        provider.name = "Only renamed"
        XCTAssertTrue(store.updateProvider(provider))
        provider = store.providers.first { $0.id == id }!
        XCTAssertTrue(provider.isConnectionTestCurrent)

        provider.model = "whisper-large-v3"
        XCTAssertTrue(store.updateProvider(provider))
        provider = store.providers.first { $0.id == id }!
        XCTAssertNil(provider.lastConnectionTest)

        provider.recordConnectionTest(outcome: .succeeded, safeSummary: "retested")
        XCTAssertTrue(store.updateProvider(provider))
        provider = store.providers.first { $0.id == id }!
        XCTAssertTrue(provider.isConnectionTestCurrent)
        let revision = provider.credentialRevision
        XCTAssertTrue(store.saveAPIKey("second-key", for: provider))
        provider = store.providers.first { $0.id == id }!
        XCTAssertEqual(provider.credentialRevision, revision + 1)
        XCTAssertNil(provider.lastConnectionTest)

        XCTAssertTrue(
            store.recordConnectionTest(
                providerID: id,
                outcome: .succeeded,
                safeSummary: "tested second key"
            )
        )
        let revisionBeforeClear = store.providers.first { $0.id == id }!.credentialRevision
        XCTAssertTrue(store.clearAPIKey(for: id))
        provider = store.providers.first { $0.id == id }!
        XCTAssertEqual(provider.credentialRevision, revisionBeforeClear + 1)
        XCTAssertNil(provider.lastConnectionTest)
    }

    func testCustomEndpointAndAmbiguousEndpointValidation() {
        var provider = TranscriptionConnection.openAIHTTP
        provider.baseURL = "https://transcription.example.com"
        XCTAssertNotNil(provider.configurationValidationError())

        provider.isCustomEndpointApproved = true
        XCTAssertNil(provider.configurationValidationError())

        provider.endpointPath = "/v1/audio/transcriptions?redirect=1"
        XCTAssertNotNil(provider.configurationValidationError())

        provider.endpointPath = "/v1/audio/transcriptions"
        provider.baseURL = "http://transcription.example.com"
        XCTAssertNotNil(provider.configurationValidationError())
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "FlotisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private final class InMemorySecretStore: KeychainSecretStoring {
    var secrets: [String: String] = [:]
    var deletionFailures: Set<String> = []
    var saveFailures: Set<String> = []
    var deletedReferences: [String] = []

    func save(secret: String, for reference: String) -> Bool {
        guard !saveFailures.contains(reference) else { return false }
        secrets[reference] = secret
        return true
    }

    func load(for reference: String) -> String? {
        secrets[reference]
    }

    func delete(for reference: String) -> Bool {
        guard !deletionFailures.contains(reference) else { return false }
        deletedReferences.append(reference)
        secrets.removeValue(forKey: reference)
        return true
    }
}
