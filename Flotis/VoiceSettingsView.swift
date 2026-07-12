import AppKit
import SwiftUI

enum SettingsCloseMode {
    case back
    case done

    var buttonTitle: String {
        switch self {
        case .back:
            return UIStrings.back
        case .done:
            return UIStrings.done
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var commandStore: CommandStore
    @ObservedObject var providerStore: SpeechProviderStore
    @Environment(\.dismiss) private var dismiss

    let closeMode: SettingsCloseMode
    let onClose: (() -> Void)?

    init(
        appState: AppState,
        commandStore: CommandStore,
        providerStore: SpeechProviderStore,
        closeMode: SettingsCloseMode = .done,
        onClose: (() -> Void)? = nil
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        _commandStore = ObservedObject(wrappedValue: commandStore)
        _providerStore = ObservedObject(wrappedValue: providerStore)
        self.closeMode = closeMode
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(UIStrings.settings)
                    .font(.headline)

                HStack {
                    Button(closeMode.buttonTitle) {
                        closeSettings()
                    }
                    .keyboardShortcut("w", modifiers: .command)

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            TabView {
                CommandsSettingsView(commandStore: commandStore)
                    .tabItem {
                        Text(UIStrings.commands)
                    }

                SpeechSettingsOverviewView(appState: appState, providerStore: providerStore)
                    .tabItem {
                        Text(UIStrings.speech)
                    }

                SpeechProviderSettingsView(appState: appState, providerStore: providerStore)
                    .tabItem {
                        Text(UIStrings.transcriptionProviders)
                    }
            }
            .padding()
        }
        .frame(width: 720, height: 540)
        .onExitCommand {
            closeSettings()
        }
    }

    private func closeSettings() {
        if let onClose {
            onClose()
            return
        }

        dismiss()
        NSApp.keyWindow?.performClose(nil)
    }
}

struct SpeechSettingsOverviewView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore

    var body: some View {
        Form {
            Section(header: Text(UIStrings.speech)) {
                Picker(UIStrings.currentProvider, selection: Binding(
                    get: { providerStore.activeProviderID },
                    set: { providerStore.setActiveProvider(id: $0) }
                )) {
                    ForEach(providerStore.providers) { provider in
                        Text(provider.name)
                            .tag(provider.id)
                            .disabled(!providerStore.isProviderReady(provider))
                    }
                }

                LabeledContent(UIStrings.status, value: appState.voiceState.displayText)
                LabeledContent(UIStrings.language, value: providerStore.activeProvider.language ?? appState.selectedSpeechLocale)
            }

            Section(header: Text(UIStrings.permissions)) {
                LabeledContent(UIStrings.accessibility, value: appState.hasAccessibilityPermission ? UIStrings.enabledStatus : UIStrings.disabledStatus)
                LabeledContent(UIStrings.microphone, value: UIStrings.managedByMacOS)
                LabeledContent(UIStrings.speechRecognition, value: UIStrings.managedByMacOS)

                Button(UIStrings.openSettings) {
                    AccessibilityPermission.openSettings()
                }
            }
        }
    }
}

struct CommandsSettingsView: View {
    @ObservedObject var commandStore: CommandStore
    @State private var selectedCommandID: UUID?
    @State private var recordingCommandID: UUID?
    @State private var validationMessage: String?
    @State private var commandDraft: PromptCommand?

    private var sortedCommands: [PromptCommand] {
        commandStore.commands.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $selectedCommandID) {
                    ForEach(sortedCommands) { command in
                        HStack(spacing: 8) {
                            Toggle("", isOn: enabledBinding(for: command))
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.title.isEmpty ? UIStrings.untitledCommand : command.title)
                                    .lineLimit(1)
                                Text(command.shortcut?.displayString ?? UIStrings.noShortcut)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .tag(command.id)
                    }
                }
                .frame(minWidth: 250)

                HStack {
                    Button(UIStrings.add) {
                        commandStore.addCommand()
                        selectedCommandID = commandStore.commands.max {
                            $0.sortIndex < $1.sortIndex
                        }?.id
                    }

                    Button(UIStrings.delete) {
                        guard let selectedCommandID else { return }
                        commandStore.deleteCommand(id: selectedCommandID)
                        self.selectedCommandID = sortedCommands.first?.id
                        loadCommandDraft()
                    }
                    .disabled(selectedCommandID == nil)

                    Spacer()

                    Button(UIStrings.moveUp) {
                        guard let selectedCommandID else { return }
                        commandStore.moveCommand(id: selectedCommandID, direction: -1)
                        loadCommandDraft()
                    }
                    .disabled(selectedCommandID == nil)

                    Button(UIStrings.moveDown) {
                        guard let selectedCommandID else { return }
                        commandStore.moveCommand(id: selectedCommandID, direction: 1)
                        loadCommandDraft()
                    }
                    .disabled(selectedCommandID == nil)
                }

