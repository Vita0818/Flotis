import Combine
import Dispatch
import Foundation

struct TranscriptionComparisonPreferences: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var isEnabled: Bool
    var modelSelectors: [String]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        isEnabled: Bool = false,
        modelSelectors: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.modelSelectors = modelSelectors
    }
}

final class TranscriptionComparisonStore: ObservableObject {
    static let shared = TranscriptionComparisonStore()
    static let maximumConnectionCount = 4

    @Published private(set) var preferences: TranscriptionComparisonPreferences
    @Published private(set) var lastError: String?

    private let configurationStore: FlotisConfigurationStore
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "flotis.transcriptionComparison.v1",
        configurationStore: FlotisConfigurationStore = .shared
    ) {
        self.configurationStore = configurationStore

        switch configurationStore.load() {
        case .loaded(let document):
            preferences = Self.normalized(document.comparisonPreferences)
            lastError = nil
        case .missing:
            if let data = defaults.data(forKey: storageKey),
               let decoded = try? decoder.decode(
                TranscriptionComparisonPreferences.self,
                from: data
               ),
               decoded.schemaVersion == TranscriptionComparisonPreferences.currentSchemaVersion {
                preferences = Self.normalized(decoded)
            } else {
                preferences = TranscriptionComparisonPreferences()
            }
            let initialPreferences = preferences
            let didSave = configurationStore.update { document in
                document.replaceComparison(initialPreferences)
            }
            lastError = didSave ? nil : UIStrings.comparisonPreferencesSaveFailed
        case .unavailable:
            preferences = TranscriptionComparisonPreferences()
            lastError = UIStrings.comparisonPreferencesUnavailable
        }
    }

    var isEnabled: Bool {
        preferences.isEnabled
    }

    var selectedModelSelectors: [String] {
        preferences.modelSelectors
    }

    func isSelected(_ modelSelector: String) -> Bool {
        preferences.modelSelectors.contains(modelSelector)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled, preferences.modelSelectors.count < 2 {
            lastError = UIStrings.comparisonNeedsTwoConnections
            return false
        }

        var updated = preferences
        updated.isEnabled = enabled
        return persist(updated)
    }

    @discardableResult
    func setModel(_ modelSelector: String, selected: Bool) -> Bool {
        guard FlotisModelSelector(rawValue: modelSelector) != nil else {
            lastError = UIStrings.comparisonPreferencesSaveFailed
            return false
        }
        var updated = preferences
        if selected {
            guard !updated.modelSelectors.contains(modelSelector) else {
                lastError = nil
                return true
            }
            guard updated.modelSelectors.count < Self.maximumConnectionCount else {
                lastError = UIStrings.comparisonConnectionLimit
                return false
            }
            updated.modelSelectors.append(modelSelector)
        } else {
            updated.modelSelectors.removeAll { $0 == modelSelector }
            if updated.modelSelectors.count < 2 {
                updated.isEnabled = false
            }
        }
        return persist(updated)
    }

    func selectedConnections(
        from connections: [TranscriptionConnection]
    ) -> [TranscriptionConnection] {
        let bySelector = Dictionary(
            uniqueKeysWithValues: connections.compactMap { connection in
                connection.configurationModelSelector.map { ($0, connection) }
            }
        )
        return preferences.modelSelectors.compactMap { bySelector[$0] }
    }

    func reconcileAvailableModelSelectors(_ availableModelSelectors: Set<String>) {
        var updated = preferences
        updated.modelSelectors.removeAll { !availableModelSelectors.contains($0) }
        if updated.modelSelectors.count < 2 {
            updated.isEnabled = false
        }
        guard updated != preferences else { return }
        _ = persist(updated)
    }

    @discardableResult
    private func persist(_ candidate: TranscriptionComparisonPreferences) -> Bool {
        var persisted = Self.normalized(candidate)
        let didSave = configurationStore.update { document in
            document.replaceComparison(persisted)
            persisted = document.comparisonPreferences
        }
        if didSave {
            preferences = persisted
            lastError = nil
            return true
        }
        lastError = UIStrings.comparisonPreferencesSaveFailed
        return false
    }

    private static func normalized(
        _ value: TranscriptionComparisonPreferences
    ) -> TranscriptionComparisonPreferences {
        var seen = Set<String>()
        let uniqueSelectors = value.modelSelectors.filter {
            FlotisModelSelector(rawValue: $0) != nil && seen.insert($0).inserted
        }
        let limitedSelectors = Array(uniqueSelectors.prefix(maximumConnectionCount))
        return TranscriptionComparisonPreferences(
            isEnabled: value.isEnabled && limitedSelectors.count >= 2,
            modelSelectors: limitedSelectors
        )
    }
}

struct TranscriptCandidate: Identifiable, Equatable {
    enum Outcome: Equatable {
        case succeeded
        case failed(String)
    }

