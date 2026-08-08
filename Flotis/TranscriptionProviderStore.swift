import Foundation

struct TranscriptionConnectionStoreSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 3
    static let currentPresetCatalogVersion = 1

    var schemaVersion: Int
    var presetCatalogVersion: Int
    var connections: [TranscriptionConnection]
    var activeConnectionID: UUID

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        presetCatalogVersion: Int = Self.currentPresetCatalogVersion,
        connections: [TranscriptionConnection],
        activeConnectionID: UUID
    ) {
        self.schemaVersion = schemaVersion
        self.presetCatalogVersion = presetCatalogVersion
        self.connections = connections
        self.activeConnectionID = activeConnectionID
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        presetCatalogVersion: Int = Self.currentPresetCatalogVersion,
        providers: [TranscriptionConnection],
        activeProviderID: UUID
    ) {
        self.init(
            schemaVersion: schemaVersion,
            presetCatalogVersion: presetCatalogVersion,
            connections: providers,
            activeConnectionID: activeProviderID
        )
    }

    var providers: [TranscriptionConnection] {
        get { connections }
        set { connections = newValue }
    }

    var activeProviderID: UUID {
        get { activeConnectionID }
        set { activeConnectionID = newValue }
    }
}

typealias SpeechProviderStoreSnapshot = TranscriptionConnectionStoreSnapshot

struct SpeechProviderStoreSnapshotV2: Codable, Equatable {
    var schemaVersion: Int
    var presetCatalogVersion: Int
    var providers: [LegacySpeechProviderConfig]
    var activeProviderID: UUID
}

struct SpeechProviderStoreSnapshotV1: Codable, Equatable {
    var providers: [LegacySpeechProviderConfig]
    var activeProviderID: UUID

    init(providers: [TranscriptionConnection], activeProviderID: UUID) {
        self.providers = providers.map(LegacySpeechProviderConfig.init)
        self.activeProviderID = activeProviderID
    }
}

enum SpeechProviderSnapshotMigration {
    static func migrateV2(_ legacy: SpeechProviderStoreSnapshotV2) -> SpeechProviderStoreSnapshot {
        normalizedSnapshot(
            connections: legacy.providers.map { $0.migratedConnection() },
            activeConnectionID: legacy.activeProviderID
        )
    }

    static func migrateV1(_ legacy: SpeechProviderStoreSnapshotV1) -> SpeechProviderStoreSnapshot {
        var connections = legacy.providers.map { $0.migratedConnection() }
        let existingIDs = Set(connections.map(\.id))
        for builtIn in TranscriptionConnection.defaultProviders
        where TranscriptionConnection.v2AddedPresetIDs.contains(builtIn.id)
            && !existingIDs.contains(builtIn.id) {
            connections.append(builtIn)
        }
        return normalizedSnapshot(
            connections: connections,
            activeConnectionID: legacy.activeProviderID
        )
    }

    static func normalizeV3(_ snapshot: SpeechProviderStoreSnapshot) -> SpeechProviderStoreSnapshot {
        normalizedSnapshot(
            connections: snapshot.connections,
            activeConnectionID: snapshot.activeConnectionID
        )
    }

    // Compatibility spelling retained for callers compiled against the v2 store.
    static func normalizeV2(_ snapshot: SpeechProviderStoreSnapshot) -> SpeechProviderStoreSnapshot {
        normalizeV3(snapshot)
    }

    static func uniqueProviders(
        _ providers: [TranscriptionConnection]
    ) -> [TranscriptionConnection] {
        var seen = Set<UUID>()
        return providers.filter { seen.insert($0.id).inserted }
    }

    static func validActiveID(
        requested: UUID,
        providers: [TranscriptionConnection]
    ) -> UUID {
        if providers.contains(where: { $0.id == requested }) {
            return requested
        }
        return providers.first?.id ?? TranscriptionConnection.appleSpeechID
    }