                Button(UIStrings.resetDefaults) {
                    commandStore.resetToDefaults()
                    selectedCommandID = commandStore.commands.first?.id
                    loadCommandDraft()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let binding = commandDraftBinding {
                    CommandEditorView(
                        command: binding,
                        commandStore: commandStore,
                        recordingCommandID: $recordingCommandID,
                        validationMessage: $validationMessage,
                        onSave: saveCommandDraft,
                        onCancel: loadCommandDraft
                    )
                } else {
                    Text(UIStrings.selectCommandToEdit)
                        .foregroundColor(.secondary)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if let lastError = commandStore.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if selectedCommandID == nil {
                selectedCommandID = sortedCommands.first?.id
            }
            loadCommandDraft()
        }
        .onChange(of: selectedCommandID) { _ in
            recordingCommandID = nil
            validationMessage = nil
            loadCommandDraft()
        }
    }

    private var commandDraftBinding: Binding<PromptCommand>? {
        guard let commandDraft else { return nil }
        return Binding(
            get: { self.commandDraft ?? commandDraft },
            set: { self.commandDraft = $0 }
        )
    }

    private func enabledBinding(for command: PromptCommand) -> Binding<Bool> {
        Binding(
            get: {
                if commandDraft?.id == command.id {
                    return commandDraft?.isEnabled ?? command.isEnabled
                }
                return commandStore.command(with: command.id)?.isEnabled ?? false
            },
            set: { isEnabled in
                if commandDraft?.id == command.id {
                    commandDraft?.isEnabled = isEnabled
                } else {
                    commandStore.setEnabled(isEnabled, for: command.id)
                }
            }
        )
    }

    private func loadCommandDraft() {
        guard let selectedCommandID else {
            commandDraft = nil
            return
        }
        commandDraft = commandStore.command(with: selectedCommandID)
    }

    private func saveCommandDraft() {
        guard let draft = commandDraft else { return }
        if let shortcut = draft.shortcut,
           let error = commandStore.validateShortcut(shortcut, for: draft.id) {
            validationMessage = error
            return
        }
        commandStore.updateCommand(draft)
        validationMessage = nil
        loadCommandDraft()
    }
}

struct CommandEditorView: View {
    @Binding var command: PromptCommand
    @ObservedObject var commandStore: CommandStore
    @Binding var recordingCommandID: UUID?
    @Binding var validationMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.commands)
                .font(.headline)

            TextField(UIStrings.title, text: $command.title)

