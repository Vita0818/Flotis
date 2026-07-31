import AppKit
import SwiftUI

private enum SpeechSettingsPresentation {
    static let visibleAdapterID: TranscriptionAdapterID =
        .openAIAudioTranscriptionsHTTPV1

    static func includes(_ provider: SpeechProviderConfig) -> Bool {
        provider.adapterID == visibleAdapterID
    }
}

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

    var systemImage: String {
        switch self {
        case .back:
            return "chevron.left"
        case .done:
            return "checkmark"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore
    @Environment(\.dismiss) private var dismiss

    let closeMode: SettingsCloseMode
    let onClose: (() -> Void)?

    init(
        appState: AppState,
        providerStore: SpeechProviderStore,
        closeMode: SettingsCloseMode = .done,
        onClose: (() -> Void)? = nil
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        _providerStore = ObservedObject(wrappedValue: providerStore)
        self.closeMode = closeMode
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            FlotisSystemCanvas()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(UIStrings.openAICompatible)
                        .font(FlotisType.title(for: UIStrings.openAICompatible, 22))

                    Spacer(minLength: 0)

                    Button {
                        if !appState.hasAccessibilityPermission {
                            AccessibilityPermission.openSettings()
                        }
                    } label: {
                        Image(systemName: "accessibility")
                        .foregroundStyle(
                            appState.hasAccessibilityPermission
                                ? Color.secondary
                                : Color.orange
                        )
                        .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .help(
                        appState.hasAccessibilityPermission
                            ? UIStrings.enabledStatus
                            : UIStrings.openSettings
                    )
                    .accessibilityLabel(UIStrings.accessibility)

                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text(UIStrings.quitFlotis)
                            .font(FlotisType.body(12, .semibold))
                    }
                    .keyboardShortcut("q", modifiers: .command)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(appState.voiceState == .injecting)
                    .help(UIStrings.quitFlotis)

                    Button {
                        closeSettings()
                    } label: {
                        Image(systemName: closeMode.systemImage)
                            .frame(width: 16, height: 16)
                    }
                    .keyboardShortcut("w", modifiers: .command)
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel(closeMode.buttonTitle)
                    .help(closeMode.buttonTitle)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 12)

                SpeechProviderSettingsView(
                    providerStore: providerStore,
                    isActive: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 560)
        .onAppear {
            appState.checkAccessibility()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            appState.checkAccessibility()
        }
        .onExitCommand {
            closeSettings()
        }
    }

    private func closeSettings() {
        if let onClose {
            onClose()
            return
        }

        let settingsWindow = NSApp.keyWindow
        dismiss()
        settingsWindow?.performClose(nil)
    }
}