    private static func normalizedSnapshot(
        connections: [TranscriptionConnection],
        activeConnectionID: UUID
    ) -> SpeechProviderStoreSnapshot {
        let normalized = uniqueProviders(connections.map { $0.normalizedForProtocol() })
        let nonempty = normalized.isEmpty ? [TranscriptionConnection.appleSpeech] : normalized
        return SpeechProviderStoreSnapshot(
            connections: nonempty,
            activeConnectionID: validActiveID(
                requested: activeConnectionID,
                providers: nonempty
            )
        )
    }
}

final class SpeechProviderStore: ObservableObject, SecretStoring {
    static let shared = SpeechProviderStore()

    /// Canonical provider groups from config.json. A group owns one endpoint and
    /// credential, and may expose many model routes.
    @Published private(set) var providerGroups: [SpeechProviderGroup] = []
    /// Runtime routes derived from providerGroups. Apple is intentionally absent.
    @Published private(set) var providers: [TranscriptionConnection] = []
    @Published private(set) var activeProviderID: UUID
    @Published private(set) var activeModelSelector = ""
    @Published var lastError: String?

    private let configKeyV3 = "flotis.transcriptionConnections.v3"
    private let configKeyV2 = "flotis.speechProviders.v2"
    private let configKeyV1 = "flotis.speechProviders.v1"
    private let lastKnownGoodKey = "flotis.transcriptionConnections.v3.lastKnownGood"
    private let lastKnownGoodKeyV2 = "flotis.speechProviders.v2.lastKnownGood"
    private let legacyComparisonKey = "flotis.transcriptionComparison.v1"
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults
    private let legacySecretStore: SecretStoring
    private let configurationStore: FlotisConfigurationStore
    private let apiKeyLock = NSLock()
    private var apiKeys: [String: String] = [:]
    private var providerOrder: [String] = []
    private var providerConfigurations: [String: FlotisProviderConfiguration] = [:]

    init(
        defaults: UserDefaults = .standard,
        secretStore: SecretStoring = LocalSecretStore.shared,
        configurationStore: FlotisConfigurationStore = .shared
    ) {
        self.defaults = defaults
        legacySecretStore = secretStore
        self.configurationStore = configurationStore
        activeProviderID = TranscriptionConnection.appleSpeechID
        load()
    }

    /// Apple Speech remains an internal no-network fallback for an empty catalog,
    /// but it is never serialized as a configurable provider.
    var activeProvider: TranscriptionConnection {
        providers.first { $0.id == activeProviderID } ?? .appleSpeech
    }

    var availableModelSelectors: Set<String> {
        Set(providers.compactMap(\.configurationModelSelector))
    }

    func providerGroup(id: String) -> SpeechProviderGroup? {
        providerConfigurations[id].map {
            SpeechProviderGroup(id: id, configuration: $0)
        }
    }

    func modelSelector(for connectionID: UUID) -> String? {
        providers.first { $0.id == connectionID }?.configurationModelSelector
    }

    func modelDisplayName(for connection: TranscriptionConnection) -> String? {
        guard let providerID = connection.configurationProviderID else { return nil }
        return providerConfigurations[providerID]?
            .models[connection.model]?
            .name?
            .flotisTrimmedNonempty
    }

    @discardableResult
    func setActiveProvider(id: UUID) -> Bool {
        guard let provider = providers.first(where: { $0.id == id }),
              let selector = provider.configurationModelSelector else {
            lastError = UIStrings.providerNotFound
            return false
        }
        if let error = providerReadinessError(for: provider) {
            lastError = error
            return false
        }

        let oldSelector = activeModelSelector
        activeModelSelector = selector
        rebuildDerivedState()
        guard saveCatalog() else {
            activeModelSelector = oldSelector
            rebuildDerivedState()
            return false
        }
        return true
    }

    func makeNewConnection(adapterID: TranscriptionAdapterID) -> TranscriptionConnection {
        let id = UUID()
        let name = TranscriptionProviderPreset.defaultPreset(for: adapterID)?.displayName
            ?? adapterID.displayName
        var connection = TranscriptionConnection(id: id, name: name, adapterID: adapterID)
        if let preset = TranscriptionProviderPreset.defaultPreset(for: adapterID) {
            connection = preset.applying(to: connection)
        }
        connection.apiKeyReference = nil
        var normalized = connection.normalizedForProtocol()
        if adapterID == .openAIAudioTranscriptionsHTTPV1 {
            // Keep a new draft's encoding implicit until its final host is known.
            // The editor still displays multipart through the computed default,
            // while save-time normalization selects JSON+Base64 for OpenRouter.
            normalized.options.requestEncoding = nil
        }
        return normalized
    }

