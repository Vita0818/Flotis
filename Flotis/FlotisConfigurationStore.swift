import Darwin
import Dispatch
import Foundation

struct FlotisModelSelector: Hashable, Codable, Identifiable {
    let providerID: String
    let modelID: String

    var id: String { rawValue }
    var rawValue: String { "\(providerID)/\(modelID)" }

    init?(providerID: String, modelID: String) {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidProviderID(normalizedProviderID),
              Self.isValidModelID(normalizedModelID) else {
            return nil
        }
        self.providerID = normalizedProviderID
        self.modelID = normalizedModelID
    }

    init?(rawValue: String) {
        guard let separator = rawValue.firstIndex(of: "/") else { return nil }
        self.init(
            providerID: String(rawValue[..<separator]),
            modelID: String(rawValue[rawValue.index(after: separator)...])
        )
    }

    static func isValidProviderID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar.value == 45
                || scalar.value == 95
                || scalar.value == 46
        }
    }

    static func isValidModelID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 256,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }
}

struct FlotisConfigurationDocument: Codable, Equatable {
    static let currentSchemaVersion = 2
    static let schemaIdentifier = "https://flotis.app/config/v2"

    var schema: String
    var schemaVersion: Int
    var model: String
    var providerOrder: [String]
    var enabledProviders: [String]
    var comparison: FlotisComparisonConfiguration
    var provider: [String: FlotisProviderConfiguration]
    var shortcuts: FlotisHotkeyConfiguration?