            Text(UIStrings.content)
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $command.content)
                .font(.system(size: 12))
                .frame(minHeight: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25))
                )

            Toggle(UIStrings.enabled, isOn: $command.isEnabled)

            HStack(spacing: 8) {
                Text("\(UIStrings.shortcut):")
                    .foregroundColor(.secondary)
                Text(command.shortcut?.displayString ?? UIStrings.none)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button(recordingCommandID == command.id ? UIStrings.recordingShortcut : UIStrings.recordShortcut) {
                    validationMessage = nil
                    recordingCommandID = command.id
                }
                Button(UIStrings.clear) {
                    command.shortcut = nil
                    validationMessage = nil
                }
            }

            if recordingCommandID == command.id {
                ShortcutRecorderView(
                    onRecord: { descriptor in
                        if let message = commandStore.validateShortcut(descriptor, for: command.id) {
                            validationMessage = message
                            recordingCommandID = nil
                            return
                        }
                        command.shortcut = descriptor
                        validationMessage = nil
                        recordingCommandID = nil
                    },
                    onCancel: {
                        recordingCommandID = nil
                        validationMessage = nil
                    }
                )
                .frame(height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
            }

            HStack {
                Spacer()
                Button(UIStrings.cancel) {
                    recordingCommandID = nil
                    validationMessage = nil
                    onCancel()
                }
                Button(UIStrings.save) {
                    recordingCommandID = nil
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private enum ProviderEditorMode: Equatable {
    case add
    case edit(UUID)
}

private enum ProviderNoticeKind {
    case information
    case success
    case warning
    case error
}

private struct ProviderNotice {
    let kind: ProviderNoticeKind
    let text: String
}

private enum ConnectionTestViewState {
    case idle
    case testing
    case succeeded
    case failed(String)
}

struct SpeechProviderSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore
    @State private var selectedProviderID: UUID?
    @State private var providerDraft: SpeechProviderConfig?
    @State private var editorMode: ProviderEditorMode?
    @State private var selectedPresetID: TranscriptionProviderPreset.ID?
    @State private var apiKeyInput = ""
    @State private var notice: ProviderNotice?
    @State private var connectionTestState: ConnectionTestViewState = .idle
    @State private var connectionTestGeneration = UUID()
    @State private var connectionTestTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $selectedProviderID) {
                    ForEach(providerStore.providers) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .lineLimit(1)
                                Text(provider.adapterID.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if provider.id == providerStore.activeProviderID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            } else if !providerStore.isProviderReady(provider) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                            }
                        }
                        .tag(provider.id)
                    }
                }
                .frame(minWidth: 250)

                HStack {
                    Button(UIStrings.addTranscriptionConnection) {
                        beginAddingConnection()
                    }
                    .disabled(editorMode == .add)

                    Button(UIStrings.delete) {
                        guard let providerID = selectedProviderID else { return }
                        if providerStore.deleteProvider(id: providerID) {
                            self.selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                            notice = nil
                            loadProviderDraft()
                        } else {
                            notice = ProviderNotice(
                                kind: .error,
                                text: providerStore.lastError ?? UIStrings.providerConfigSaveFailed
                            )
                        }
                    }
                    .disabled(
                        providerStore.providers.count <= 1
                            || selectedProviderID == nil
                            || editorMode == .add
                    )

                    Spacer()

                    Button(UIStrings.setAsCurrent) {
                        guard let selectedProviderID else { return }
                        if providerStore.setActiveProvider(id: selectedProviderID) {
                            syncAppStateFromActiveProvider()
                            notice = nil
                        } else {
                            notice = ProviderNotice(
                                kind: .error,
                                text: providerStore.lastError ?? UIStrings.providerConfigSaveFailed
                            )
                        }
                    }
                    .disabled(!canActivateSelectedProvider)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let binding = providerDraftBinding {
                    Text(
                        editorMode == .add
                            ? UIStrings.addTranscriptionConnection
                            : UIStrings.editTranscriptionConnection
                    )
                    .font(.headline)

                    SpeechProviderEditorView(
                        provider: binding,
                        selectedPresetID: $selectedPresetID,
                        apiKeyInput: $apiKeyInput,
                        notice: $notice,
                        hasSavedAPIKey: hasSavedAPIKeyForDraft,
                        canClearSavedAPIKey: canClearSavedAPIKey,
                        connectionTestState: connectionTestState,
                        isConnectionTestCurrent: isDraftConnectionTestCurrent,
                        canTestConnection: canTestDraftConnection,
                        onSave: saveProviderDraft,
                        onCancel: cancelProviderDraft,
                        onClearAPIKey: clearSelectedAPIKey,
                        onTestConnection: testProviderDraft,
                        onConfigurationChanged: invalidateConnectionTest
                    )
                } else {
                    Text(UIStrings.selectProviderToEdit)
                        .foregroundColor(.secondary)
                }

                if let notice {
                    Text(notice.text)
                        .font(.caption)
                        .foregroundColor(noticeColor(for: notice.kind))
                } else if let lastError = providerStore.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            selectedProviderID = providerStore.activeProviderID
            loadProviderDraft()
        }
        .onChange(of: selectedProviderID) { newProviderID in
            guard let newProviderID else { return }
            if case .edit(let editingID) = editorMode,
               editingID == newProviderID,
               providerDraft?.id == newProviderID {
                return
            }
            apiKeyInput = ""
            notice = nil
            loadProviderDraft()
        }
        .onDisappear {
            cancelConnectionTest(resetState: true)
        }
    }

    private var providerDraftBinding: Binding<SpeechProviderConfig>? {
        guard let providerDraft else { return nil }
        return Binding(
            get: { self.providerDraft ?? providerDraft },
            set: { self.providerDraft = $0 }
        )
    }

    private var persistedSelectedProvider: SpeechProviderConfig? {
        guard let selectedProviderID else { return nil }
        return providerStore.providers.first { $0.id == selectedProviderID }
    }

    private var draftMatchesPersistedSecretBoundary: Bool {
        guard let providerDraft, let persistedSelectedProvider else { return false }
        return providerDraft.secretBoundaryIdentifier
            == persistedSelectedProvider.secretBoundaryIdentifier
    }

    private var hasSavedAPIKeyForDraft: Bool {
        guard draftMatchesPersistedSecretBoundary,
              let persistedSelectedProvider else { return false }
        return providerStore.hasAPIKey(for: persistedSelectedProvider)
    }

    private var canClearSavedAPIKey: Bool {
        hasSavedAPIKeyForDraft && draftMatchesPersistedSecretBoundary
    }

    private var canActivateSelectedProvider: Bool {
        guard editorMode != .add, let persistedSelectedProvider else { return false }
        if let providerDraft,
           providerDraft.normalizedForProtocol() != persistedSelectedProvider.normalizedForProtocol() {
            return false
        }
        return providerStore.isProviderReady(persistedSelectedProvider)
    }

    private var isDraftConnectionTestCurrent: Bool {
        guard let providerDraft,
              providerDraft.lastConnectionTest?.outcome == .succeeded else { return false }
        if case .succeeded = connectionTestState {
            return true
        }
        let hasReplacementKey = !apiKeyInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return !hasReplacementKey && providerDraft.isConnectionTestCurrent
    }

    private var canTestDraftConnection: Bool {
        guard let providerDraft,
              providerDraft.configurationValidationError() == nil else { return false }
        if providerDraft.protocolSchema.requiresAPIKey {
            let hasDraftKey = !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasDraftKey || hasSavedAPIKeyForDraft
        }
        return true
    }

    private func loadProviderDraft() {
        cancelConnectionTest(resetState: true)
        guard let persistedSelectedProvider else {
            providerDraft = nil
            editorMode = nil
            selectedPresetID = nil
            apiKeyInput = ""
            return
        }
        providerDraft = persistedSelectedProvider
        editorMode = .edit(persistedSelectedProvider.id)
        selectedPresetID = nil
        apiKeyInput = ""
    }

    private func beginAddingConnection() {
        cancelConnectionTest(resetState: true)
        var draft = providerStore.makeNewConnection(
            adapterID: .openAIAudioTranscriptionsHTTPV1
        )
        draft.name = UIStrings.newTranscriptionConnectionName
        draft.lastConnectionTest = nil

        selectedProviderID = nil
        providerDraft = draft
        editorMode = .add
        selectedPresetID = nil
        apiKeyInput = ""
        notice = ProviderNotice(kind: .information, text: UIStrings.newConnectionDraftHint)
    }

    private func cancelProviderDraft() {
        notice = nil
        if editorMode == .add {
            selectedProviderID = providerStore.activeProviderID
        }
        loadProviderDraft()
    }

    private func saveProviderDraft() {
        guard let providerDraft else { return }
        let candidate = providerDraft.normalizedForProtocol()
        if let error = candidate.configurationValidationError() {
            notice = ProviderNotice(kind: .error, text: error)
            return
        }
        let trimmedAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
        let didSave: Bool
        switch editorMode {
        case .add:
            didSave = providerStore.createConnection(candidate, savingAPIKey: apiKey) != nil
        case .edit:
            didSave = providerStore.updateProvider(candidate, savingAPIKey: apiKey)
        case nil:
            return
        }

        guard didSave,
              let persisted = providerStore.providers.first(where: { $0.id == candidate.id }) else {
            notice = ProviderNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.providerConfigSaveFailed
            )
            return
        }

        selectedProviderID = persisted.id
        self.providerDraft = persisted
        editorMode = .edit(persisted.id)
        selectedPresetID = nil
        apiKeyInput = ""
        cancelConnectionTest(resetState: true)
        if persisted.protocolSchema.requiresAPIKey,
           !providerStore.hasAPIKey(for: persisted) {
            notice = ProviderNotice(kind: .warning, text: UIStrings.providerSavedNeedsAPIKey)
        } else {
            notice = ProviderNotice(kind: .success, text: UIStrings.providerSaved)
        }
    }

    private func clearSelectedAPIKey() {
        guard editorMode != .add, let selectedProviderID else { return }
        guard providerStore.clearAPIKey(for: selectedProviderID) else {
            notice = ProviderNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.apiKeyClearFailed
            )
            return
        }
        apiKeyInput = ""
        notice = ProviderNotice(kind: .success, text: UIStrings.apiKeyCleared)
        loadProviderDraft()
    }

    private func testProviderDraft() {
        guard var candidate = providerDraft?.normalizedForProtocol(), canTestDraftConnection else {
            notice = ProviderNotice(kind: .error, text: UIStrings.connectionTestConfigurationInvalid)
            return
        }

        cancelConnectionTest(resetState: false)
        let generation = UUID()
        connectionTestGeneration = generation
        connectionTestState = .testing
        notice = nil
        let trimmedAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
        if apiKey != nil {
            // The raw secret never enters the fingerprint. A transient revision keeps
            // this probe from being mistaken for a test of the previously stored key.
            candidate.credentialRevision = (persistedSelectedProvider?.credentialRevision ?? 0) + 1
            candidate.lastConnectionTest = nil
        }

        connectionTestTask = Task { @MainActor in
            do {
                let record = try await TranscriptionConnectionTester.shared.test(
                    connection: candidate,
                    apiKey: apiKey
                )
                guard !Task.isCancelled,
                      connectionTestGeneration == generation,
                      providerDraft?.id == candidate.id else { return }
                providerDraft?.credentialRevision = candidate.credentialRevision
                providerDraft?.lastConnectionTest = record
                switch record.outcome {
                case .succeeded:
                    connectionTestState = .succeeded
                case .failed:
                    connectionTestState = .failed(record.safeSummary)
                }
                connectionTestTask = nil
            } catch is CancellationError {
                guard connectionTestGeneration == generation else { return }
                connectionTestState = .idle
                connectionTestTask = nil
            } catch {
                guard !Task.isCancelled,
                      connectionTestGeneration == generation,
                      providerDraft?.id == candidate.id else { return }
                var testedCandidate = candidate
                testedCandidate.recordConnectionTest(
                    outcome: .failed,
                    safeSummary: error.localizedDescription
                )
                providerDraft?.credentialRevision = testedCandidate.credentialRevision
                providerDraft?.lastConnectionTest = testedCandidate.lastConnectionTest
                let safeSummary = testedCandidate.lastConnectionTest?.safeSummary
                    ?? UIStrings.connectionTestUnknownFailure
                connectionTestState = .failed(safeSummary)
                connectionTestTask = nil
            }
        }
    }

    private func invalidateConnectionTest() {
        cancelConnectionTest(resetState: true)
    }

    private func cancelConnectionTest(resetState: Bool) {
        connectionTestGeneration = UUID()
        connectionTestTask?.cancel()
        connectionTestTask = nil
        if resetState {
            connectionTestState = .idle
        }
    }

    private func noticeColor(for kind: ProviderNoticeKind) -> Color {
        switch kind {
        case .information:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func syncAppStateFromActiveProvider() {
        let provider = providerStore.activeProvider
        if provider.kind == .appleSpeechLive {
            appState.selectedSpeechLocale = provider.language ?? "zh-CN"
        }
    }
}

private struct SpeechProviderEditorView: View {
    @Binding var provider: SpeechProviderConfig
    @Binding var selectedPresetID: TranscriptionProviderPreset.ID?
    @Binding var apiKeyInput: String
    @Binding var notice: ProviderNotice?
    let hasSavedAPIKey: Bool
    let canClearSavedAPIKey: Bool
    let connectionTestState: ConnectionTestViewState
    let isConnectionTestCurrent: Bool
    let canTestConnection: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onClearAPIKey: () -> Void
    let onTestConnection: () -> Void
    let onConfigurationChanged: () -> Void

    @State private var isAdvancedSettingsExpanded = false

    var body: some View {
        Form {
            Section {
                TextField(UIStrings.connectionName, text: $provider.name)

                Picker(UIStrings.protocolCompatibilityType, selection: adapterBinding) {
                    Section(header: Text(UIStrings.recommendedAdapters)) {
                        ForEach(recommendedAdapters) { adapterID in
                            Text(adapterID.displayName).tag(adapterID)
                        }
                    }
                    Section(header: Text(UIStrings.advancedNativeAdapters)) {
                        ForEach(advancedAdapters) { adapterID in
                            Text(adapterID.displayName).tag(adapterID)
                        }
                    }
                }

                Picker(UIStrings.quickPreset, selection: presetBinding) {
                    Text(UIStrings.customPreset)
                        .tag(Optional<TranscriptionProviderPreset.ID>.none)
                    ForEach(availablePresets) { preset in
                        Text(preset.displayName)
                            .tag(Optional(preset.id))
                    }
                }

                if provider.protocolSchema.supportsEditableModel {
                    TextField(UIStrings.model, text: modelBinding)
                } else if let fixedModel = provider.protocolSchema.fixedModel,
                          !fixedModel.isEmpty {
                    LabeledContent(UIStrings.model, value: fixedModel)
                }

                if provider.protocolSchema.supportsLanguage {
                    TextField(UIStrings.language, text: optionalStringBinding(\.language))
                }
            }

            if provider.protocolSchema.endpointStyle == .secureHTTP {
                Section(header: Text(UIStrings.connectionEndpoint)) {
                    TextField(UIStrings.baseURL, text: baseURLBinding)
                    TextField(UIStrings.endpointPath, text: endpointPathBinding)
                }
            }

            if provider.protocolSchema.endpointStyle == .secureWebSocket {
                Section(header: Text(UIStrings.connectionEndpoint)) {
                    TextField(UIStrings.realtimeURL, text: realtimeURLBinding)
                    TextField(UIStrings.realtimePath, text: optionalStringBinding(\.realtimePath))
                }
            }

            if let host = provider.credentialDestinationIdentifier {
                Section(header: Text(UIStrings.credentialDestination)) {
                    Text(String(format: UIStrings.credentialDestinationFormat, host))
                        .font(.caption)
                        .foregroundColor(provider.usesTrustedEndpoint ? .secondary : .orange)
                    if !provider.usesTrustedEndpoint {
                        Toggle(
                            UIStrings.confirmCustomEndpoint,
                            isOn: customEndpointApprovalBinding
                        )
                    }
                }
            }

            if provider.protocolSchema.requiresAPIKey {
                Section(header: Text(UIStrings.apiKey)) {
                    HStack {
                        SecureField(
                            hasSavedAPIKey ? UIStrings.apiKeySavedPlaceholder : UIStrings.apiKey,
                            text: apiKeyBinding
                        )
                        Button(UIStrings.clearAPIKey) {
                            onClearAPIKey()
                        }
                        .disabled(!canClearSavedAPIKey)
                    }

                    Text(UIStrings.apiKeyStoredInKeychain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if hasAdvancedSettings {
                Section {
                    DisclosureGroup(
                        UIStrings.advancedSettings,
                        isExpanded: $isAdvancedSettingsExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            if provider.protocolSchema.supportsPrompt {
                                TextField(UIStrings.prompt, text: optionalStringBinding(\.prompt))
                            }
                            if provider.protocolSchema.supportsTemperature {
                                TextField(UIStrings.temperature, text: doubleBinding(\.temperature))
                            }
                            if provider.adapterID == .volcengineBigASRWSV3 {
                                TextField(
                                    UIStrings.volcengineResourceID,
                                    text: volcengineResourceIDBinding
                                )
                                LabeledContent(
                                    UIStrings.volcengineModelName,
                                    value: provider.volcengineModelName
                                )
                            }
                            if provider.protocolSchema.supportsVolcengineTwoPass {
                                Toggle(
                                    UIStrings.volcengineTwoPassRecognition,
                                    isOn: volcengineTwoPassBinding
                                )
                            }
                            if provider.protocolSchema.fixedInputAudioFormat != nil {
                                LabeledContent(
                                    UIStrings.inputAudioFormat,
                                    value: fixedAudioDescription
                                )
                            } else if !provider.protocolSchema.allowedInputAudioFormats.isEmpty {
                                Picker(UIStrings.inputAudioFormat, selection: inputAudioFormatBinding) {
                                    ForEach(
                                        provider.protocolSchema.allowedInputAudioFormats.sorted(),
                                        id: \.self
                                    ) { format in
                                        Text(format.uppercased()).tag(format)
                                    }
                                }
                                LabeledContent(
                                    UIStrings.audioParameters,
                                    value: fixedAudioDescription
                                )
                            }
                            if let responseMode = provider.protocolSchema.responseMode {
                                LabeledContent(
                                    UIStrings.responseMode,
                                    value: responseMode == .json
                                        ? UIStrings.responseModeJSON
                                        : UIStrings.responseModeSSE
                                )
                            }
                            if provider.adapterID == .openAIRealtimeTranscriptionGA {
                                Text(UIStrings.openAIRealtimeManualCommit)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if provider.adapterID == .glmASRHTTPSSEV4 {
                                Text(UIStrings.glmUploadLimits)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }

            Section(header: Text(UIStrings.connectionTest)) {
                HStack(spacing: 10) {
                    Button(connectionTestButtonTitle) {
                        if isTestingConnection {
                            onConfigurationChanged()
                        } else {
                            onTestConnection()
                        }
                    }
                    .disabled(!isTestingConnection && !canTestConnection)

                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(connectionTestStatusText)
                        .font(.caption)
                        .foregroundColor(connectionTestStatusColor)
                        .lineLimit(2)
                }

                if let record = provider.lastConnectionTest {
                    Text(
                        "\(UIStrings.lastConnectionTest): "
                            + record.testedAt.formatted(date: .abbreviated, time: .shortened)
                            + " · \(UIStrings.adapterVersion) \(record.adapterVersion)"
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Text(UIStrings.connectionTestPrivacyNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button(UIStrings.cancel) {
                    notice = nil
                    onCancel()
                }
                Button(UIStrings.save) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTestingConnection)
            }
        }
    }

    private var recommendedAdapters: [TranscriptionAdapterID] {
        TranscriptionAdapterID.allCases.filter { !advancedAdapters.contains($0) }
    }

    private var advancedAdapters: [TranscriptionAdapterID] {
        [
            .dashScopeParaformerWSV1,
            .volcengineBigASRWSV3,
            .glmASRHTTPSSEV4
        ]
    }

    private var availablePresets: [TranscriptionProviderPreset] {
        TranscriptionProviderPreset.catalog.filter { $0.adapterID == provider.adapterID }
    }

    private var adapterBinding: Binding<TranscriptionAdapterID> {
        Binding(
            get: { provider.adapterID },
            set: { newAdapterID in
                guard newAdapterID != provider.adapterID else { return }
                provider = provider.applyingAdapter(newAdapterID)
                selectedPresetID = nil
                apiKeyInput = ""
                notice = ProviderNotice(
                    kind: hasSavedAPIKey ? .warning : .information,
                    text: hasSavedAPIKey
                        ? UIStrings.adapterChangeClearsAPIKey
                        : UIStrings.adapterChangedHint
                )
                onConfigurationChanged()
            }
        )
    }

    private var presetBinding: Binding<TranscriptionProviderPreset.ID?> {
        Binding(
            get: { selectedPresetID },
            set: { newPresetID in
                selectedPresetID = newPresetID
                guard let newPresetID,
                      let preset = availablePresets.first(where: { $0.id == newPresetID }) else {
                    onConfigurationChanged()
                    return
                }
                let oldDestination = provider.credentialDestinationIdentifier
                provider = preset.applying(to: provider)
                if provider.credentialDestinationIdentifier != oldDestination {
                    provider.isCustomEndpointApproved = false
                }
                notice = ProviderNotice(kind: .information, text: UIStrings.presetAppliedHint)
                onConfigurationChanged()
            }
        )
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<SpeechProviderConfig, String?>) -> Binding<String> {
        Binding(
            get: { provider[keyPath: keyPath] ?? "" },
            set: {
                provider[keyPath: keyPath] = $0.isEmpty ? nil : $0
                manualConfigurationChanged()
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { provider.model },
            set: {
                provider.model = $0
                manualConfigurationChanged()
            }
        )
    }

    private var endpointPathBinding: Binding<String> {
        Binding(
            get: { provider.endpointPath },
            set: {
                provider.endpointPath = $0
                manualConfigurationChanged()
            }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKeyInput },
            set: {
                apiKeyInput = $0
                onConfigurationChanged()
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { provider.baseURL },
            set: { newValue in
                let oldHost = provider.credentialDestinationIdentifier
                provider.baseURL = newValue
                resetCustomEndpointApprovalIfHostChanged(from: oldHost)
                manualConfigurationChanged()
            }
        )
    }

    private var realtimeURLBinding: Binding<String> {
        Binding(
            get: { provider.realtimeURL ?? "" },
            set: { newValue in
                let oldHost = provider.credentialDestinationIdentifier
                provider.realtimeURL = newValue.isEmpty ? nil : newValue
                resetCustomEndpointApprovalIfHostChanged(from: oldHost)
                manualConfigurationChanged()
            }
        )
    }

    private var volcengineResourceIDBinding: Binding<String> {
        Binding(
            get: { provider.volcengineResourceID },
            set: {
                provider.volcengineResourceID = $0
                manualConfigurationChanged()
            }
        )
    }

    private var volcengineTwoPassBinding: Binding<Bool> {
        Binding(
            get: { provider.enableVolcengineTwoPassRecognition },
            set: {
                provider.enableVolcengineTwoPassRecognition = $0
                manualConfigurationChanged()
            }
        )
    }

    private var customEndpointApprovalBinding: Binding<Bool> {
        Binding(
            get: { provider.isCustomEndpointApproved },
            set: {
                provider.isCustomEndpointApproved = $0
                manualConfigurationChanged()
            }
        )
    }

    private var fixedAudioDescription: String {
        let schema = provider.protocolSchema
        let format = (
            schema.fixedInputAudioFormat
                ?? provider.inputAudioFormat
                ?? schema.defaultInputAudioFormat
        )?.uppercased() ?? UIStrings.none
        let rate = schema.fixedSampleRate.map(String.init) ?? UIStrings.none
        let channels = schema.fixedChannels.map(String.init) ?? UIStrings.none
        return "\(format) · \(rate) Hz · \(channels) ch"
    }

    private var inputAudioFormatBinding: Binding<String> {
        Binding(
            get: {
                provider.inputAudioFormat
                    ?? provider.protocolSchema.defaultInputAudioFormat
                    ?? provider.protocolSchema.allowedInputAudioFormats.sorted().first
                    ?? ""
            },
            set: {
                provider.inputAudioFormat = $0
                manualConfigurationChanged()
            }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<SpeechProviderConfig, Double?>) -> Binding<String> {
        Binding(
            get: {
                if let value = provider[keyPath: keyPath] {
                    return "\(value)"
                }
                return ""
            },
            set: {
                provider[keyPath: keyPath] = Double($0)
                manualConfigurationChanged()
            }
        )
    }

    private func manualConfigurationChanged() {
        selectedPresetID = nil
        onConfigurationChanged()
    }

    private var hasAdvancedSettings: Bool {
        provider.protocolSchema.supportsPrompt
            || provider.protocolSchema.supportsTemperature
            || provider.protocolSchema.supportsVolcengineTwoPass
            || provider.protocolSchema.fixedInputAudioFormat != nil
            || !provider.protocolSchema.allowedInputAudioFormats.isEmpty
            || provider.protocolSchema.responseMode != nil
            || provider.adapterID == .volcengineBigASRWSV3
    }

    private var isTestingConnection: Bool {
        if case .testing = connectionTestState {
            return true
        }
        return false
    }

    private var connectionTestButtonTitle: String {
        isTestingConnection ? UIStrings.cancelConnectionTest : UIStrings.testConnection
    }

    private var connectionTestStatusText: String {
        switch connectionTestState {
        case .testing:
            return UIStrings.testingConnection
        case .succeeded:
            return UIStrings.connectionTestSucceeded
        case .failed(let summary):
            return String(format: UIStrings.connectionTestFailedFormat, summary)
        case .idle:
            guard let record = provider.lastConnectionTest else {
                return UIStrings.connectionNotTested
            }
            guard isTestRecordConfigurationCurrent else {
                return UIStrings.connectionTestInvalidated
            }
            switch record.outcome {
            case .succeeded:
                return UIStrings.connectionTestStillValid
            case .failed:
                return String(format: UIStrings.connectionTestFailedFormat, record.safeSummary)
            }
        }
    }

    private var connectionTestStatusColor: Color {
        switch connectionTestState {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .testing:
            return .secondary
        case .idle:
            if isTestRecordConfigurationCurrent,
               provider.lastConnectionTest?.outcome == .failed {
                return .red
            }
            return isConnectionTestCurrent ? .green : .secondary
        }
    }

    private var isTestRecordConfigurationCurrent: Bool {
        let hasReplacementKey = !apiKeyInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return !hasReplacementKey && provider.isConnectionTestCurrent
    }

    private func resetCustomEndpointApprovalIfHostChanged(from oldHost: String?) {
        if provider.credentialDestinationIdentifier != oldHost {
            provider.isCustomEndpointApproved = false
        }
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let onRecord: (KeyboardShortcutDescriptor) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderCaptureView {
        let view = ShortcutRecorderCaptureView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderCaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class ShortcutRecorderCaptureView: NSView {
    var onRecord: ((KeyboardShortcutDescriptor) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        dirtyRect.fill()
        let text = UIStrings.shortcutCaptureHint
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: max(8, (bounds.width - size.width) / 2),
                y: max(8, (bounds.height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let flags = event.modifierFlags
        let modifiers = ShortcutModifiers(
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            control: flags.contains(.control)
        )

        let descriptor = KeyboardShortcutDescriptor(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        onRecord?(descriptor)
    }
}