struct SpeechSettingsOverviewView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore

    private var visibleProviders: [SpeechProviderConfig] {
        providerStore.providers.filter(SpeechSettingsPresentation.includes)
    }

    private var activeVisibleProvider: SpeechProviderConfig? {
        visibleProviders.first { $0.id == providerStore.activeProviderID }
    }

    private var activeVisibleProviderSelection: Binding<UUID?> {
        Binding(
            get: { activeVisibleProvider?.id },
            set: { providerID in
                guard let providerID else { return }
                _ = providerStore.setActiveProvider(id: providerID)
            }
        )
    }

    private var activeVisibleLanguageText: String {
        guard let activeVisibleProvider else {
            return UIStrings.openAICompatibleNotCurrent
        }
        return activeVisibleProvider.language ?? UIStrings.none
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FlotisSettingsSection(UIStrings.speech, systemImage: "waveform") {
                    VStack(spacing: 14) {
                        Picker(
                            UIStrings.currentProvider,
                            selection: activeVisibleProviderSelection
                        ) {
                            Text(UIStrings.openAICompatibleNotCurrent)
                                .tag(Optional<UUID>.none)
                                .disabled(true)

                            ForEach(visibleProviders) { provider in
                                Text(provider.displayNameForUI)
                                    .tag(Optional(provider.id))
                                    .disabled(!providerStore.isProviderReady(provider))
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(visibleProviders.isEmpty)

                        Divider()
                            .opacity(0.45)

                        LabeledContent(
                            UIStrings.status,
                            value: appState.voiceState.displayText
                        )

                        Divider()
                            .opacity(0.45)

                        LabeledContent(
                            UIStrings.language,
                            value: activeVisibleLanguageText
                        )
                    }
                }

                FlotisSettingsSection(UIStrings.permissions, systemImage: "lock.shield") {
                    VStack(spacing: 14) {
                        permissionRow(
                            title: UIStrings.accessibility,
                            systemImage: "accessibility",
                            value: appState.hasAccessibilityPermission
                                ? UIStrings.enabledStatus
                                : UIStrings.disabledStatus,
                            valueColor: appState.hasAccessibilityPermission ? .green : .orange
                        )

                        Divider()
                            .opacity(0.45)

                        permissionRow(
                            title: UIStrings.microphone,
                            systemImage: "mic",
                            value: UIStrings.managedByMacOS
                        )

                        Divider()
                            .opacity(0.45)

                        HStack {
                            Spacer(minLength: 0)
                            Button {
                                AccessibilityPermission.openSettings()
                            } label: {
                                Label(
                                    UIStrings.openSettings,
                                    systemImage: "arrow.up.forward.app"
                                )
                            }
                            .flotisGlassButton()
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func permissionRow(
        title: String,
        systemImage: String,
        value: String,
        valueColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)

            Spacer(minLength: 16)

            Text(value)
                .foregroundStyle(valueColor)
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
    @ObservedObject var providerStore: SpeechProviderStore
    let isActive: Bool

    @State private var selectedProviderID: UUID?
    @State private var providerDraft: SpeechProviderConfig?
    @State private var editorMode: ProviderEditorMode?
    @State private var apiKeyInput = ""
    @State private var notice: ProviderNotice?
    @State private var connectionTestState: ConnectionTestViewState = .idle
    @State private var connectionTestGeneration = UUID()
    @State private var connectionTestTask: Task<Void, Never>?

    private var visibleProviders: [SpeechProviderConfig] {
        providerStore.providers.filter(SpeechSettingsPresentation.includes)
    }

    private var preferredVisibleProviderID: UUID? {
        if visibleProviders.contains(where: { $0.id == providerStore.activeProviderID }) {
            return providerStore.activeProviderID
        }
        return visibleProviders.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let binding = providerDraftBinding {
                if let notice {
                    providerNotice(
                        text: notice.text,
                        kind: notice.kind
                    )
                } else if let lastError = providerStore.lastError {
                    providerNotice(
                        text: lastError,
                        kind: .error
                    )
                }

                SpeechProviderEditorView(
                    provider: binding,
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Button {
                    beginAddingConnection()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(UIStrings.addTranscriptionConnection)
                .help(UIStrings.addTranscriptionConnection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedProviderID = preferredVisibleProviderID
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
        .onChange(of: isActive) { newValue in
            if !newValue {
                cancelConnectionTest(resetState: true)
            }
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
        return visibleProviders.first { $0.id == selectedProviderID }
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
            apiKeyInput = ""
            return
        }
        providerDraft = persistedSelectedProvider
        editorMode = .edit(persistedSelectedProvider.id)
        apiKeyInput = ""
    }

    private func beginAddingConnection() {
        cancelConnectionTest(resetState: true)
        var draft = providerStore.makeNewConnection(
            adapterID: SpeechSettingsPresentation.visibleAdapterID
        )
        draft.name = UIStrings.newTranscriptionConnectionName
        draft.lastConnectionTest = nil

        selectedProviderID = nil
        providerDraft = draft
        editorMode = .add
        apiKeyInput = ""
        notice = nil
    }

    private func cancelProviderDraft() {
        notice = nil
        if editorMode == .add {
            selectedProviderID = preferredVisibleProviderID
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
        apiKeyInput = ""
        cancelConnectionTest(resetState: true)
        if persisted.protocolSchema.requiresAPIKey,
           !providerStore.hasAPIKey(for: persisted) {
            notice = ProviderNotice(kind: .warning, text: UIStrings.providerSavedNeedsAPIKey)
        } else if !providerStore.setActiveProvider(id: persisted.id) {
            notice = ProviderNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.providerConfigSaveFailed
            )
        } else {
            notice = nil
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
        notice = nil
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

    private func noticeSystemImage(for kind: ProviderNoticeKind) -> String {
        switch kind {
        case .information:
            return "info.circle"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private func providerNotice(
        text: String,
        kind: ProviderNoticeKind
    ) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: noticeSystemImage(for: kind))
        }
        .font(FlotisType.caption(12, .medium))
        .foregroundStyle(noticeColor(for: kind))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flotisContentSurface(cornerRadius: 12)
    }

}

private struct SpeechProviderEditorView: View {
    @Binding var provider: SpeechProviderConfig
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if provider.protocolSchema.supportsEditableModel {
                        editorField(UIStrings.model) {
                            TextField(
                                UIStrings.model,
                                text: modelBinding
                            )
                            .font(FlotisType.mono())
                        }
                    } else if let fixedModel = provider.protocolSchema.fixedModel,
                              !fixedModel.isEmpty {
                        LabeledContent(UIStrings.model) {
                            Text(fixedModel)
                                .font(FlotisType.mono())
                        }
                    }

                    if provider.protocolSchema.endpointStyle == .secureHTTP {
                        editorField(UIStrings.endpoint) {
                            HStack(spacing: 8) {
                            TextField(
                                UIStrings.baseURL,
                                text: baseURLBinding
                            )
                            .font(FlotisType.mono())

                            TextField(
                                UIStrings.endpointPath,
                                text: endpointPathBinding
                            )
                            .font(FlotisType.mono())
                            }
                        }
                    }

                    if let host = provider.credentialDestinationIdentifier,
                       !provider.usesTrustedEndpoint {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(host)
                                .font(FlotisType.mono(12, .medium))
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)

                            Toggle(
                                UIStrings.confirmCustomEndpoint,
                                isOn: customEndpointApprovalBinding
                            )
                        }
                        .padding(10)
                        .background(
                            Color.orange.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }

                    if provider.protocolSchema.requiresAPIKey {
                        editorField(UIStrings.apiKey) {
                            HStack(spacing: 8) {
                                SecureField(
                                    hasSavedAPIKey
                                        ? UIStrings.apiKeySavedPlaceholder
                                        : UIStrings.apiKey,
                                    text: apiKeyBinding
                                )

                                Button(role: .destructive) {
                                    onClearAPIKey()
                                } label: {
                                    Image(systemName: "key.slash")
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 28, height: 28)
                                .disabled(!canClearSavedAPIKey)
                                .accessibilityLabel(UIStrings.clearAPIKey)
                                .help(UIStrings.clearAPIKey)
                            }
                        }
                    }

                    if hasAdvancedSettings {
                        DisclosureGroup(
                            isExpanded: $isAdvancedSettingsExpanded
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                if provider.protocolSchema.supportsLanguage {
                                    editorField(UIStrings.language) {
                                        TextField(
                                            UIStrings.language,
                                            text: optionalStringBinding(\.language)
                                        )
                                    }
                                }

                                if provider.protocolSchema.supportsPrompt {
                                    editorField(UIStrings.prompt) {
                                        TextField(
                                            UIStrings.prompt,
                                            text: optionalStringBinding(\.prompt)
                                        )
                                    }
                                }

                                if provider.protocolSchema.supportsTemperature {
                                    editorField(UIStrings.temperature) {
                                        TextField(
                                            UIStrings.temperature,
                                            text: doubleBinding(\.temperature)
                                        )
                                        .font(FlotisType.mono())
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text(UIStrings.advancedSettings)
                                .font(FlotisType.body(12, .medium))
                        }
                    }

                    Divider()
                        .opacity(0.45)

                    HStack(spacing: 10) {
                        Button {
                            if isTestingConnection {
                                onConfigurationChanged()
                            } else {
                                onTestConnection()
                            }
                        } label: {
                            Text(connectionTestButtonTitle)
                        }
                        .disabled(!isTestingConnection && !canTestConnection)
                        .buttonStyle(.bordered)

                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if shouldShowConnectionTestStatus {
                            Label(
                                connectionTestStatusText,
                                systemImage: connectionTestStatusIcon
                            )
                            .font(FlotisType.caption(12, .medium))
                            .foregroundStyle(connectionTestStatusColor)
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, 12)
            }

            Divider()
                .opacity(0.45)

            HStack(spacing: 10) {
                Button {
                    notice = nil
                    onCancel()
                } label: {
                    Text(UIStrings.cancel)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button {
                    onSave()
                } label: {
                    Text(UIStrings.save)
                }
                .disabled(isTestingConnection)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 14)
        }
    }

    private func editorField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FlotisType.caption(12, .semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var customEndpointApprovalBinding: Binding<Bool> {
        Binding(
            get: { provider.isCustomEndpointApproved },
            set: {
                provider.isCustomEndpointApproved = $0
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
        onConfigurationChanged()
    }

    private var hasAdvancedSettings: Bool {
        provider.protocolSchema.supportsLanguage
            || provider.protocolSchema.supportsPrompt
            || provider.protocolSchema.supportsTemperature
    }

    private var isTestingConnection: Bool {
        if case .testing = connectionTestState {
            return true
        }
        return false
    }

    private var shouldShowConnectionTestStatus: Bool {
        if case .idle = connectionTestState {
            return provider.lastConnectionTest != nil
        }
        return true
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

    private var connectionTestStatusIcon: String {
        switch connectionTestState {
        case .testing:
            return "hourglass"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .idle:
            guard let record = provider.lastConnectionTest else {
                return "questionmark.circle"
            }
            guard isTestRecordConfigurationCurrent else {
                return "arrow.triangle.2.circlepath"
            }
            switch record.outcome {
            case .succeeded:
                return "checkmark.circle.fill"
            case .failed:
                return "xmark.circle.fill"
            }
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