    init(
        schema: String = Self.schemaIdentifier,
        schemaVersion: Int = Self.currentSchemaVersion,
        model: String,
        providerOrder: [String],
        enabledProviders: [String],
        comparison: FlotisComparisonConfiguration,
        provider: [String: FlotisProviderConfiguration],
        shortcuts: FlotisHotkeyConfiguration? = FlotisHotkeyConfiguration.defaults
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.model = model
        self.providerOrder = providerOrder
        self.enabledProviders = enabledProviders
        self.comparison = comparison
        self.provider = provider
        self.shortcuts = shortcuts
    }

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case schemaVersion = "schema_version"
        case model
        case providerOrder = "provider_order"
        case enabledProviders = "enabled_providers"
        case comparison
        case provider
        case shortcuts
    }

    static func fresh() -> FlotisConfigurationDocument {
        FlotisConfigurationDocument(
            model: "",
            providerOrder: [],
            enabledProviders: [],
            comparison: FlotisComparisonConfiguration(enabled: false, models: []),
            provider: [:]
        )
    }

    static func make(
        snapshot: SpeechProviderStoreSnapshot,
        apiKeys: [String: String],
        comparison: TranscriptionComparisonPreferences
    ) -> FlotisConfigurationDocument {
        let normalizedSnapshot = SpeechProviderSnapshotMigration.normalizeV3(snapshot)
        var order: [String] = []
        var configurations: [String: FlotisProviderConfiguration] = [:]
        var selectorByConnectionID: [UUID: String] = [:]

        for connection in normalizedSnapshot.connections
        where connection.adapterID != .appleOnDevice {
            guard FlotisModelSelector.isValidModelID(connection.model) else { continue }
            let requestedProviderID = connection.configurationProviderID?.trimmedNonempty
                ?? connection.id.uuidString.lowercased()
            var providerID = FlotisModelSelector.isValidProviderID(requestedProviderID)
                ? requestedProviderID
                : connection.id.uuidString.lowercased()
            var candidate = FlotisProviderConfiguration(
                connection: connection,
                apiKey: connection.apiKeyReference.flatMap { apiKeys[$0] }
            )
            let modelConfiguration = candidate.models[connection.model]
                ?? FlotisModelConfiguration(lastConnectionTest: connection.lastConnectionTest)
            candidate.models = [:]

            var suffix = 2
            while let existing = configurations[providerID],
                  existing.sharedConfiguration != candidate.sharedConfiguration {
                providerID = "\(requestedProviderID)-\(suffix)"
                suffix += 1
            }

            if configurations[providerID] == nil {
                configurations[providerID] = candidate
                order.append(providerID)
            }
            configurations[providerID]?.models[connection.model] = modelConfiguration
            selectorByConnectionID[connection.id] = FlotisModelSelector(
                providerID: providerID,
                modelID: connection.model
            )?.rawValue
        }

        let availableSelectors = Set(configurations.flatMap { providerID, configuration in
            configuration.models.keys.compactMap {
                FlotisModelSelector(providerID: providerID, modelID: $0)?.rawValue
            }
        })
        let requestedComparison = normalizedComparisonPreferences(
            comparison,
            availableSelectors: availableSelectors
        )
        let activeSelector = selectorByConnectionID[normalizedSnapshot.activeConnectionID]
            ?? order.first.flatMap { providerID in
                configurations[providerID]?.models.keys.sorted().first.flatMap {
                    FlotisModelSelector(providerID: providerID, modelID: $0)?.rawValue
                }
            }

        return FlotisConfigurationDocument(
            model: activeSelector ?? "",
            providerOrder: order,
            enabledProviders: order,
            comparison: FlotisComparisonConfiguration(
                enabled: requestedComparison.isEnabled,
                models: requestedComparison.modelSelectors
            ),
            provider: configurations
        )
    }

    mutating func replaceProviderCatalog(
        providerOrder: [String],
        activeModel: String,
        providers: [String: FlotisProviderConfiguration]
    ) {
        schema = Self.schemaIdentifier
        schemaVersion = Self.currentSchemaVersion
        model = activeModel
        self.providerOrder = providerOrder
        enabledProviders = providerOrder
        provider = providers

        let availableSelectors = self.availableModelSelectors
        comparison.models.removeAll { !availableSelectors.contains($0) }
        if comparison.models.count < 2 {
            comparison.enabled = false
        }
    }

    mutating func replaceProviderState(
        snapshot: SpeechProviderStoreSnapshot,
        apiKeys: [String: String]
    ) {
        let replacement = Self.make(
            snapshot: snapshot,
            apiKeys: apiKeys,
            comparison: comparisonPreferences
        )
        replaceProviderCatalog(
            providerOrder: replacement.providerOrder,
            activeModel: replacement.model,
            providers: replacement.provider
        )
    }

    mutating func replaceComparison(_ preferences: TranscriptionComparisonPreferences) {
        let normalized = Self.normalizedComparisonPreferences(
            preferences,
            availableSelectors: availableModelSelectors
        )
        schema = Self.schemaIdentifier
        schemaVersion = Self.currentSchemaVersion
        comparison = FlotisComparisonConfiguration(
            enabled: normalized.isEnabled,
            models: normalized.modelSelectors
        )
    }

    mutating func replaceShortcuts(_ configuration: FlotisHotkeyConfiguration) {
        schema = Self.schemaIdentifier
        schemaVersion = Self.currentSchemaVersion
        shortcuts = configuration
    }

    var comparisonPreferences: TranscriptionComparisonPreferences {
        Self.normalizedComparisonPreferences(
            TranscriptionComparisonPreferences(
                isEnabled: comparison.enabled,
                modelSelectors: comparison.models
            ),
            availableSelectors: availableModelSelectors
        )
    }

    var providerGroups: [SpeechProviderGroup] {
        providerOrder.compactMap { providerID in
            provider[providerID].map {
                SpeechProviderGroup(id: providerID, configuration: $0)
            }
        }
    }

    var availableModelSelectors: Set<String> {
        Set(provider.flatMap { providerID, configuration in
            configuration.models.keys.compactMap {
                FlotisModelSelector(providerID: providerID, modelID: $0)?.rawValue
            }
        })
    }

    func providerState() throws -> (
        snapshot: SpeechProviderStoreSnapshot,
        apiKeys: [String: String]
    ) {
        guard isStructurallyValid() else { throw ValidationError.invalidDocument }

        var connections: [TranscriptionConnection] = []
        var apiKeys: [String: String] = [:]
        for providerID in providerOrder {
            guard let configuration = provider[providerID] else {
                throw ValidationError.invalidProvider
            }
            connections.append(contentsOf: try configuration.connections(providerID: providerID))
            if let reference = configuration.resolvedAPIKeyReference(providerID: providerID),
               let apiKey = configuration.options.apiKey?.trimmedNonempty {
                apiKeys[reference] = apiKey
            }
        }

        let activeID: UUID
        if connections.isEmpty {
            activeID = TranscriptionConnection.appleSpeechID
        } else {
            guard let activeConnection = connections.first(where: {
                $0.configurationModelSelector == model
            }) else {
                throw ValidationError.invalidActiveModel
            }
            activeID = activeConnection.id
        }
        return (
            SpeechProviderSnapshotMigration.normalizeV3(
                SpeechProviderStoreSnapshot(
                    connections: connections,
                    activeConnectionID: activeID
                )
            ),
            apiKeys
        )
    }

    func isStructurallyValid() -> Bool {
        guard schema == Self.schemaIdentifier,
              schemaVersion == Self.currentSchemaVersion,
              provider.count <= FlotisConfigurationStore.maximumProviderCount,
              providerOrder.count == provider.count,
              Set(providerOrder) == Set(provider.keys),
              enabledProviders.count == provider.count,
              Set(enabledProviders) == Set(provider.keys),
              providerOrder.allSatisfy(FlotisModelSelector.isValidProviderID),
              comparison.models.count <= TranscriptionComparisonStore.maximumConnectionCount,
              Set(comparison.models).count == comparison.models.count,
              shortcuts?.isValid != false else {
            return false
        }

        if provider.isEmpty {
            return model.isEmpty
                && comparison.models.isEmpty
                && !comparison.enabled
        }

        var references = Set<String>()
        var connectionIDs = Set<UUID>()
        for providerID in providerOrder {
            guard let configuration = provider[providerID],
                  configuration.adapter != .appleOnDevice,
                  !configuration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !configuration.models.isEmpty,
                  configuration.models.count <= FlotisConfigurationStore.maximumModelCountPerProvider,
                  configuration.models.keys.allSatisfy(FlotisModelSelector.isValidModelID),
                  let connections = try? configuration.connections(providerID: providerID),
                  connections.count == configuration.models.count,
                  connections.allSatisfy({ $0.configurationValidationError() == nil }) else {
                return false
            }
            for connection in connections where !connectionIDs.insert(connection.id).inserted {
                return false
            }
            if let reference = configuration.resolvedAPIKeyReference(providerID: providerID) {
                guard references.insert(reference).inserted else { return false }
            }
            if let key = configuration.options.apiKey,
               (key.trimmedNonempty == nil || key.count > 262_144) {
                return false
            }
        }

        let available = availableModelSelectors
        guard available.contains(model),
              comparison.models.allSatisfy(available.contains),
              !comparison.enabled || comparison.models.count >= 2 else {
            return false
        }
        return true
    }

    private static func normalizedComparisonPreferences(
        _ value: TranscriptionComparisonPreferences,
        availableSelectors: Set<String>
    ) -> TranscriptionComparisonPreferences {
        var seen = Set<String>()
        let unique = value.modelSelectors.filter {
            availableSelectors.contains($0)
                && FlotisModelSelector(rawValue: $0) != nil
                && seen.insert($0).inserted
        }
        let limited = Array(unique.prefix(TranscriptionComparisonStore.maximumConnectionCount))
        return TranscriptionComparisonPreferences(
            isEnabled: value.isEnabled && limited.count >= 2,
            modelSelectors: limited
        )
    }

    private enum ValidationError: Error {
        case invalidDocument
        case invalidProvider
        case invalidActiveModel
    }
}