    /// Saves one provider and all of its models in one atomic config.json update.
    /// `existingProviderID == nil` creates a semantic provider ID from the name.
    @discardableResult
    func saveProviderGroup(
        existingProviderID: String?,
        draft: TranscriptionConnection,
        modelIDs: [String],
        selectedModelID: String,
        modelDisplayNames: [String: String] = [:],
        savingAPIKey apiKey: String? = nil
    ) -> String? {
        guard draft.adapterID != .appleOnDevice else {
            lastError = UIStrings.providerConfigSaveFailed
            return nil
        }

        let normalizedModels = normalizedModelIDs(modelIDs)
        guard !normalizedModels.isEmpty,
              normalizedModels.count <= FlotisConfigurationStore.maximumModelCountPerProvider,
              normalizedModels.contains(selectedModelID),
              normalizedModels.allSatisfy(FlotisModelSelector.isValidModelID) else {
            lastError = UIStrings.providerConfigSaveFailed
            return nil
        }
        let trimmedAPIKey = normalizedKey(apiKey)
        if apiKey != nil, trimmedAPIKey == nil {
            lastError = UIStrings.apiKeySaveFailed
            return nil
        }

        let providerID: String
        let oldConfiguration: FlotisProviderConfiguration?
        if let existingProviderID {
            guard FlotisModelSelector.isValidProviderID(existingProviderID),
                  let existing = providerConfigurations[existingProviderID] else {
                lastError = UIStrings.providerNotFound
                return nil
            }
            providerID = existingProviderID
            oldConfiguration = existing
        } else {
            providerID = uniqueProviderID(for: draft.name)
            oldConfiguration = nil
        }

        let oldOrder = providerOrder
        let oldConfigurations = providerConfigurations
        let oldActiveSelector = activeModelSelector
        let oldAPIKeys = apiKeySnapshot()

        var candidate = draft.normalizedForProtocol()
        candidate.configurationProviderID = providerID
        candidate.model = selectedModelID
        let oldRepresentative = oldConfiguration.flatMap { configuration in
            configuration.models.keys.sorted().first.flatMap {
                try? configuration.connection(providerID: providerID, modelID: $0)
            }
        }
        let secretBoundaryChanged = oldRepresentative.map {
            $0.secretBoundaryIdentifier != candidate.secretBoundaryIdentifier
        } ?? false
        let credentialChanged = secretBoundaryChanged || trimmedAPIKey != nil
        var revision = oldConfiguration?.credentialRevision ?? 0
        if oldConfiguration == nil, trimmedAPIKey != nil {
            revision = max(1, candidate.credentialRevision)
        } else if credentialChanged {
            revision += 1
        }
        candidate.credentialRevision = revision

        let preservedKey = oldConfiguration?.options.apiKey?.flotisTrimmedNonempty
        // Never carry a credential to a different adapter/scheme/host/port/auth
        // boundary unless the user explicitly enters it for that destination.
        let resolvedKey = trimmedAPIKey ?? (secretBoundaryChanged ? nil : preservedKey)
        var options = FlotisProviderOptions(connection: candidate, apiKey: resolvedKey)
        if candidate.protocolSchema.requiresAPIKey {
            if secretBoundaryChanged {
                options.apiKeyReference = makeAPIKeyReference(
                    providerID: providerID,
                    revision: max(1, revision)
                )
            } else {
                options.apiKeyReference = oldConfiguration?.resolvedAPIKeyReference(
                    providerID: providerID
                ) ?? makeAPIKeyReference(providerID: providerID, revision: max(1, revision))
            }
        } else {
            options.apiKey = nil
            options.apiKeyReference = nil
        }

        var models = Dictionary(uniqueKeysWithValues: normalizedModels.map { modelID in
            var model = oldConfiguration?.models[modelID] ?? FlotisModelConfiguration()
            if let displayName = modelDisplayNames[modelID] {
                model.name = displayName.flotisTrimmedNonempty
            }
            return (modelID, model)
        })
        var configuration = FlotisProviderConfiguration(
            name: candidate.name,
            adapter: candidate.adapterID,
            options: options,
            models: models,
            credentialRevision: revision == 0 ? nil : revision
        )

        // A test belongs to one model route. Shared-provider changes invalidate
        // sibling tests whose fingerprint no longer matches.
        for modelID in normalizedModels {
            guard let route = try? configuration.connection(
                providerID: providerID,
                modelID: modelID
            ) else {
                lastError = UIStrings.providerConfigSaveFailed
                return nil
            }
            var record = models[modelID]?.lastConnectionTest
            if modelID == selectedModelID, let submitted = candidate.lastConnectionTest {
                record = submitted
            }
            if record?.adapterVersion != route.protocolSchema.adapterVersion
                || record?.configurationFingerprint != route.connectionTestFingerprint {
                record = nil
            }
            models[modelID]?.lastConnectionTest = record
        }
        configuration.models = models

        guard let routes = try? configuration.connections(providerID: providerID),
              routes.allSatisfy({ $0.configurationValidationError() == nil }) else {
            lastError = UIStrings.providerConfigSaveFailed
            return nil
        }

        if oldConfiguration == nil {
            providerOrder.append(providerID)
        }
        providerConfigurations[providerID] = configuration
        activeModelSelector = FlotisModelSelector(
            providerID: providerID,
            modelID: selectedModelID
        )!.rawValue
        rebuildDerivedState()

        guard saveCatalog() else {
            providerOrder = oldOrder
            providerConfigurations = oldConfigurations
            activeModelSelector = oldActiveSelector
            replaceAPIKeys(oldAPIKeys)
            rebuildDerivedState()
            return nil
        }
        lastError = nil
        return providerID
    }