    let id: UUID
    let connectionName: String
    let model: String
    let modelDisplayName: String?
    let destination: String
    var text: String
    let outcome: Outcome
    let elapsedMilliseconds: Int

    init(
        id: UUID,
        connectionName: String,
        model: String,
        modelDisplayName: String? = nil,
        destination: String,
        text: String,
        outcome: Outcome,
        elapsedMilliseconds: Int
    ) {
        self.id = id
        self.connectionName = connectionName
        self.model = model
        let trimmedDisplayName = modelDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelDisplayName = trimmedDisplayName?.isEmpty == false
            ? trimmedDisplayName
            : nil
        self.destination = destination
        self.text = text
        self.outcome = outcome
        self.elapsedMilliseconds = elapsedMilliseconds
    }

    var isSuccessful: Bool {
        outcome == .succeeded
    }

    var failureMessage: String? {
        guard case .failed(let message) = outcome else { return nil }
        return message
    }

    var primaryDisplayName: String {
        modelDisplayName ?? model
    }

    var secondaryDisplayName: String? {
        modelDisplayName == nil ? connectionName : nil
    }

    var accessibilityDisplayName: String {
        guard let secondaryDisplayName else { return primaryDisplayName }
        return "\(primaryDisplayName), \(secondaryDisplayName)"
    }
}

struct FileTranscriptionComparisonJob {
    let order: Int
    let connectionID: UUID
    let connectionName: String
    let model: String
    let modelDisplayName: String?
    let destination: String
    let transcriber: FileSpeechTranscribing
    let maximumUploadBytes: Int?

    init(
        order: Int,
        connectionID: UUID,
        connectionName: String,
        model: String,
        modelDisplayName: String? = nil,
        destination: String,
        transcriber: FileSpeechTranscribing,
        maximumUploadBytes: Int?
    ) {
        self.order = order
        self.connectionID = connectionID
        self.connectionName = connectionName
        self.model = model
        self.modelDisplayName = modelDisplayName
        self.destination = destination
        self.transcriber = transcriber
        self.maximumUploadBytes = maximumUploadBytes
    }

    func cancel() {
        transcriber.cancel()
    }
}

struct FileTranscriptionComparisonRunner {
    private struct OrderedCandidate {
        let order: Int
        let candidate: TranscriptCandidate
    }

    func run(
        fileURL: URL,
        jobs: [FileTranscriptionComparisonJob]
    ) async throws -> [TranscriptCandidate] {
        try Task.checkCancellation()
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard values.isRegularFile == true, fileSize > 0 else {
            throw NSError(
                domain: "FileTranscriptionComparisonRunner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: UIStrings.recordingFileUnavailable]
            )
        }

        let ordered = await withTaskGroup(of: OrderedCandidate.self) { group in
            for job in jobs {
                group.addTask {
                    let startedAt = DispatchTime.now().uptimeNanoseconds
                    let candidate: TranscriptCandidate

                    if let maximumUploadBytes = job.maximumUploadBytes,
                       fileSize > maximumUploadBytes {
                        candidate = Self.failedCandidate(
                            job: job,
                            message: UIStrings.recordingExceedsUploadLimit(
                                megabytes: maximumUploadBytes / 1_024 / 1_024
                            ),
                            startedAt: startedAt
                        )
                    } else {
                        do {
                            try Task.checkCancellation()
                            let rawText = try await job.transcriber.transcribeFile(fileURL)
                            try Task.checkCancellation()
                            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if text.isEmpty {
                                candidate = Self.failedCandidate(
                                    job: job,
                                    message: UIStrings.emptyTranscript,
                                    startedAt: startedAt
                                )
                            } else {
                                candidate = TranscriptCandidate(
                                    id: job.connectionID,
                                    connectionName: job.connectionName,
                                    model: job.model,
                                    modelDisplayName: job.modelDisplayName,
                                    destination: job.destination,
                                    text: text,
                                    outcome: .succeeded,
                                    elapsedMilliseconds: Self.elapsedMilliseconds(since: startedAt)
                                )
                            }
                        } catch {
                            candidate = Self.failedCandidate(
                                job: job,
                                message: error.localizedDescription,
                                startedAt: startedAt
                            )
                        }
                    }

                    return OrderedCandidate(order: job.order, candidate: candidate)
                }
            }

            var results: [OrderedCandidate] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        try Task.checkCancellation()
        return ordered
            .sorted { $0.order < $1.order }
            .map(\.candidate)
    }

    private static func failedCandidate(
        job: FileTranscriptionComparisonJob,
        message: String,
        startedAt: UInt64
    ) -> TranscriptCandidate {
        TranscriptCandidate(
            id: job.connectionID,
            connectionName: job.connectionName,
            model: job.model,
            modelDisplayName: job.modelDisplayName,
            destination: job.destination,
            text: "",
            outcome: .failed(message),
            elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
        )
    }

    private static func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= startedAt else { return 0 }
        return Int((now - startedAt) / 1_000_000)
    }
}