struct FlotisComparisonConfiguration: Codable, Equatable {
    var enabled: Bool
    var models: [String]
}

struct FlotisProviderConfiguration: Codable, Equatable {
    var name: String
    var adapter: TranscriptionAdapterID
    var options: FlotisProviderOptions
    var models: [String: FlotisModelConfiguration]
    var credentialRevision: Int?

    init(
        name: String,
        adapter: TranscriptionAdapterID,
        options: FlotisProviderOptions,
        models: [String: FlotisModelConfiguration],
        credentialRevision: Int? = nil
    ) {
        self.name = name
        self.adapter = adapter
        self.options = options
        self.models = models
        self.credentialRevision = credentialRevision
    }

    init(
        connection: TranscriptionConnection,
        apiKey: String?,
        models: [String: FlotisModelConfiguration]? = nil
    ) {
        name = connection.name
        adapter = connection.adapterID
        options = FlotisProviderOptions(connection: connection, apiKey: apiKey)
        self.models = models ?? (connection.model.isEmpty
            ? [:]
            : [
                connection.model: FlotisModelConfiguration(
                    lastConnectionTest: connection.lastConnectionTest
                )
            ])
        credentialRevision = connection.credentialRevision == 0
            ? nil
            : connection.credentialRevision
    }

    var sharedConfiguration: FlotisProviderConfiguration {
        var value = self
        value.models = [:]
        return value
    }

