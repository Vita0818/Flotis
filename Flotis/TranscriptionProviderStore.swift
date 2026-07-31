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

final class SpeechProviderStore: ObservableObject {
    static let shared = SpeechProviderStore()

    @Published private(set) var providers: [TranscriptionConnection] = []
    @Published private(set) var activeProviderID: UUID
    @Published var lastError: String?

    private let configKeyV3 = "flotis.transcriptionConnections.v3"
    private let configKeyV2 = "flotis.speechProviders.v2"
    private let configKeyV1 = "flotis.speechProviders.v1"
    private let lastKnownGoodKey = "flotis.transcriptionConnections.v3.lastKnownGood"
    private let lastKnownGoodKeyV2 = "flotis.speechProviders.v2.lastKnownGood"
    private let corruptBackupKey = "flotis.transcriptionConnections.corruptBackup"
    private let corruptBackupMetadataKey = "flotis.transcriptionConnections.corruptBackupMetadata"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults
    private let secretStore: SecretStoring

    init(
        defaults: UserDefaults = .standard,
        secretStore: SecretStoring = LocalSecretStore.shared
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
        activeProviderID = TranscriptionConnection.appleSpeechID
        load()
    }

    var activeProvider: TranscriptionConnection {
        providers.first { $0.id == activeProviderID } ?? .appleSpeech
    }