    @discardableResult
    func createConnection(
        _ draft: TranscriptionConnection,
        savingAPIKey apiKey: String? = nil
    ) -> UUID? {
        let modelID = draft.model
        guard let providerID = saveProviderGroup(
            existingProviderID: nil,
            draft: draft,
            modelIDs: [modelID],
            selectedModelID: modelID,
            savingAPIKey: apiKey
        ),
        let selector = FlotisModelSelector(providerID: providerID, modelID: modelID) else {
            return nil
        }
        return providers.first { $0.configurationModelSelector == selector.rawValue }?.id
    }

    @discardableResult
    func addProvider(kind: SpeechProviderKind) -> UUID {
        let adapterID: TranscriptionAdapterID
        switch kind {
        case .appleSpeechLive:
            // Local Apple recognition is not a config.json provider.
            return TranscriptionConnection.appleSpeechID
        case .openAIRealtimeTranscription:
            adapterID = .openAIRealtimeTranscriptionGA
        case .openAIHTTPTranscription:
            adapterID = .openAIAudioTranscriptionsHTTPV1
        }
        var draft = makeNewConnection(adapterID: adapterID)
        draft.name = kind == .openAIRealtimeTranscription
            ? UIStrings.customRealtime
            : UIStrings.customHTTP
        return createConnection(draft) ?? draft.id
    }

    @discardableResult
    func addProvider(
        preset wireProtocol: SpeechProviderWireProtocol,
        customName: String? = nil
    ) -> UUID {
        if wireProtocol.adapterID == .appleOnDevice {
            return TranscriptionConnection.appleSpeechID
        }
        var draft = makeNewConnection(adapterID: wireProtocol.adapterID)
        if let customName { draft.name = customName }
        return createConnection(draft) ?? draft.id
    }

    @discardableResult
    func updateProvider(_ provider: TranscriptionConnection) -> Bool {
        updateProvider(provider, savingAPIKey: nil)
    }