    func resolvedAPIKeyReference(providerID: String) -> String? {
        guard adapter.schema.requiresAPIKey else { return nil }
        return options.apiKeyReference?.trimmedNonempty
            ?? "flotis.config.provider.\(providerID).apikey"
    }

    func connections(providerID: String) throws -> [TranscriptionConnection] {
        try models.keys.sorted().map {
            try connection(providerID: providerID, modelID: $0)
        }
    }

    func connection(providerID: String, modelID: String) throws -> TranscriptionConnection {
        guard FlotisModelSelector.isValidProviderID(providerID),
              let modelConfiguration = models[modelID],
              let selector = FlotisModelSelector(providerID: providerID, modelID: modelID) else {
            throw ProviderError.invalidModel
        }
        let endpoint: TranscriptionEndpoint?
        switch adapter.schema.endpointStyle {
        case .none:
            endpoint = nil
        case .secureHTTP, .secureWebSocket:
            endpoint = TranscriptionEndpoint(
                baseURL: options.baseURL ?? "",
                path: options.path ?? "",
                customEndpointApproved: options.customEndpointApproved
            )
        }

        return TranscriptionConnection(
            id: stableModelRouteID(selector.rawValue),
            configurationProviderID: providerID,
            name: name,
            adapterID: adapter,
            endpoint: endpoint,
            model: modelID,
            language: options.language,
            authentication: TranscriptionAuthentication(
                type: options.authentication ?? adapter.schema.authenticationType,
                apiKeyReference: resolvedAPIKeyReference(providerID: providerID)
            ),
            audio: options.audio ?? TranscriptionAudioConfiguration(),
            options: options.transcription ?? TranscriptionConnectionOptions(),
            credentialRevision: credentialRevision ?? 0,
            lastConnectionTest: modelConfiguration.lastConnectionTest
        ).normalizedForProtocol()
    }

    private enum ProviderError: Error {
        case invalidModel
    }
}

struct FlotisProviderOptions: Codable, Equatable {
    var baseURL: String?
    var path: String?
    var customEndpointApproved: Bool?
    var apiKey: String?
    var apiKeyReference: String?
    var language: String?
    var authentication: TranscriptionAuthenticationType?
    var audio: TranscriptionAudioConfiguration?
    var transcription: TranscriptionConnectionOptions?

    init(connection: TranscriptionConnection, apiKey: String?) {
        baseURL = connection.endpoint?.baseURL.trimmedNonempty
        path = connection.endpoint?.path.trimmedNonempty
        customEndpointApproved = connection.endpoint?.customEndpointApproved == true ? true : nil
        self.apiKey = apiKey?.trimmedNonempty
        apiKeyReference = connection.apiKeyReference
        language = connection.language?.trimmedNonempty
        authentication = connection.authentication.type == .none
            ? nil
            : connection.authentication.type
        audio = connection.audio.isEmpty ? nil : connection.audio
        transcription = connection.options.isEmpty ? nil : connection.options
    }
}

struct FlotisModelConfiguration: Codable, Equatable {
    var name: String?
    var lastConnectionTest: TranscriptionConnectionTestRecord?

    init(
        name: String? = nil,
        lastConnectionTest: TranscriptionConnectionTestRecord? = nil
    ) {
        self.name = name?.trimmedNonempty
        self.lastConnectionTest = lastConnectionTest
    }
}

struct SpeechProviderGroup: Identifiable, Equatable {
    let id: String
    var configuration: FlotisProviderConfiguration

    var name: String { configuration.name }
    var adapterID: TranscriptionAdapterID { configuration.adapter }
    var modelIDs: [String] { configuration.models.keys.sorted() }

    func connection(modelID: String) -> TranscriptionConnection? {
        try? configuration.connection(providerID: id, modelID: modelID)
    }
}

