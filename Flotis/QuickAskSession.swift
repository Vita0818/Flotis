import Combine
import Foundation

struct QuickAskMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

@MainActor
final class QuickAskSession: ObservableObject {
    @Published private(set) var messages: [QuickAskMessage] = []
    @Published var draft = ""
    @Published private(set) var isRequesting = false
    @Published private(set) var lastError: QuickAskError?

    private let service: QuickAskServicing
    private let configurationStore: QuickAskConfigurationStore
    private var activeTask: Task<Void, Never>?
    private var requestGeneration = 0

    init(
        service: QuickAskServicing,
        configurationStore: QuickAskConfigurationStore
    ) {
        self.service = service
        self.configurationStore = configurationStore
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRequesting else { return }
        draft = ""
        send(text)
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRequesting else { return }

        lastError = nil
        messages.append(QuickAskMessage(role: .user, content: text))
        isRequesting = true

        requestGeneration += 1
        let generation = requestGeneration
        let configuration = configurationStore.configuration
        let history = messages

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.service.complete(
                    messages: history,
                    configuration: configuration
                )
                guard generation == self.requestGeneration else { return }
                self.messages.append(QuickAskMessage(role: .assistant, content: reply))
                self.configurationStore.noteConnectionTest(
                    QuickAskConnectionTestResult(
                        status: .ready,
                        detail: UIStrings.quickAskConnected(model: configuration.model)
                    )
                )
            } catch let error as QuickAskError {
                guard generation == self.requestGeneration else { return }
                if error != .cancelled {
                    self.lastError = error
                }
            } catch is CancellationError {
                guard generation == self.requestGeneration else { return }
            } catch {
                guard generation == self.requestGeneration else { return }
                self.lastError = .connectionFailed(error.localizedDescription)
            }

            guard generation == self.requestGeneration else { return }
            self.isRequesting = false
            self.activeTask = nil
        }
    }

    func cancelCurrent() {
        guard isRequesting else { return }
        requestGeneration += 1
        activeTask?.cancel()
        activeTask = nil
        isRequesting = false
        lastError = nil
    }

    func dismissError() {
        lastError = nil
    }

    func close() {
        requestGeneration += 1
        activeTask?.cancel()
        activeTask = nil
        messages = []
        draft = ""
        lastError = nil
        isRequesting = false
    }
}
