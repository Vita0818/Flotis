import Combine
import Foundation

enum QuickAskConfigurationError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidBaseURL
    case invalidEndpointPath
    case customHostApprovalRequired(String)
    case missingModel
    case invalidTemperature
    case invalidMaxTokens
    case invalidTimeout
    case apiKeyTooLarge
    case systemPromptTooLarge

    var errorDescription: String? {
        switch self {
        case .missingBaseURL: return UIStrings.quickAskBaseURLRequired
        case .invalidBaseURL: return UIStrings.quickAskHTTPSRequired
        case .invalidEndpointPath: return UIStrings.quickAskPathInvalid
        case .customHostApprovalRequired(let host):
            return UIStrings.quickAskCustomHostApprovalRequired(host)
        case .missingModel: return UIStrings.quickAskModelRequired
        case .invalidTemperature: return UIStrings.quickAskTemperatureInvalid
        case .invalidMaxTokens: return UIStrings.quickAskMaxTokensInvalid
        case .invalidTimeout: return UIStrings.quickAskTimeoutInvalid
        case .apiKeyTooLarge: return UIStrings.quickAskAPIKeyTooLarge
        case .systemPromptTooLarge: return UIStrings.quickAskSystemPromptTooLarge
        }
    }
}

enum QuickAskEndpointResolver {
    private static let trustedHosts: Set<String> = ["api.openai.com", "openrouter.ai"]

    static func endpointURL(for configuration: QuickAskConfiguration) throws -> URL {
        let baseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointPath = configuration.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else { throw QuickAskConfigurationError.missingBaseURL }
        guard !endpointPath.isEmpty,
              endpointPath.hasPrefix("/"),
              !endpointPath.hasPrefix("//"),
              !endpointPath.contains("?"),
              !endpointPath.contains("#"),
              !endpointPath.contains("\\"),
              URL(string: endpointPath)?.scheme == nil else {
            throw QuickAskConfigurationError.invalidEndpointPath
        }
        guard !baseURL.contains("\\"),
              var components = URLComponents(string: baseURL),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw QuickAskConfigurationError.invalidBaseURL
        }

        let effectivePort = components.port ?? 443
        let isTrustedDestination = trustedHosts.contains(host) && effectivePort == 443
        guard isTrustedDestination || configuration.customEndpointApproved else {
            throw QuickAskConfigurationError.customHostApprovalRequired(host)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else { throw QuickAskConfigurationError.invalidBaseURL }
        return url
    }