private struct LegacyFlotisConfigurationDocumentV1: Codable {
    var schema: String
    var schemaVersion: Int
    var model: String
    var providerOrder: [String]
    var enabledProviders: [String]
    var comparison: LegacyFlotisComparisonConfigurationV1
    var provider: [String: LegacyFlotisProviderConfigurationV1]

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case schemaVersion = "schema_version"
        case model
        case providerOrder = "provider_order"
        case enabledProviders = "enabled_providers"
        case comparison
        case provider
    }

    func migrated() -> FlotisConfigurationDocument? {
        guard schema == "https://flotis.app/config/v1",
              schemaVersion == 1,
              providerOrder.count == provider.count,
              Set(providerOrder) == Set(provider.keys) else {
            return nil
        }

        var order: [String] = []
        var migratedProviders: [String: FlotisProviderConfiguration] = [:]
        var selectorByLegacyProviderID: [String: String] = [:]

        for legacyProviderID in providerOrder {
            guard let legacy = provider[legacyProviderID] else { return nil }
            if legacy.adapter == .appleOnDevice { continue }
            let providerID = legacyProviderID.lowercased()
            guard FlotisModelSelector.isValidProviderID(providerID) else { return nil }

            var modelConfigurations = legacy.models
            if modelConfigurations.isEmpty {
                let fallbackModel = legacy.options.transcription?.resourceID?.trimmedNonempty
                    ?? legacy.adapter.schema.fixedModel
                    ?? legacy.adapter.schema.defaultModel
                guard let fallbackModel else { return nil }
                modelConfigurations[fallbackModel] = FlotisModelConfiguration()
            }
            if let firstModel = modelConfigurations.keys.sorted().first,
               let lastConnectionTest = legacy.lastConnectionTest {
                modelConfigurations[firstModel]?.lastConnectionTest = lastConnectionTest
            }

            migratedProviders[providerID] = FlotisProviderConfiguration(
                name: legacy.name,
                adapter: legacy.adapter,
                options: legacy.options,
                models: modelConfigurations,
                credentialRevision: legacy.credentialRevision
            )
            order.append(providerID)

            let requestedModel = FlotisModelSelector(rawValue: model)
                .flatMap { $0.providerID.caseInsensitiveCompare(legacyProviderID) == .orderedSame
                    ? $0.modelID
                    : nil }
            let selectedModel = requestedModel.flatMap { modelConfigurations[$0] == nil ? nil : $0 }
                ?? modelConfigurations.keys.sorted().first
            if let selectedModel {
                selectorByLegacyProviderID[legacyProviderID] = FlotisModelSelector(
                    providerID: providerID,
                    modelID: selectedModel
                )?.rawValue
            }
        }

        let requestedProviderID = FlotisModelSelector(rawValue: model)?.providerID
        let activeSelector = requestedProviderID.flatMap { selectorByLegacyProviderID[$0] }
            ?? order.first.flatMap { providerID in
                migratedProviders[providerID]?.models.keys.sorted().first.flatMap {
                    FlotisModelSelector(providerID: providerID, modelID: $0)?.rawValue
                }
            }
            ?? ""
        var seen = Set<String>()
        let comparisonModels = enabledProviders.compactMap {
            selectorByLegacyProviderID[$0]
        }.filter { seen.insert($0).inserted }

        let migrated = FlotisConfigurationDocument(
            model: activeSelector,
            providerOrder: order,
            enabledProviders: order,
            comparison: FlotisComparisonConfiguration(
                enabled: comparison.enabled && comparisonModels.count >= 2,
                models: Array(comparisonModels.prefix(TranscriptionComparisonStore.maximumConnectionCount))
            ),
            provider: migratedProviders
        )
        return migrated.isStructurallyValid() ? migrated : nil
    }
}

private struct LegacyFlotisComparisonConfigurationV1: Codable {
    var enabled: Bool
}

private struct LegacyFlotisProviderConfigurationV1: Codable {
    var name: String
    var adapter: TranscriptionAdapterID
    var options: FlotisProviderOptions
    var models: [String: FlotisModelConfiguration]
    var credentialRevision: Int?
    var lastConnectionTest: TranscriptionConnectionTestRecord?
}

enum FlotisConfigurationLoadResult {
    case missing
    case loaded(FlotisConfigurationDocument)
    case unavailable
}

final class FlotisConfigurationStore {
    static let shared = FlotisConfigurationStore()