    @discardableResult
    func updateProvider(
        _ provider: TranscriptionConnection,
        savingAPIKey apiKey: String?
    ) -> Bool {
        guard let oldRoute = providers.first(where: { $0.id == provider.id }),
              let providerID = oldRoute.configurationProviderID,
              let oldModelID = oldRoute.configurationModelSelector.flatMap({
                  FlotisModelSelector(rawValue: $0)?.modelID
              }),
              let group = providerConfigurations[providerID] else {
            lastError = UIStrings.providerNotFound
            return false
        }
        var modelIDs = group.models.keys.sorted()
        if provider.model != oldModelID {
            guard !modelIDs.contains(provider.model) else {
                lastError = UIStrings.providerConfigSaveFailed
                return false
            }
            modelIDs.removeAll { $0 == oldModelID }
            modelIDs.append(provider.model)
        }
        return saveProviderGroup(
            existingProviderID: providerID,
            draft: provider,
            modelIDs: modelIDs,
            selectedModelID: provider.model,
            savingAPIKey: apiKey
        ) != nil
    }

    @discardableResult
    func deleteProvider(id: UUID) -> Bool {
        guard let route = providers.first(where: { $0.id == id }),
              let providerID = route.configurationProviderID,
              providerConfigurations[providerID] != nil else {
            lastError = UIStrings.providerNotFound
            return false
        }
        return deleteProviderGroup(id: providerID)
    }

    @discardableResult
    func deleteProviderGroup(id providerID: String) -> Bool {
        guard providerConfigurations[providerID] != nil else {
            lastError = UIStrings.providerNotFound
            return false
        }
        let oldOrder = providerOrder
        let oldConfigurations = providerConfigurations
        let oldActiveSelector = activeModelSelector
        let oldAPIKeys = apiKeySnapshot()

        providerOrder.removeAll { $0 == providerID }
        providerConfigurations.removeValue(forKey: providerID)
        if FlotisModelSelector(rawValue: activeModelSelector)?.providerID == providerID {
            activeModelSelector = firstModelSelector() ?? ""
        }
        rebuildDerivedState()
        guard saveCatalog() else {
            providerOrder = oldOrder
            providerConfigurations = oldConfigurations
            activeModelSelector = oldActiveSelector
            replaceAPIKeys(oldAPIKeys)
            rebuildDerivedState()
            return false
        }
        lastError = nil
        return true
    }

    func hasAPIKey(for provider: TranscriptionConnection) -> Bool {
        guard let reference = provider.apiKeyReference else { return false }
        return load(for: reference) != nil
    }

    @discardableResult
    func saveAPIKey(_ apiKey: String, for provider: TranscriptionConnection) -> Bool {
        guard let persisted = providers.first(where: { $0.id == provider.id }) else {
            lastError = UIStrings.providerNotFound
            return false
        }
        return updateProvider(persisted, savingAPIKey: apiKey)
    }

    @discardableResult
    func clearAPIKey(for providerID: UUID) -> Bool {
        guard let route = providers.first(where: { $0.id == providerID }),
              let groupID = route.configurationProviderID,
              var configuration = providerConfigurations[groupID],
              configuration.options.apiKey?.flotisTrimmedNonempty != nil else {
            lastError = UIStrings.apiKeyNotSaved
            return false
        }
        let oldConfiguration = configuration
        let oldActiveSelector = activeModelSelector
        let oldAPIKeys = apiKeySnapshot()

        configuration.options.apiKey = nil
        configuration.credentialRevision = (configuration.credentialRevision ?? 0) + 1
        for modelID in configuration.models.keys {
            configuration.models[modelID]?.lastConnectionTest = nil
        }
        providerConfigurations[groupID] = configuration
        if FlotisModelSelector(rawValue: activeModelSelector)?.providerID == groupID {
            activeModelSelector = firstReadyModelSelector(excludingProviderID: groupID)
                ?? route.configurationModelSelector
                ?? firstModelSelector()
                ?? ""
        }
        rebuildDerivedState()
        guard saveCatalog() else {
            providerConfigurations[groupID] = oldConfiguration
            activeModelSelector = oldActiveSelector
            replaceAPIKeys(oldAPIKeys)
            rebuildDerivedState()
            return false
        }
        lastError = nil
        return true
    }