    static func destinationHost(for configuration: QuickAskConfiguration) -> String? {
        URLComponents(
            string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.host?.lowercased()
    }

    static func requiresCustomHostApproval(for configuration: QuickAskConfiguration) -> Bool {
        guard let components = URLComponents(
            string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        let host = components.host?.lowercased(),
        !host.isEmpty else { return false }
        let effectivePort = components.port ?? 443
        return !trustedHosts.contains(host) || effectivePort != 443
    }
}

/// Immutable runtime route snapshot used by one Quick Ask request.
/// The canonical representation is ``QuickAskCatalogConfiguration``.
struct QuickAskConfiguration: Equatable {
    static let defaultSystemPrompt = UIStrings.quickAskDefaultSystemPrompt
    static let maximumAPIKeyLength = 262_144
    static let maximumSystemPromptLength = 32_768

    static let unconfigured = QuickAskConfiguration(
        baseURL: "",
        path: "/chat/completions",
        model: "",
        apiKey: nil,
        temperature: 0.7,
        maxTokens: 2_048,
        timeoutSeconds: 120,
        systemPrompt: defaultSystemPrompt,
        customEndpointApproved: false
    )

    var baseURL: String
    var path: String
    var model: String
    var apiKey: String?
    var temperature: Double
    var maxTokens: Int
    var timeoutSeconds: Int
    var systemPrompt: String
    var customEndpointApproved: Bool
    var providerID: String
    var providerName: String
    var modelDisplayName: String?

    init(
        baseURL: String,
        path: String,
        model: String,
        apiKey: String?,
        temperature: Double,
        maxTokens: Int,
        timeoutSeconds: Int,
        systemPrompt: String,
        customEndpointApproved: Bool,
        providerID: String = "",
        providerName: String = "",
        modelDisplayName: String? = nil
    ) {
        self.baseURL = baseURL
        self.path = path
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
        self.systemPrompt = systemPrompt
        self.customEndpointApproved = customEndpointApproved
        self.providerID = providerID
        self.providerName = providerName
        self.modelDisplayName = modelDisplayName
    }

    var destinationHost: String? { QuickAskEndpointResolver.destinationHost(for: self) }

    var credentialBoundaryIdentifier: String? {
        guard let components = URLComponents(
            string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        let scheme = components.scheme?.lowercased(),
        let host = components.host?.lowercased(),
        !host.isEmpty else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : -1)
        return "\(scheme)://\(host):\(port)"
    }

    var modelTitle: String { modelDisplayName?.quickAskTrimmedNonempty ?? model }

    func normalized() -> QuickAskConfiguration {
        var value = self
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.baseURL.hasSuffix("/") { value.baseURL.removeLast() }
        value.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        value.apiKey = apiKey?.quickAskTrimmedNonempty
        value.providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        value.providerName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.modelDisplayName = modelDisplayName?.quickAskTrimmedNonempty
        return value
    }

    func validationError() -> QuickAskConfigurationError? {
        let value = normalized()
        guard !value.model.isEmpty, value.model.count <= 256 else { return .missingModel }
        guard value.temperature.isFinite, (0 ... 2).contains(value.temperature) else {
            return .invalidTemperature
        }
        guard (64 ... 32_768).contains(value.maxTokens) else { return .invalidMaxTokens }
        guard (5 ... 600).contains(value.timeoutSeconds) else { return .invalidTimeout }
        guard value.apiKey?.count ?? 0 <= Self.maximumAPIKeyLength else {
            return .apiKeyTooLarge
        }
        guard value.systemPrompt.count <= Self.maximumSystemPromptLength else {
            return .systemPromptTooLarge
        }
        do {
            _ = try QuickAskEndpointResolver.endpointURL(for: value)
            return nil
        } catch let error as QuickAskConfigurationError {
            return error
        } catch {
            return .invalidBaseURL
        }
    }
}

struct QuickAskProviderOptions: Codable, Equatable {
    static let defaults = QuickAskProviderOptions(
        baseURL: "",
        path: "/chat/completions",
        apiKey: nil,
        temperature: 0.7,
        maxTokens: 2_048,
        timeoutSeconds: 120,
        systemPrompt: QuickAskConfiguration.defaultSystemPrompt,
        customEndpointApproved: false
    )

    var baseURL: String
    var path: String
    var apiKey: String?
    var temperature: Double
    var maxTokens: Int
    var timeoutSeconds: Int
    var systemPrompt: String
    var customEndpointApproved: Bool

    func normalized() -> QuickAskProviderOptions {
        var value = self
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.baseURL.hasSuffix("/") { value.baseURL.removeLast() }
        value.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        value.apiKey = apiKey?.quickAskTrimmedNonempty
        return value
    }

    var credentialBoundaryIdentifier: String? {
        runtimeConfiguration(modelID: "validation-model").credentialBoundaryIdentifier
    }

    var destinationHost: String? {
        runtimeConfiguration(modelID: "validation-model").destinationHost
    }

    func runtimeConfiguration(
        providerID: String = "",
        providerName: String = "",
        modelID: String,
        modelDisplayName: String? = nil,
        apiKeyOverride: String? = nil
    ) -> QuickAskConfiguration {
        let value = normalized()
        return QuickAskConfiguration(
            baseURL: value.baseURL,
            path: value.path,
            model: modelID,
            apiKey: apiKeyOverride?.quickAskTrimmedNonempty ?? value.apiKey,
            temperature: value.temperature,
            maxTokens: value.maxTokens,
            timeoutSeconds: value.timeoutSeconds,
            systemPrompt: value.systemPrompt,
            customEndpointApproved: value.customEndpointApproved,
            providerID: providerID,
            providerName: providerName,
            modelDisplayName: modelDisplayName
        )
    }
}

struct QuickAskModelConfiguration: Codable, Equatable {
    var name: String?

    init(name: String? = nil) {
        self.name = name?.quickAskTrimmedNonempty
    }
}

struct QuickAskProviderConfiguration: Codable, Equatable {
    var name: String
    var options: QuickAskProviderOptions
    var models: [String: QuickAskModelConfiguration]

    func runtimeConfiguration(
        providerID: String,
        modelID: String,
        apiKeyOverride: String? = nil
    ) -> QuickAskConfiguration? {
        guard let model = models[modelID] else { return nil }
        return options.runtimeConfiguration(
            providerID: providerID,
            providerName: name,
            modelID: modelID,
            modelDisplayName: model.name,
            apiKeyOverride: apiKeyOverride
        )
    }
}

struct QuickAskProviderGroup: Identifiable, Equatable {
    let id: String
    var configuration: QuickAskProviderConfiguration

    var name: String { configuration.name }
    var modelIDs: [String] { configuration.models.keys.sorted() }
}

struct QuickAskCatalogConfiguration: Codable, Equatable {
    static let unconfigured = QuickAskCatalogConfiguration(
        model: "",
        providerOrder: [],
        enabledProviders: [],
        provider: [:]
    )

    var model: String
    var providerOrder: [String]
    var enabledProviders: [String]
    var provider: [String: QuickAskProviderConfiguration]

    private enum CodingKeys: String, CodingKey {
        case model
        case providerOrder = "provider_order"
        case enabledProviders = "enabled_providers"
        case provider
    }

    var providerGroups: [QuickAskProviderGroup] {
        providerOrder.compactMap { providerID in
            provider[providerID].map {
                QuickAskProviderGroup(id: providerID, configuration: $0)
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

    var activeConfiguration: QuickAskConfiguration? {
        guard let selector = FlotisModelSelector(rawValue: model),
              let configuration = provider[selector.providerID] else { return nil }
        return configuration.runtimeConfiguration(
            providerID: selector.providerID,
            modelID: selector.modelID
        )
    }

    var isStructurallyValid: Bool {
        guard provider.count <= FlotisConfigurationStore.maximumProviderCount,
              providerOrder.count == provider.count,
              Set(providerOrder) == Set(provider.keys),
              enabledProviders.count == provider.count,
              Set(enabledProviders) == Set(provider.keys),
              providerOrder.allSatisfy(FlotisModelSelector.isValidProviderID) else {
            return false
        }
        if provider.isEmpty { return model.isEmpty }
        guard availableModelSelectors.contains(model) else { return false }
        for providerID in providerOrder {
            guard let configuration = provider[providerID],
                  !configuration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  configuration.name == configuration.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  !configuration.models.isEmpty,
                  configuration.models.count <= FlotisConfigurationStore.maximumModelCountPerProvider,
                  configuration.models.keys.allSatisfy(FlotisModelSelector.isValidModelID),
                  configuration.options == configuration.options.normalized(),
                  configuration.models.values.allSatisfy({
                      $0.name == $0.name?.quickAskTrimmedNonempty
                  }),
                  let firstModelID = configuration.models.keys.sorted().first,
                  let runtime = configuration.runtimeConfiguration(
                      providerID: providerID,
                      modelID: firstModelID
                  ),
                  runtime.validationError() == nil else {
                return false
            }
        }
        return true
    }
}

enum QuickAskConnectionStatus: String, Equatable {
    case ready
    case missingModel
    case connectionFailed
    case requestTimeout

    var displayText: String {
        switch self {
        case .ready: return UIStrings.quickAskReady
        case .missingModel: return UIStrings.quickAskMissingModel
        case .connectionFailed: return UIStrings.quickAskConnectionFailed
        case .requestTimeout: return UIStrings.quickAskRequestTimeout
        }
    }
}

struct QuickAskConnectionTestResult: Equatable {
    let status: QuickAskConnectionStatus
    let detail: String
}

final class QuickAskConfigurationStore: ObservableObject {
    static let shared = QuickAskConfigurationStore()

    @Published private(set) var catalog: QuickAskCatalogConfiguration
    @Published private(set) var lastError: String?
    @Published private(set) var connectionTestResult: QuickAskConnectionTestResult?

    private let configurationStore: FlotisConfigurationStore

    init(configurationStore: FlotisConfigurationStore = .shared) {
        self.configurationStore = configurationStore
        switch configurationStore.load() {
        case .loaded(let document):
            catalog = document.quickAsk ?? .unconfigured
            lastError = nil
        case .missing:
            catalog = .unconfigured
            lastError = nil
        case .unavailable:
            catalog = .unconfigured
            lastError = UIStrings.quickAskConfigurationUnavailable
        }
    }

    var configuration: QuickAskConfiguration {
        catalog.activeConfiguration ?? .unconfigured
    }

    var activeConfiguration: QuickAskConfiguration? { catalog.activeConfiguration }
    var activeModelSelector: String { catalog.model }
    var providerGroups: [QuickAskProviderGroup] { catalog.providerGroups }

    func providerGroup(id: String) -> QuickAskProviderGroup? {
        catalog.provider[id].map { QuickAskProviderGroup(id: id, configuration: $0) }
    }

    func hasAPIKey(providerID: String) -> Bool {
        catalog.provider[providerID]?.options.apiKey?.quickAskTrimmedNonempty != nil
    }

    func draftRuntimeConfiguration(
        existingProviderID: String?,
        providerName: String,
        options: QuickAskProviderOptions,
        modelID: String,
        apiKeyInput: String
    ) -> QuickAskConfiguration {
        var resolvedOptions = options.normalized()
        if let submittedKey = apiKeyInput.quickAskTrimmedNonempty {
            resolvedOptions.apiKey = submittedKey
        } else if let existingProviderID,
                  let existing = catalog.provider[existingProviderID],
                  existing.options.credentialBoundaryIdentifier
                    == resolvedOptions.credentialBoundaryIdentifier {
            resolvedOptions.apiKey = existing.options.apiKey
        } else {
            resolvedOptions.apiKey = nil
        }
        return resolvedOptions.runtimeConfiguration(
            providerID: existingProviderID ?? "",
            providerName: providerName,
            modelID: modelID
        )
    }

    @discardableResult
    func saveProviderGroup(
        existingProviderID: String?,
        name: String,
        options: QuickAskProviderOptions,
        modelIDs: [String],
        modelDisplayNames: [String: String],
        selectedModelID: String,
        savingAPIKey apiKeyInput: String?
    ) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 256 else {
            lastError = UIStrings.quickAskProviderNameRequired
            return nil
        }

        var seen = Set<String>()
        let normalizedModels = modelIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard normalizedModels.count <= FlotisConfigurationStore.maximumModelCountPerProvider,
              !normalizedModels.isEmpty,
              normalizedModels.allSatisfy({
                  FlotisModelSelector.isValidModelID($0) && seen.insert($0).inserted
              }),
              normalizedModels.contains(selectedModelID) else {
            lastError = UIStrings.quickAskModelsRequired
            return nil
        }

        let providerID = existingProviderID ?? uniqueProviderID(for: normalizedName)
        var resolvedOptions = options.normalized()
        if let submittedKey = apiKeyInput?.quickAskTrimmedNonempty {
            resolvedOptions.apiKey = submittedKey
        } else if let existing = existingProviderID.flatMap({ catalog.provider[$0] }),
                  existing.options.credentialBoundaryIdentifier
                    == resolvedOptions.credentialBoundaryIdentifier {
            resolvedOptions.apiKey = existing.options.apiKey
        } else {
            resolvedOptions.apiKey = nil
        }

        let models = Dictionary(uniqueKeysWithValues: normalizedModels.map { modelID in
            (modelID, QuickAskModelConfiguration(name: modelDisplayNames[modelID]))
        })
        let providerConfiguration = QuickAskProviderConfiguration(
            name: normalizedName,
            options: resolvedOptions,
            models: models
        )
        let runtime = providerConfiguration.runtimeConfiguration(
            providerID: providerID,
            modelID: selectedModelID
        )
        guard let runtime,
              runtime.validationError() == nil,
              let selector = FlotisModelSelector(
                  providerID: providerID,
                  modelID: selectedModelID
              )?.rawValue else {
            lastError = runtime?.validationError()?.localizedDescription
                ?? UIStrings.quickAskConfigurationSaveFailed
            return nil
        }

        var candidate = catalog
        if candidate.provider[providerID] == nil { candidate.providerOrder.append(providerID) }
        candidate.provider[providerID] = providerConfiguration
        candidate.enabledProviders = candidate.providerOrder
        candidate.model = selector
        guard persist(candidate) else { return nil }
        return providerID
    }

    @discardableResult
    func deleteProviderGroup(id: String) -> Bool {
        guard catalog.provider[id] != nil else {
            lastError = UIStrings.quickAskProviderNotFound
            return false
        }
        var candidate = catalog
        candidate.provider[id] = nil
        candidate.providerOrder.removeAll { $0 == id }
        candidate.enabledProviders = candidate.providerOrder
        candidate.model = candidate.providerOrder.first.flatMap { providerID in
            candidate.provider[providerID]?.models.keys.sorted().first.flatMap {
                FlotisModelSelector(providerID: providerID, modelID: $0)?.rawValue
            }
        } ?? ""
        return persist(candidate)
    }

    @discardableResult
    func clearAPIKey(providerID: String) -> Bool {
        guard var provider = catalog.provider[providerID] else {
            lastError = UIStrings.quickAskProviderNotFound
            return false
        }
        provider.options.apiKey = nil
        var candidate = catalog
        candidate.provider[providerID] = provider
        return persist(candidate)
    }

    func noteConnectionTest(_ result: QuickAskConnectionTestResult?) {
        connectionTestResult = result
    }

    private func persist(_ candidate: QuickAskCatalogConfiguration) -> Bool {
        guard candidate.isStructurallyValid else {
            lastError = UIStrings.quickAskConfigurationSaveFailed
            return false
        }
        let didSave = configurationStore.update { document in
            document.replaceQuickAsk(candidate)
        }
        guard didSave else {
            lastError = UIStrings.quickAskConfigurationSaveFailed
            return false
        }
        catalog = candidate
        connectionTestResult = nil
        lastError = nil
        return true
    }

    private func uniqueProviderID(for name: String) -> String {
        let lowered = name.lowercased()
        var base = ""
        var previousWasSeparator = false
        for scalar in lowered.unicodeScalars {
            let isASCIIAlphaNumeric = (48 ... 57).contains(scalar.value)
                || (97 ... 122).contains(scalar.value)
            if isASCIIAlphaNumeric {
                base.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !base.isEmpty {
                base.append("-")
                previousWasSeparator = true
            }
        }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty { base = "quick-ask-provider" }
        base = String(base.prefix(96))
        var candidate = base
        var suffix = 2
        while catalog.provider[candidate] != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}

private extension String {
    var quickAskTrimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
