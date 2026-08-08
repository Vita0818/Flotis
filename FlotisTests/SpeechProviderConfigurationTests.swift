import XCTest
@testable import Flotis

final class SpeechProviderConfigurationTests: XCTestCase {
    private var configurationRootURL: URL?
    private var configurationFileURL: URL?

    override func tearDown() {
        if let configurationRootURL {
            try? FileManager.default.removeItem(at: configurationRootURL)
        }
        configurationRootURL = nil
        configurationFileURL = nil
        super.tearDown()
    }

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

    func testFreshConfigHasEmptyProviderCatalogAndDoesNotPersistApple() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())

        XCTAssertTrue(store.providers.isEmpty)
        XCTAssertTrue(store.providerGroups.isEmpty)
        XCTAssertEqual(store.activeProviderID, TranscriptionConnection.appleSpeechID)
        XCTAssertEqual(store.activeProvider.adapterID, .appleOnDevice)
        let document = try configurationDocument()
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.providerOrder, [])
        XCTAssertEqual(document.provider, [:])
        XCTAssertEqual(document.model, "")
        XCTAssertFalse(document.provider.values.contains { $0.adapter == .appleOnDevice })
        XCTAssertNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
        XCTAssertNil(defaults.data(forKey: "flotis.speechProviders.v2"))
    }

    func testCanonicalV1MigratesToGroupedV2DropsAppleAndPreservesSlashModelIDs() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisConfigurationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let directory = root.appendingPathComponent("Flotis", isDirectory: true)
        let fileURL = directory.appendingPathComponent("config.json")
        configurationRootURL = root
        configurationFileURL = fileURL
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let legacyProviderID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let legacyJSON = #"""
        {
          "$schema": "https://flotis.app/config/v1",
          "schema_version": 1,
          "model": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/openai/gpt-4o-transcribe",
          "provider_order": [
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
          ],
          "enabled_providers": [
            "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
          ],
          "comparison": { "enabled": true },
          "provider": {
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa": {
              "name": "Apple Speech Recognition",
              "adapter": "apple-on-device",
              "options": { "language": "zh-CN" },
              "models": {}
            },
            "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb": {
              "name": "OpenRouter",
              "adapter": "openai-audio-transcriptions-http-v1",
              "options": {
                "baseURL": "https://openrouter.ai/api",
                "path": "/v1/audio/transcriptions",
                "apiKey": "legacy-openrouter-key",
                "language": "zh",
                "authentication": "bearer",
                "audio": { "format": "wav", "sampleRate": 16000, "channels": 1 },
                "transcription": { "responseMode": "json" }
              },
              "models": {
                "openai/gpt-4o-mini-transcribe": {},
                "openai/gpt-4o-transcribe": {}
              },
              "credentialRevision": 1
            }
          }
        }
        """#
        try Data(legacyJSON.utf8).write(to: fileURL)

        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())
        let expectedSelector = "\(legacyProviderID)/openai/gpt-4o-transcribe"

        XCTAssertEqual(store.providerGroups.map(\.id), [legacyProviderID])
        XCTAssertEqual(
            Set(store.providerGroups[0].modelIDs),
            ["openai/gpt-4o-mini-transcribe", "openai/gpt-4o-transcribe"]
        )
        XCTAssertEqual(store.activeModelSelector, expectedSelector)
        XCTAssertEqual(Set(store.providers.map(\.requestEncoding)), [.jsonBase64])
        XCTAssertEqual(store.load(for: "flotis.config.provider.\(legacyProviderID).apikey"), "legacy-openrouter-key")

        let migrated = try configurationDocument()
        XCTAssertEqual(migrated.schema, FlotisConfigurationDocument.schemaIdentifier)
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.model, expectedSelector)
        XCTAssertEqual(migrated.providerOrder, [legacyProviderID])
        XCTAssertFalse(migrated.provider.values.contains { $0.adapter == .appleOnDevice })
        XCTAssertFalse(String(decoding: try Data(contentsOf: fileURL), as: UTF8.self).contains("config/v1"))
    }

    func testMakeNewConnectionIsPureDraftAndDoesNotPersistUntilCreate() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())
        let providersBeforeDraft = store.providers
        let snapshotBeforeDraft = try! Data(contentsOf: configurationFileURL!)

        var draft = store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1)
        draft.name = "Cancelled draft"
        draft.model = "whisper-large-v3"

        XCTAssertEqual(store.providers, providersBeforeDraft)
        XCTAssertEqual(
            try! Data(contentsOf: configurationFileURL!),
            snapshotBeforeDraft
        )
        XCTAssertFalse(store.providers.contains { $0.id == draft.id })
    }

    func testUnsavedCredentialTestRecordRequiresExpectedRevisionForCreateAndUpdate() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())

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

        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())

        let networkConnections = connections.filter { $0.adapterID != .appleOnDevice }
        XCTAssertEqual(store.providers.map(\.name), networkConnections.map(\.name))
        XCTAssertEqual(store.activeProvider.name, custom.name)
        XCTAssertEqual(
            store.activeModelSelector,
            "\(custom.id.uuidString.lowercased())/\(custom.model)"
        )
        XCTAssertEqual(
            store.providers.map(\.adapterID),
            [
                .openAIRealtimeTranscriptionGA,
                .openAIAudioTranscriptionsHTTPV1,
                .openAIAudioTranscriptionsHTTPV1,
                .dashScopeParaformerWSV1,
                .volcengineBigASRWSV3,
                .glmASRHTTPSSEV4
            ]
        )
        let migratedCustom = store.providers.first {
            $0.configurationProviderID == custom.id.uuidString.lowercased()
        }!
        XCTAssertEqual(migratedCustom.apiKeyReference, "legacy-custom-key-reference")
        XCTAssertEqual(migratedCustom.inputAudioFormat, "m4a")
        XCTAssertEqual(migratedCustom.displayNameForUI, "OpenAI HTTP")
        XCTAssertEqual(defaults.data(forKey: "flotis.speechProviders.v2"), v2Data)
        XCTAssertNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
        let document = try configurationDocument()
        XCTAssertEqual(
            document.providerOrder,
            networkConnections.map { $0.id.uuidString.lowercased() }
        )
        XCTAssertFalse(document.provider.values.contains { $0.adapter == .appleOnDevice })
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

    func testLegacySplitSourcesMigrateOnceIntoCanonicalConfig() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        var connection = TranscriptionConnection.openAIHTTP
        connection.id = UUID()
        connection.name = "Migrated connection"
        connection.apiKeyReference = "legacy-reference"
        let snapshot = SpeechProviderStoreSnapshot(
            connections: [.appleSpeech, connection],
            activeConnectionID: connection.id
        )
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: "flotis.transcriptionConnections.v3"
        )
        let comparison = LegacyComparisonPreferencesFixture(
            schemaVersion: 1,
            isEnabled: true,
            connectionIDs: [TranscriptionConnection.appleSpeechID, connection.id]
        )
        defaults.set(
            try JSONEncoder().encode(comparison),
            forKey: "flotis.transcriptionComparison.v1"
        )
        secrets.secrets["legacy-reference"] = "legacy-api-key"

        let first = makeStore(defaults: defaults, secretStore: secrets)
        let selector = "\(connection.id.uuidString.lowercased())/\(connection.model)"
        XCTAssertEqual(first.activeModelSelector, selector)
        XCTAssertEqual(first.load(for: "legacy-reference"), "legacy-api-key")
        let migratedDocument = try configurationDocument()
        XCTAssertFalse(migratedDocument.comparison.enabled)
        XCTAssertEqual(migratedDocument.comparison.models, [selector])
        XCTAssertEqual(
            migratedDocument.enabledProviders,
            [connection.id.uuidString.lowercased()]
        )
        XCTAssertFalse(migratedDocument.provider.values.contains { $0.adapter == .appleOnDevice })

        secrets.secrets["legacy-reference"] = "changed-legacy-key"
        var changedSnapshot = snapshot
        changedSnapshot.connections[1].name = "Changed legacy name"
        defaults.set(
            try JSONEncoder().encode(changedSnapshot),
            forKey: "flotis.transcriptionConnections.v3"
        )

        let reloaded = makeStore(defaults: defaults, secretStore: secrets)
        XCTAssertEqual(reloaded.activeProvider.name, "Migrated connection")
        XCTAssertEqual(reloaded.load(for: "legacy-reference"), "legacy-api-key")
    }

    func testSameAdapterSupportsMultipleIsolatedConnectionsAndSecrets() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = makeStore(defaults: defaults, secretStore: secrets)

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
        XCTAssertEqual(store.load(for: persistedFirst.apiKeyReference!), "first-key")
        XCTAssertEqual(store.load(for: persistedSecond.apiKeyReference!), "second-key")
        XCTAssertTrue(secrets.secrets.isEmpty)
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
        let store = makeStore(defaults: defaults, secretStore: secrets)

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
        XCTAssertNil(store.load(for: oldReference))
        XCTAssertEqual(store.load(for: persisted.apiKeyReference!), "new-secret")
        XCTAssertTrue(secrets.deletedReferences.isEmpty)
    }

    func testBoundaryUpdateRollsBackConnectionAndSecretWhenConfigIsMalformed() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = makeStore(defaults: defaults, secretStore: secrets)

        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: "old-secret"
        )!
        var provider = store.providers.first { $0.id == id }!
        let oldReference = provider.apiKeyReference!
        let malformed = Data("{malformed-config".utf8)
        try malformed.write(to: configurationFileURL!, options: .atomic)
        provider.baseURL = "https://asr.example.com"
        provider.isCustomEndpointApproved = true

        XCTAssertFalse(store.updateProvider(provider, savingAPIKey: "new-secret"))
        let rolledBack = store.providers.first { $0.id == id }!
        XCTAssertEqual(rolledBack.apiKeyReference, oldReference)
        XCTAssertEqual(rolledBack.baseURL, "https://api.openai.com")
        XCTAssertEqual(store.load(for: oldReference), "old-secret")
        XCTAssertTrue(secrets.secrets.isEmpty)
        XCTAssertEqual(store.lastError, UIStrings.providerConfigSaveFailed)
        XCTAssertEqual(try Data(contentsOf: configurationFileURL!), malformed)
    }

    func testDeleteRollsBackProviderAndSecretWhenConfigIsMalformed() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = makeStore(defaults: defaults, secretStore: secrets)
        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: "retained-secret"
        )!
        let reference = store.providers.first { $0.id == id }!.apiKeyReference!
        let malformed = Data("{malformed-config".utf8)
        try malformed.write(to: configurationFileURL!, options: .atomic)

        XCTAssertFalse(store.deleteProvider(id: id))
        XCTAssertTrue(store.providers.contains { $0.id == id })
        XCTAssertEqual(store.load(for: reference), "retained-secret")
        XCTAssertTrue(secrets.secrets.isEmpty)
        XCTAssertEqual(try Data(contentsOf: configurationFileURL!), malformed)
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

        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())

        XCTAssertEqual(store.providers.map(\.name), ["Recovery Name"])
        XCTAssertEqual(store.activeProvider.name, "Recovery Name")
        XCTAssertEqual(defaults.data(forKey: "flotis.transcriptionConnections.v3"), corrupt)
        XCTAssertNil(defaults.data(forKey: "flotis.transcriptionConnections.corruptBackup"))
        XCTAssertEqual(try configurationDocument().providerOrder, [recovered.id.uuidString.lowercased()])
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

        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())

        XCTAssertEqual(store.providers.map(\.name), ["Recovered v2 connection"])
        XCTAssertEqual(store.activeProvider.name, "Recovered v2 connection")
        XCTAssertEqual(defaults.data(forKey: "flotis.speechProviders.v2"), corrupt)
        XCTAssertNil(defaults.data(forKey: "flotis.transcriptionConnections.corruptBackup"))
        XCTAssertNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
        XCTAssertEqual(try configurationDocument().providerOrder, [recovered.id.uuidString.lowercased()])
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

    func testConfigJSONStoresEndpointModelAndAPIKeyTogetherWithoutSeparateSecretWrite() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secrets = InMemorySecretStore()
        let store = makeStore(defaults: defaults, secretStore: secrets)
        let plaintext = "unit-test-secret-in-single-config"

        let id = store.createConnection(
            store.makeNewConnection(adapterID: .openAIAudioTranscriptionsHTTPV1),
            savingAPIKey: plaintext
        )!
        let data = try Data(contentsOf: configurationFileURL!)
        let serialized = try XCTUnwrap(String(data: data, encoding: .utf8))
        let document = try configurationDocument()
        let route = try XCTUnwrap(store.providers.first { $0.id == id })
        let providerID = try XCTUnwrap(route.configurationProviderID)
        let provider = try XCTUnwrap(document.provider[providerID])

        XCTAssertEqual(document.schema, FlotisConfigurationDocument.schemaIdentifier)
        XCTAssertEqual(provider.options.baseURL, "https://api.openai.com")
        XCTAssertEqual(provider.models.keys.first, "gpt-4o-mini-transcribe")
        XCTAssertEqual(provider.options.apiKey, plaintext)
        XCTAssertTrue(serialized.contains(plaintext))
        XCTAssertTrue(secrets.secrets.isEmpty)
        XCTAssertNil(defaults.data(forKey: "flotis.transcriptionConnections.v3"))
    }

    func testOneOpenRouterProviderOwnsMultipleModelsAndOneSharedCredential() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(defaults: defaults, secretStore: InMemorySecretStore())
        var draft = store.makeNewConnection(
            adapterID: .openAIAudioTranscriptionsHTTPV1
        )
        draft.name = "OpenRouter"
        draft.baseURL = "https://openrouter.ai/api"
        draft.endpointPath = "/v1/audio/transcriptions"
        draft.isCustomEndpointApproved = true
        let models = [
            "openai/gpt-4o-mini-transcribe",
            "openai/gpt-4o-transcribe"
        ]

        let providerID = try XCTUnwrap(
            store.saveProviderGroup(
                existingProviderID: nil,
                draft: draft,
                modelIDs: models,
                selectedModelID: models[0],
                modelDisplayNames: [
                    models[0]: "GPT-4o mini transcribe",
                    models[1]: "GPT-4o transcribe"
                ],
                savingAPIKey: "openrouter-test-key"
            )
        )

        XCTAssertEqual(providerID, "openrouter")
        XCTAssertEqual(store.providerGroups.count, 1)
        XCTAssertEqual(store.providerGroups[0].modelIDs, models)
        XCTAssertEqual(store.providers.map(\.model), models)
        XCTAssertEqual(Set(store.providers.map(\.baseURL)), ["https://openrouter.ai/api"])
        XCTAssertEqual(Set(store.providers.compactMap(\.apiKeyReference)).count, 1)
        XCTAssertEqual(Set(store.providers.map(\.id)).count, 2)
        XCTAssertEqual(
            store.activeModelSelector,
            "openrouter/openai/gpt-4o-mini-transcribe"
        )

        let document = try configurationDocument()
        let configuration = try XCTUnwrap(document.provider["openrouter"])
        XCTAssertEqual(configuration.options.apiKey, "openrouter-test-key")
        XCTAssertEqual(
            configuration.options.transcription?.requestEncoding,
            .jsonBase64
        )
        XCTAssertEqual(Set(configuration.models.keys), Set(models))
        XCTAssertEqual(
            configuration.models[models[0]]?.name,
            "GPT-4o mini transcribe"
        )
        XCTAssertEqual(
            configuration.models[models[1]]?.name,
            "GPT-4o transcribe"
        )
        XCTAssertEqual(document.providerOrder, ["openrouter"])
        XCTAssertFalse(document.provider.values.contains { $0.adapter == .appleOnDevice })
    }

    func testConfigJSONAndLockUsePrivatePermissions() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        _ = makeStore(defaults: defaults, secretStore: InMemorySecretStore())
        let directoryURL = try XCTUnwrap(configurationFileURL).deletingLastPathComponent()

        XCTAssertEqual(try posixPermissions(at: directoryURL), 0o700)
        XCTAssertEqual(try posixPermissions(at: XCTUnwrap(configurationFileURL)), 0o600)
        XCTAssertEqual(
            try posixPermissions(at: directoryURL.appendingPathComponent(".config.lock")),
            0o600
        )
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
        let store = makeStore(defaults: defaults, secretStore: secrets)
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
        let configurationProviderID = provider.configurationProviderID
        XCTAssertTrue(provider.isConnectionTestCurrent)
        XCTAssertFalse(provider.lastConnectionTest!.safeSummary.contains("\n"))
        XCTAssertFalse(provider.lastConnectionTest!.safeSummary.lowercased().contains("authorization"))

        provider.name = "Only renamed"
        XCTAssertTrue(store.updateProvider(provider))
        provider = store.providers.first { $0.id == id }!
        XCTAssertTrue(provider.isConnectionTestCurrent)

        provider.model = "whisper-large-v3"
        XCTAssertTrue(store.updateProvider(provider))
        provider = store.providers.first {
            $0.configurationProviderID == configurationProviderID
        }!
        XCTAssertNil(provider.lastConnectionTest)

        provider.recordConnectionTest(outcome: .succeeded, safeSummary: "retested")
        XCTAssertTrue(store.updateProvider(provider))
        provider = store.providers.first {
            $0.configurationProviderID == configurationProviderID
        }!
        XCTAssertTrue(provider.isConnectionTestCurrent)
        let revision = provider.credentialRevision
        XCTAssertTrue(store.saveAPIKey("second-key", for: provider))
        provider = store.providers.first {
            $0.configurationProviderID == configurationProviderID
        }!
        XCTAssertEqual(provider.credentialRevision, revision + 1)
        XCTAssertNil(provider.lastConnectionTest)

        XCTAssertTrue(
            store.recordConnectionTest(
                providerID: provider.id,
                outcome: .succeeded,
                safeSummary: "tested second key"
            )
        )
        let revisionBeforeClear = provider.credentialRevision
        XCTAssertTrue(store.clearAPIKey(for: provider.id))
        provider = store.providers.first {
            $0.configurationProviderID == configurationProviderID
        }!
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

    func testLocalSecretStorePersistsReplacesAndDeletesWithPrivatePermissions() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisLocalSecretStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = rootURL.appendingPathComponent("Flotis", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("secrets.json")
        let store = LocalSecretStore(fileURL: fileURL)

        XCTAssertTrue(store.save(secret: "  synthetic-secret-one  ", for: " reference-one "))
        XCTAssertEqual(store.load(for: "reference-one"), "synthetic-secret-one")
        XCTAssertEqual(
            LocalSecretStore(fileURL: fileURL).load(for: "reference-one"),
            "synthetic-secret-one"
        )
        XCTAssertEqual(try posixPermissions(at: directoryURL), 0o700)
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)
        XCTAssertEqual(
            try posixPermissions(
                at: directoryURL.appendingPathComponent(".secrets.lock")
            ),
            0o600
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: fileURL.path
        )
        XCTAssertEqual(store.load(for: "reference-one"), "synthetic-secret-one")
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)

        XCTAssertTrue(store.save(secret: "replacement-secret", for: "reference-one"))
        XCTAssertTrue(store.save(secret: "synthetic-secret-two", for: "reference-two"))
        XCTAssertEqual(store.load(for: "reference-one"), "replacement-secret")
        XCTAssertEqual(store.load(for: "reference-two"), "synthetic-secret-two")

        XCTAssertTrue(store.delete(for: "reference-one"))
        XCTAssertNil(store.load(for: "reference-one"))
        XCTAssertEqual(store.load(for: "reference-two"), "synthetic-secret-two")
        XCTAssertTrue(store.delete(for: "reference-two"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLocalSecretStoreSerializesConcurrentInstancesWithoutLostUpdates() {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisConcurrentSecretStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL
            .appendingPathComponent("Flotis", isDirectory: true)
            .appendingPathComponent("secrets.json")
        let resultLock = NSLock()
        var saveResults: [Int: Bool] = [:]

        DispatchQueue.concurrentPerform(iterations: 32) { index in
            let result = LocalSecretStore(fileURL: fileURL).save(
                secret: "synthetic-secret-\(index)",
                for: "reference-\(index)"
            )
            resultLock.lock()
            saveResults[index] = result
            resultLock.unlock()
        }

        XCTAssertEqual(saveResults.count, 32)
        XCTAssertTrue(saveResults.values.allSatisfy { $0 })
        let reloaded = LocalSecretStore(fileURL: fileURL)
        for index in 0..<32 {
            XCTAssertEqual(
                reloaded.load(for: "reference-\(index)"),
                "synthetic-secret-\(index)"
            )
        }
    }

    func testLocalSecretStoreRefusesToOverwriteMalformedData() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisMalformedSecretStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = rootURL.appendingPathComponent("Flotis", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("secrets.json")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let malformedData = Data("{not-valid-json".utf8)
        try malformedData.write(to: fileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )

        let store = LocalSecretStore(fileURL: fileURL)
        XCTAssertNil(store.load(for: "reference"))
        XCTAssertFalse(store.save(secret: "synthetic-secret", for: "reference"))
        XCTAssertEqual(try Data(contentsOf: fileURL), malformedData)
    }

    func testLocalSecretStoreRejectsSymbolicLinkDestination() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlotisSymlinkSecretStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = rootURL.appendingPathComponent("Flotis", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("secrets.json")
        let targetURL = rootURL.appendingPathComponent("unrelated.json")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let originalTargetData = Data("do-not-change".utf8)
        try originalTargetData.write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: fileURL,
            withDestinationURL: targetURL
        )

        let store = LocalSecretStore(fileURL: fileURL)
        XCTAssertNil(store.load(for: "reference"))
        XCTAssertFalse(store.save(secret: "synthetic-secret", for: "reference"))
        XCTAssertFalse(store.delete(for: "reference"))
        XCTAssertEqual(try Data(contentsOf: targetURL), originalTargetData)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "FlotisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeStore(
        defaults: UserDefaults,
        secretStore: SecretStoring
    ) -> SpeechProviderStore {
        if configurationRootURL == nil {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "FlotisConfigurationTests-\(UUID().uuidString)",
                isDirectory: true
            )
            configurationRootURL = root
            configurationFileURL = root
                .appendingPathComponent("Flotis", isDirectory: true)
                .appendingPathComponent("config.json")
        }
        return SpeechProviderStore(
            defaults: defaults,
            secretStore: secretStore,
            configurationStore: FlotisConfigurationStore(fileURL: configurationFileURL!)
        )
    }

    private func configurationDocument() throws -> FlotisConfigurationDocument {
        let data = try Data(contentsOf: XCTUnwrap(configurationFileURL))
        return try JSONDecoder().decode(FlotisConfigurationDocument.self, from: data)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}

private struct LegacyComparisonPreferencesFixture: Encodable {
    let schemaVersion: Int
    let isEnabled: Bool
    let connectionIDs: [UUID]
}

private final class InMemorySecretStore: SecretStoring {
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