    @discardableResult
    func recordConnectionTest(
        providerID: UUID,
        outcome: TranscriptionConnectionTestOutcome,
        safeSummary: String,
        testedAt: Date = Date()
    ) -> Bool {
        guard var route = providers.first(where: { $0.id == providerID }),
              let groupID = route.configurationProviderID,
              let selector = route.configurationModelSelector.flatMap({
                  FlotisModelSelector(rawValue: $0)
              }),
              var configuration = providerConfigurations[groupID] else {
            lastError = UIStrings.providerNotFound
            return false
        }
        let oldConfiguration = configuration
        route.recordConnectionTest(
            outcome: outcome,
            safeSummary: safeSummary,
            testedAt: testedAt
        )
        configuration.models[selector.modelID]?.lastConnectionTest = route.lastConnectionTest
        providerConfigurations[groupID] = configuration
        rebuildDerivedState()
        guard saveCatalog() else {
            providerConfigurations[groupID] = oldConfiguration
            rebuildDerivedState()
            return false
        }
        return true
    }

    func isProviderReady(_ provider: TranscriptionConnection) -> Bool {
        providerReadinessError(for: provider) == nil
    }

    func providerReadinessError(for provider: TranscriptionConnection) -> String? {
        if let error = provider.configurationValidationError() { return error }
        if provider.protocolSchema.requiresAPIKey && !hasAPIKey(for: provider) {
            return UIStrings.apiKeyRequiredForActivation
        }
        return nil
    }

    func loadConfig() -> TranscriptionConnection { activeProvider }

    @discardableResult
    func saveConfig(_ config: TranscriptionConnection) -> Bool {
        updateProvider(config)
    }

    @discardableResult
    func save(secret: String, for reference: String) -> Bool {
        guard let normalized = normalizedKey(secret),
              let providerID = providerOrder.first(where: {
                  providerConfigurations[$0]?.resolvedAPIKeyReference(providerID: $0) == reference
              }),
              var configuration = providerConfigurations[providerID] else {
            return false
        }
        let oldConfiguration = configuration
        configuration.options.apiKey = normalized
        configuration.credentialRevision = (configuration.credentialRevision ?? 0) + 1
        for modelID in configuration.models.keys {
            configuration.models[modelID]?.lastConnectionTest = nil
        }
        providerConfigurations[providerID] = configuration
        rebuildDerivedState()
        guard saveCatalog() else {
            providerConfigurations[providerID] = oldConfiguration
            rebuildDerivedState()
            return false
        }
        return true
    }

    func load(for reference: String) -> String? {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else { return nil }
        apiKeyLock.lock()
        defer { apiKeyLock.unlock() }
        return apiKeys[normalizedReference]
    }

    @discardableResult
    func delete(for reference: String) -> Bool {
        guard let route = providers.first(where: { $0.apiKeyReference == reference }) else {
            return true
        }
        return clearAPIKey(for: route.id)
    }

    private func load() {
        switch configurationStore.load() {
        case .loaded(let document):
            apply(document: document)
            lastError = nil
        case .missing:
            let migration = legacySnapshot()
            let snapshot = migration.snapshot
            let migratedAPIKeys = legacyAPIKeys(for: snapshot)
            let document = FlotisConfigurationDocument.make(
                snapshot: snapshot,
                apiKeys: migratedAPIKeys,
                comparison: legacyComparisonPreferences(for: snapshot)
            )
            apply(document: document)
            if !configurationStore.installInitialDocument(document) {
                lastError = UIStrings.providerConfigSaveFailed
            } else if migration.recoveredCorruptData {
                lastError = UIStrings.providerConfigRecoveredWithoutOverwrite
            } else {
                lastError = nil
            }
        case .unavailable:
            apply(document: .fresh())
            lastError = UIStrings.providerConfigRecoveredWithoutOverwrite
        }
    }

    private func apply(document: FlotisConfigurationDocument) {
        providerOrder = document.providerOrder
        providerConfigurations = document.provider
        activeModelSelector = document.model
        rebuildDerivedState()
    }