    static let defaultFileURL: URL = {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Flotis", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }()

    static let maximumProviderCount = 64
    static let maximumModelCountPerProvider = 64
    private static let maximumFileSize = 4_194_304
    private static let maximumLockWaitNanoseconds: UInt64 = 500_000_000
    private static let lockRetryMicroseconds: UInt64 = 10_000
    private static let processLock = NSLock()

    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let lockFileName = ".config.lock"

    init(
        fileURL: URL = FlotisConfigurationStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func load() -> FlotisConfigurationLoadResult {
        withLockedDirectory { directoryDescriptor in
            readDocument(from: directoryDescriptor)
        } ?? .unavailable
    }

    @discardableResult
    func update(_ body: (inout FlotisConfigurationDocument) -> Void) -> Bool {
        withLockedDirectory { directoryDescriptor in
            var document: FlotisConfigurationDocument
            switch readDocument(from: directoryDescriptor) {
            case .missing:
                document = .fresh()
            case .loaded(let loaded):
                document = loaded
            case .unavailable:
                return false
            }
            body(&document)
            guard document.isStructurallyValid() else { return false }
            return writeDocument(document, to: directoryDescriptor)
        } ?? false
    }

    @discardableResult
    func installInitialDocument(_ document: FlotisConfigurationDocument) -> Bool {
        withLockedDirectory { directoryDescriptor in
            switch readDocument(from: directoryDescriptor) {
            case .missing:
                guard document.isStructurallyValid() else { return false }
                return writeDocument(document, to: directoryDescriptor)
            case .loaded:
                return true
            case .unavailable:
                return false
            }
        } ?? false
    }

    private func withLockedDirectory<Result>(
        _ body: (Int32) -> Result
    ) -> Result? {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        guard let directoryDescriptor = openStorageDirectory() else {
            return nil
        }
        defer { Darwin.close(directoryDescriptor) }

        guard let lockDescriptor = openLockFile(in: directoryDescriptor) else {
            return nil
        }
        defer { Darwin.close(lockDescriptor) }

        guard acquireFileLock(on: lockDescriptor) else {
            return nil
        }
        defer {
            _ = applyFileLock(on: lockDescriptor, type: Int16(F_UNLCK))
        }
        return body(directoryDescriptor)
    }

    private func openStorageDirectory() -> Int32? {
        let directoryURL = fileURL.deletingLastPathComponent()
        if let descriptor = openDirectory(at: directoryURL) {
            return descriptor
        }
        guard errno == ENOENT else { return nil }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            return nil
        }
        return openDirectory(at: directoryURL)
    }

    private func openDirectory(at url: URL) -> Int32? {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              Darwin.fchmod(descriptor, mode_t(0o700)) == 0,
              Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(0o777) == mode_t(0o700) else {
            Darwin.close(descriptor)
            return nil
        }
        return descriptor
    }

    private func openLockFile(in directoryDescriptor: Int32) -> Int32? {
        let descriptor = lockFileName.withCString { name in
            Darwin.openat(
                directoryDescriptor,
                name,
                O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0, validateAndRestrictRegularFile(descriptor) else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return nil
        }
        return descriptor
    }

    private func readDocument(from directoryDescriptor: Int32) -> FlotisConfigurationLoadResult {
        let descriptor = openConfigurationFile(
            in: directoryDescriptor,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0 {
            return errno == ENOENT ? .missing : .unavailable
        }
        defer { Darwin.close(descriptor) }

        var status = stat()
        guard validateAndRestrictRegularFile(descriptor),
              Darwin.fstat(descriptor, &status) == 0,
              status.st_size >= 0,
              status.st_size <= off_t(Self.maximumFileSize),
              let data = readData(from: descriptor),
              data.count <= Self.maximumFileSize else {
            return .unavailable
        }
        if let document = try? decoder.decode(FlotisConfigurationDocument.self, from: data),
           document.isStructurallyValid() {
            return .loaded(document)
        }
        if let legacy = try? decoder.decode(LegacyFlotisConfigurationDocumentV1.self, from: data),
           let migrated = legacy.migrated(),
           writeDocument(migrated, to: directoryDescriptor) {
            return .loaded(migrated)
        }
        return .unavailable
    }

    private func writeDocument(
        _ document: FlotisConfigurationDocument,
        to directoryDescriptor: Int32
    ) -> Bool {
        guard existingConfigurationFileIsValidOrMissing(in: directoryDescriptor),
              let data = try? encoder.encode(document),
              data.count <= Self.maximumFileSize else {
            return false
        }

        let temporaryFileName = ".config-\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryFileName.withCString { name in
            Darwin.openat(
                directoryDescriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard temporaryDescriptor >= 0 else { return false }

        var shouldRemoveTemporaryFile = true
        defer {
            Darwin.close(temporaryDescriptor)
            if shouldRemoveTemporaryFile {
                _ = temporaryFileName.withCString { name in
                    Darwin.unlinkat(directoryDescriptor, name, 0)
                }
            }
        }

        guard validateAndRestrictRegularFile(temporaryDescriptor),
              writeData(data, to: temporaryDescriptor),
              Darwin.fsync(temporaryDescriptor) == 0,
              atomicReplace(
                sourceName: temporaryFileName,
                destinationName: fileURL.lastPathComponent,
                in: directoryDescriptor
              ) else {
            return false
        }
        shouldRemoveTemporaryFile = false
        _ = Darwin.fsync(directoryDescriptor)
        return true
    }

    private func existingConfigurationFileIsValidOrMissing(
        in directoryDescriptor: Int32
    ) -> Bool {
        let descriptor = openConfigurationFile(
            in: directoryDescriptor,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0 { return errno == ENOENT }
        defer { Darwin.close(descriptor) }
        return validateAndRestrictRegularFile(descriptor)
    }

    private func openConfigurationFile(in directoryDescriptor: Int32, flags: Int32) -> Int32 {
        fileURL.lastPathComponent.withCString { name in
            Darwin.openat(directoryDescriptor, name, flags)
        }
    }

    private func validateAndRestrictRegularFile(_ descriptor: Int32) -> Bool {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              Darwin.fchmod(descriptor, mode_t(0o600)) == 0,
              Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & mode_t(0o777) == mode_t(0o600) else {
            return false
        }
        return true
    }

    private func readData(from descriptor: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let byteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if byteCount < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if byteCount == 0 { return data }
            guard data.count + byteCount <= Self.maximumFileSize else { return nil }
            buffer.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                data.append(baseAddress, count: byteCount)
            }
        }
    }

    private func writeData(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private func atomicReplace(
        sourceName: String,
        destinationName: String,
        in directoryDescriptor: Int32
    ) -> Bool {
        sourceName.withCString { sourcePath in
            destinationName.withCString { destinationPath in
                Darwin.renameat(
                    directoryDescriptor,
                    sourcePath,
                    directoryDescriptor,
                    destinationPath
                ) == 0
            }
        }
    }

    private func acquireFileLock(on descriptor: Int32) -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        let (deadline, overflow) = start.addingReportingOverflow(
            Self.maximumLockWaitNanoseconds
        )
        guard !overflow else { return false }

        while true {
            guard let lockError = applyFileLock(on: descriptor, type: Int16(F_WRLCK)) else {
                return true
            }
            guard lockError == EACCES || lockError == EAGAIN else { return false }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return false }
            let remainingMicroseconds = max(
                UInt64(1),
                min(Self.lockRetryMicroseconds, (deadline - now) / 1_000)
            )
            _ = Darwin.usleep(useconds_t(remainingMicroseconds))
        }
    }

    private func applyFileLock(on descriptor: Int32, type: Int16) -> Int32? {
        var fileLock = Darwin.flock()
        fileLock.l_type = type
        fileLock.l_whence = Int16(SEEK_SET)
        fileLock.l_start = 0
        fileLock.l_len = 0
        while Darwin.fcntl(descriptor, F_SETLK, &fileLock) != 0 {
            let lockError = errno
            guard lockError == EINTR else { return lockError }
        }
        return nil
    }
}

private extension String {
    var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private func stableModelRouteID(_ selector: String) -> UUID {
    func hash(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var value = seed
        for byte in bytes {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }

    let bytes = Array(selector.utf8)
    let first = hash(bytes, seed: 14_695_981_039_346_656_037)
    let second = hash(Array(bytes.reversed()), seed: 7_806_984_835_845_132_671)
    let hexadecimal = String(format: "%016llx%016llx", first, second)
    let uuidString = "\(hexadecimal.prefix(8))-\(hexadecimal.dropFirst(8).prefix(4))-\(hexadecimal.dropFirst(12).prefix(4))-\(hexadecimal.dropFirst(16).prefix(4))-\(hexadecimal.dropFirst(20).prefix(12))"
    return UUID(uuidString: uuidString)!
}