    @discardableResult
    func setActiveProvider(id: UUID) -> Bool {
        guard let provider = providers.first(where: { $0.id == id }) else {
            lastError = UIStrings.providerNotFound
            return false
        }
        if let error = providerReadinessError(for: provider) {
            lastError = error
            return false
        }

        let oldActiveID = activeProviderID
        activeProviderID = id
        guard save() else {
            activeProviderID = oldActiveID
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
        connection.apiKeyReference = adapterID.schema.requiresAPIKey
            ? TranscriptionConnection.makeAPIKeyReference(providerID: id, adapterID: adapterID)
            : nil
        return connection.normalizedForProtocol()
    }

    @discardableResult
    func createConnection(
        _ draft: TranscriptionConnection,
        savingAPIKey apiKey: String? = nil
    ) -> UUID? {
        guard !providers.contains(where: { $0.id == draft.id }) else {
            lastError = UIStrings.providerConfigSaveFailed
            return nil
        }

        var connection = draft.normalizedForProtocol()
        if connection.protocolSchema.requiresAPIKey {
            connection.apiKeyReference = TranscriptionConnection.makeAPIKeyReference(
                providerID: connection.id,
                adapterID: connection.adapterID
            )
        } else {
            connection.apiKeyReference = nil
        }

        let submittedTestRecord = connection.lastConnectionTest
        let trimmedAPIKey = normalizedKey(apiKey)
        if trimmedAPIKey != nil {
            // Revision 1 represents the first persisted credential. A draft that
            // already tested that same in-memory credential also carries revision 1.
            connection.credentialRevision = max(1, connection.credentialRevision)
        }
        if let submittedTestRecord,
           submittedTestRecord.adapterVersion == connection.protocolSchema.adapterVersion,
           submittedTestRecord.configurationFingerprint == connection.connectionTestFingerprint {
            connection.lastConnectionTest = submittedTestRecord
        } else if trimmedAPIKey != nil {
            connection.lastConnectionTest = nil
        }
        if let error = connection.configurationValidationError() {
            lastError = error
            return nil
        }

        let reference = connection.apiKeyReference
        if let trimmedAPIKey {
            guard let reference,
                  secretStore.save(secret: trimmedAPIKey, for: reference) else {
                lastError = UIStrings.apiKeySaveFailed
                return nil
            }
        }

        providers.append(connection)
        guard save() else {
            providers.removeAll { $0.id == connection.id }
            if trimmedAPIKey != nil, let reference {
                _ = secretStore.delete(for: reference)
            }
            return nil
        }
        return connection.id
    }

    @discardableResult
    func addProvider(kind: SpeechProviderKind) -> UUID {
        let adapterID: TranscriptionAdapterID
        switch kind {
        case .appleSpeechLive:
            adapterID = .appleOnDevice
        case .openAIRealtimeTranscription:
            adapterID = .openAIRealtimeTranscriptionGA
        case .openAIHTTPTranscription:
            adapterID = .openAIAudioTranscriptionsHTTPV1
        }
        var draft = makeNewConnection(adapterID: adapterID)
        if kind == .openAIRealtimeTranscription {
            draft.name = UIStrings.customRealtime
        } else if kind == .openAIHTTPTranscription {
            draft.name = UIStrings.customHTTP
        }
        return createConnection(draft) ?? draft.id
    }

    @discardableResult
    func addProvider(
        preset wireProtocol: SpeechProviderWireProtocol,
        customName: String? = nil
    ) -> UUID {
        var draft = makeNewConnection(adapterID: wireProtocol.adapterID)
        if let customName {
            draft.name = customName
        }
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
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else {
            lastError = UIStrings.providerNotFound
            return false
        }

        let oldProvider = providers[index]
        var updated = provider.normalizedForProtocol()
        let submittedTestRecord = updated.lastConnectionTest
        let secretBoundaryChanged = oldProvider.secretBoundaryIdentifier
            != updated.secretBoundaryIdentifier
        let trimmedAPIKey = normalizedKey(apiKey)
        let credentialChanged = secretBoundaryChanged || trimmedAPIKey != nil

        updated.credentialRevision = oldProvider.credentialRevision
        if updated.protocolSchema.requiresAPIKey {
            if secretBoundaryChanged {
                updated.apiKeyReference = TranscriptionConnection.makeAPIKeyReference(
                    providerID: updated.id,
                    adapterID: updated.adapterID
                )
            } else {
                updated.apiKeyReference = oldProvider.apiKeyReference
                    ?? TranscriptionConnection.makeAPIKeyReference(
                        providerID: updated.id,
                        adapterID: updated.adapterID
                    )
            }
        } else {
            updated.apiKeyReference = nil
        }

        if credentialChanged {
            updated.credentialRevision += 1
        }
        if let submittedTestRecord,
           submittedTestRecord.adapterVersion == updated.protocolSchema.adapterVersion,
           submittedTestRecord.configurationFingerprint == updated.connectionTestFingerprint {
            // The editor can test an in-memory replacement credential before Save.
            // Preserve that result only when its non-secret revision/fingerprint
            // exactly matches the credential revision this transaction will persist.
            updated.lastConnectionTest = submittedTestRecord
        } else if credentialChanged {
            updated.lastConnectionTest = nil
        } else if oldProvider.connectionTestFingerprint == updated.connectionTestFingerprint {
            updated.lastConnectionTest = oldProvider.lastConnectionTest
        } else {
            updated.lastConnectionTest = nil
        }
        updated = updated.normalizedForProtocol()

        if let error = updated.configurationValidationError() {
            lastError = error
            return false
        }

        let newReference = updated.apiKeyReference
        let previousSecretAtNewReference: String?
        if trimmedAPIKey != nil, let newReference {
            previousSecretAtNewReference = secretStore.load(for: newReference)
        } else {
            previousSecretAtNewReference = nil
        }
        if let trimmedAPIKey {
            guard let newReference,
                  secretStore.save(secret: trimmedAPIKey, for: newReference) else {
                lastError = UIStrings.apiKeySaveFailed
                return false
            }
        }

        let oldProviders = providers
        let oldActiveID = activeProviderID
        providers[index] = updated
        if activeProviderID == updated.id,
           providerReadinessError(for: updated) != nil {
            activeProviderID = firstReadyProviderID(excluding: updated.id)
                ?? ensureAppleFallbackProvider()
        }

        guard save() else {
            providers = oldProviders
            activeProviderID = oldActiveID
            if let newReference, trimmedAPIKey != nil {
                restoreSecret(previousSecretAtNewReference, for: newReference)
            }
            return false
        }

        if oldProvider.apiKeyReference != updated.apiKeyReference,
           let oldReference = oldProvider.apiKeyReference,
           !secretStore.delete(for: oldReference) {
            providers = oldProviders
            activeProviderID = oldActiveID
            _ = save()
            if let newReference, trimmedAPIKey != nil {
                restoreSecret(previousSecretAtNewReference, for: newReference)
            }
            lastError = UIStrings.providerSecretCleanupFailed
            return false
        }
        lastError = nil
        return true
    }

    @discardableResult
    func deleteProvider(id: UUID) -> Bool {
        guard providers.count > 1 else {
            lastError = UIStrings.keepOneProvider
            return false
        }
        guard let provider = providers.first(where: { $0.id == id }) else {
            lastError = UIStrings.providerNotFound
            return false
        }

        let oldProviders = providers
        let oldActiveID = activeProviderID
        providers.removeAll { $0.id == id }
        if activeProviderID == id {
            activeProviderID = firstReadyProviderID()
                ?? ensureAppleFallbackProvider()
        }

        guard save() else {
            providers = oldProviders
            activeProviderID = oldActiveID
            return false
        }

        if let reference = provider.apiKeyReference,
           !secretStore.delete(for: reference) {
            providers = oldProviders
            activeProviderID = oldActiveID
            _ = save()
            lastError = UIStrings.providerDeleteSecretCleanupFailed
            return false
        }
        lastError = nil
        return true
    }

    func hasAPIKey(for provider: TranscriptionConnection) -> Bool {
        guard let reference = provider.apiKeyReference else { return false }
        let key = secretStore.load(for: reference) ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard let index = providers.firstIndex(where: { $0.id == providerID }),
              let reference = providers[index].apiKeyReference else {
            lastError = UIStrings.apiKeyNotSaved
            return false
        }

        let oldProviders = providers
        let oldActiveID = activeProviderID
        providers[index].credentialRevision += 1
        providers[index].lastConnectionTest = nil
        if activeProviderID == providerID {
            activeProviderID = firstReadyProviderID(excluding: providerID)
                ?? ensureAppleFallbackProvider()
        }

        guard save() else {
            providers = oldProviders
            activeProviderID = oldActiveID
            return false
        }

        guard secretStore.delete(for: reference) else {
            providers = oldProviders
            activeProviderID = oldActiveID
            _ = save()
            lastError = UIStrings.apiKeyClearFailed
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
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else {
            lastError = UIStrings.providerNotFound
            return false
        }
        let oldProvider = providers[index]
        providers[index].recordConnectionTest(
            outcome: outcome,
            safeSummary: safeSummary,
            testedAt: testedAt
        )
        guard save() else {
            providers[index] = oldProvider
            return false
        }
        return true
    }

    func isProviderReady(_ provider: TranscriptionConnection) -> Bool {
        providerReadinessError(for: provider) == nil
    }

    func providerReadinessError(for provider: TranscriptionConnection) -> String? {
        if let error = provider.configurationValidationError() {
            return error
        }
        if provider.protocolSchema.requiresAPIKey && !hasAPIKey(for: provider) {
            return UIStrings.apiKeyRequiredForActivation
        }
        return nil
    }

    func loadConfig() -> TranscriptionConnection {
        activeProvider
    }

    @discardableResult
    func saveConfig(_ config: TranscriptionConnection) -> Bool {
        updateProvider(config)
    }

    private func load() {
        if let v3Data = defaults.data(forKey: configKeyV3) {
            do {
                let decoded = try decodeV3(v3Data)
                let normalized = SpeechProviderSnapshotMigration.normalizeV3(decoded)
                apply(snapshot: normalized)
                defaults.set(v3Data, forKey: lastKnownGoodKey)
                if normalized != decoded {
                    _ = persist(snapshot: normalized)
                }
                return
            } catch {
                backupCorrupt(data: v3Data, sourceKey: configKeyV3)
                if let recoveryData = defaults.data(forKey: lastKnownGoodKey),
                   let recovery = try? decodeV3(recoveryData) {
                    apply(snapshot: SpeechProviderSnapshotMigration.normalizeV3(recovery))
                } else if let migrated = loadV2Migration() ?? loadV1Migration() {
                    apply(snapshot: migrated)
                } else {
                    apply(snapshot: freshSnapshot())
                }
                lastError = UIStrings.providerConfigRecoveredWithoutOverwrite
                return
            }
        }

        if let migrated = loadV2Migration() {
            apply(snapshot: migrated)
            _ = persist(snapshot: migrated)
            return
        }
        if let migrated = loadV1Migration() {
            apply(snapshot: migrated)
            _ = persist(snapshot: migrated)
            return
        }

        let fresh = freshSnapshot()
        apply(snapshot: fresh)
        _ = persist(snapshot: fresh)
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
            backupCorrupt(data: data, sourceKey: configKeyV2)
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
            backupCorrupt(data: data, sourceKey: configKeyV1)
            return nil
        }
    }

    private func freshSnapshot() -> SpeechProviderStoreSnapshot {
        SpeechProviderStoreSnapshot(
            connections: [.appleSpeech],
            activeConnectionID: TranscriptionConnection.appleSpeechID
        )
    }

    private func apply(snapshot: SpeechProviderStoreSnapshot) {
        providers = snapshot.connections
        activeProviderID = SpeechProviderSnapshotMigration.validActiveID(
            requested: snapshot.activeConnectionID,
            providers: providers
        )
    }

    @discardableResult
    private func ensureAppleFallbackProvider() -> UUID {
        if let index = providers.firstIndex(where: { $0.id == TranscriptionConnection.appleSpeechID }) {
            providers[index] = .appleSpeech
        } else {
            providers.append(.appleSpeech)
        }
        return TranscriptionConnection.appleSpeechID
    }

    private func firstReadyProviderID(excluding excludedID: UUID? = nil) -> UUID? {
        providers.first { provider in
            provider.id != excludedID && providerReadinessError(for: provider) == nil
        }?.id
    }

    private func currentSnapshot() -> SpeechProviderStoreSnapshot {
        SpeechProviderStoreSnapshot(
            connections: providers,
            activeConnectionID: activeProviderID
        )
    }

    @discardableResult
    private func save() -> Bool {
        persist(snapshot: currentSnapshot())
    }

    @discardableResult
    private func persist(snapshot: SpeechProviderStoreSnapshot) -> Bool {
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: configKeyV3)
            defaults.set(data, forKey: lastKnownGoodKey)
            lastError = nil
            return true
        } catch {
            lastError = UIStrings.providerConfigSaveFailed
            return false
        }
    }

    private func restoreSecret(_ previousSecret: String?, for reference: String) {
        if let previousSecret {
            _ = secretStore.save(secret: previousSecret, for: reference)
        } else {
            _ = secretStore.delete(for: reference)
        }
    }

    private func normalizedKey(_ key: String?) -> String? {
        guard let key else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func backupCorrupt(data: Data, sourceKey: String) {
        defaults.set(data, forKey: corruptBackupKey)
        defaults.set(
            [
                "sourceKey": sourceKey,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ],
            forKey: corruptBackupMetadataKey
        )
    }

    private enum SnapshotLoadError: Error {
        case unsupportedOrEmpty
    }
}

typealias TranscriptionProviderStore = SpeechProviderStore