    private func rebuildDerivedState() {
        providerGroups = providerOrder.compactMap { providerID in
            providerConfigurations[providerID].map {
                SpeechProviderGroup(id: providerID, configuration: $0)
            }
        }
        providers = providerGroups.flatMap { group in
            group.modelIDs.compactMap(group.connection)
        }
        if providers.isEmpty {
            activeModelSelector = ""
            activeProviderID = TranscriptionConnection.appleSpeechID
        } else {
            if !availableModelSelectors.contains(activeModelSelector) {
                activeModelSelector = providers.first?.configurationModelSelector ?? ""
            }
            activeProviderID = providers.first {
                $0.configurationModelSelector == activeModelSelector
            }?.id ?? TranscriptionConnection.appleSpeechID
        }

        var keys: [String: String] = [:]
        for providerID in providerOrder {
            guard let configuration = providerConfigurations[providerID],
                  let key = configuration.options.apiKey?.flotisTrimmedNonempty,
                  let reference = configuration.resolvedAPIKeyReference(providerID: providerID) else {
                continue
            }
            keys[reference] = key
        }
        replaceAPIKeys(keys)
    }

    private func legacySnapshot() -> (
        snapshot: SpeechProviderStoreSnapshot,
        recoveredCorruptData: Bool
    ) {
        if let data = defaults.data(forKey: configKeyV3) {
            if let decoded = try? decodeV3(data) {
                return (SpeechProviderSnapshotMigration.normalizeV3(decoded), false)
            }
            if let recoveryData = defaults.data(forKey: lastKnownGoodKey),
               let recovery = try? decodeV3(recoveryData) {
                return (SpeechProviderSnapshotMigration.normalizeV3(recovery), true)
            }
            if let migrated = loadV2Migration() ?? loadV1Migration() {
                return (migrated, true)
            }
            return (freshSnapshot(), true)
        }
        if let migrated = loadV2Migration() ?? loadV1Migration() {
            return (migrated, false)
        }
        return (freshSnapshot(), false)
    }

    private func legacyAPIKeys(
        for snapshot: SpeechProviderStoreSnapshot
    ) -> [String: String] {
        var values: [String: String] = [:]
        for reference in snapshot.connections.compactMap(\.apiKeyReference) {
            if let value = normalizedKey(legacySecretStore.load(for: reference)) {
                values[reference] = value
            }
        }
        return values
    }

    private func legacyComparisonPreferences(
        for snapshot: SpeechProviderStoreSnapshot
    ) -> TranscriptionComparisonPreferences {
        guard let data = defaults.data(forKey: legacyComparisonKey) else {
            return TranscriptionComparisonPreferences()
        }
        if let decoded = try? decoder.decode(TranscriptionComparisonPreferences.self, from: data),
           decoded.schemaVersion == TranscriptionComparisonPreferences.currentSchemaVersion {
            return decoded
        }
        guard let decoded = try? decoder.decode(LegacyComparisonPreferencesV1.self, from: data)
        else {
            return TranscriptionComparisonPreferences()
        }
        let connectionByID = Dictionary(
            uniqueKeysWithValues: snapshot.connections.map { ($0.id, $0) }
        )
        let selectors = decoded.connectionIDs.compactMap { connectionID -> String? in
            guard let connection = connectionByID[connectionID],
                  connection.adapterID != .appleOnDevice else { return nil }
            let providerID = connection.configurationProviderID?.flotisTrimmedNonempty
                ?? connection.id.uuidString.lowercased()
            return FlotisModelSelector(
                providerID: providerID,
                modelID: connection.model
            )?.rawValue
        }
        return TranscriptionComparisonPreferences(
            isEnabled: decoded.isEnabled && selectors.count >= 2,
            modelSelectors: selectors
        )
    }

    private func decodeV3(_ data: Data) throws -> SpeechProviderStoreSnapshot {
        let decoded = try decoder.decode(SpeechProviderStoreSnapshot.self, from: data)
        guard decoded.schemaVersion == SpeechProviderStoreSnapshot.currentSchemaVersion,
              !decoded.connections.isEmpty else {
            throw SnapshotLoadError.unsupportedOrEmpty
        }
        return decoded
    }

    private func loadV2Migration() -> SpeechProviderStoreSnapshot? {
        guard let data = defaults.data(forKey: configKeyV2) else { return nil }
        do {
            let legacy = try decoder.decode(SpeechProviderStoreSnapshotV2.self, from: data)
            guard legacy.schemaVersion == 2, !legacy.providers.isEmpty else {
                throw SnapshotLoadError.unsupportedOrEmpty
            }
            return SpeechProviderSnapshotMigration.migrateV2(legacy)
        } catch {
            if let recoveryData = defaults.data(forKey: lastKnownGoodKeyV2),
               let recovery = try? decoder.decode(
                   SpeechProviderStoreSnapshotV2.self,
                   from: recoveryData
               ),
               recovery.schemaVersion == 2,
               !recovery.providers.isEmpty {
                return SpeechProviderSnapshotMigration.migrateV2(recovery)
            }
            return nil
        }
    }

    private func loadV1Migration() -> SpeechProviderStoreSnapshot? {
        guard let data = defaults.data(forKey: configKeyV1) else { return nil }
        do {
            let legacy = try decoder.decode(SpeechProviderStoreSnapshotV1.self, from: data)
            guard !legacy.providers.isEmpty else {
                throw SnapshotLoadError.unsupportedOrEmpty
            }
            return SpeechProviderSnapshotMigration.migrateV1(legacy)
        } catch {
            return nil
        }
    }

    private func freshSnapshot() -> SpeechProviderStoreSnapshot {
        SpeechProviderStoreSnapshot(
            connections: [.appleSpeech],
            activeConnectionID: TranscriptionConnection.appleSpeechID
        )
    }

    private func firstModelSelector() -> String? {
        providerOrder.lazy.compactMap { providerID in
            self.providerConfigurations[providerID]?.models.keys.sorted().first.flatMap {
                FlotisModelSelector(providerID: providerID, modelID: $0)?.rawValue
            }
        }.first
    }

    private func firstReadyModelSelector(excludingProviderID: String? = nil) -> String? {
        providers.first { route in
            route.configurationProviderID != excludingProviderID
                && providerReadinessError(for: route) == nil
        }?.configurationModelSelector
    }

    private func uniqueProviderID(for name: String) -> String {
        let scalars = name.lowercased().unicodeScalars
        var result = ""
        var pendingSeparator = false
        for scalar in scalars {
            let isASCIIAlphaNumeric = scalar.value < 128
                && CharacterSet.alphanumerics.contains(scalar)
            if isASCIIAlphaNumeric {
                if pendingSeparator, !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else if !result.isEmpty {
                pendingSeparator = true
            }
        }
        let base = String((result.isEmpty ? "provider" : result).prefix(96))
        var candidate = base
        var suffix = 2
        while providerConfigurations[candidate] != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func normalizedModelIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private func makeAPIKeyReference(providerID: String, revision: Int) -> String {
        "flotis.config.provider.\(providerID).credential.\(max(1, revision))"
    }

    @discardableResult
    private func saveCatalog() -> Bool {
        let order = providerOrder
        let activeModel = activeModelSelector
        let configurations = providerConfigurations
        let didSave = configurationStore.update { document in
            document.replaceProviderCatalog(
                providerOrder: order,
                activeModel: activeModel,
                providers: configurations
            )
        }
        lastError = didSave ? nil : UIStrings.providerConfigSaveFailed
        return didSave
    }

    private func apiKeySnapshot() -> [String: String] {
        apiKeyLock.lock()
        defer { apiKeyLock.unlock() }
        return apiKeys
    }

    private func replaceAPIKeys(_ values: [String: String]) {
        apiKeyLock.lock()
        apiKeys = values
        apiKeyLock.unlock()
    }

    private func normalizedKey(_ key: String?) -> String? {
        guard let key else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 262_144 else { return nil }
        return trimmed
    }

    private struct LegacyComparisonPreferencesV1: Decodable {
        var isEnabled: Bool
        var connectionIDs: [UUID]
    }

    private enum SnapshotLoadError: Error {
        case unsupportedOrEmpty
    }
}

typealias TranscriptionProviderStore = SpeechProviderStore

private extension String {
    var flotisTrimmedNonempty: String? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
