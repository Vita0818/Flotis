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

private enum SettingsDestination: Hashable {
    case shortcuts
    case transcription

    var title: String {
        switch self {
        case .shortcuts:
            return UIStrings.shortcutSettings
        case .transcription:
            return UIStrings.transcriptionSettings
        }
    }

    var systemImage: String {
        switch self {
        case .shortcuts:
            return "keyboard"
        case .transcription:
            return "waveform.badge.mic"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore
    @ObservedObject var comparisonStore: TranscriptionComparisonStore
    @ObservedObject var hotkeyStore: HotkeyConfigurationStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var destination: SettingsDestination = .shortcuts

    let closeMode: SettingsCloseMode
    let onClose: (() -> Void)?

    init(
        appState: AppState,
        providerStore: SpeechProviderStore,
        comparisonStore: TranscriptionComparisonStore,
        hotkeyStore: HotkeyConfigurationStore,
        closeMode: SettingsCloseMode = .done,
        onClose: (() -> Void)? = nil
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        _providerStore = ObservedObject(wrappedValue: providerStore)
        _comparisonStore = ObservedObject(wrappedValue: comparisonStore)
        _hotkeyStore = ObservedObject(wrappedValue: hotkeyStore)
        self.closeMode = closeMode
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                settingsSidebar

                Divider()

                ZStack {
                    FlotisSystemCanvas()
                        .ignoresSafeArea()

                    settingsContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .frame(minWidth: 820, minHeight: 600)
        .onExitCommand {
            closeSettings()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Flotis")
                    .font(FlotisType.brand(20, .semibold))
                Text(appVersionText)
                    .font(FlotisType.mono(10, .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)

            VStack(spacing: 6) {
                sidebarButton(.shortcuts)
                sidebarButton(.transcription)
            }

            Spacer(minLength: 24)

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(UIStrings.quitFlotis, systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(appState.voiceState == .injecting)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ item: SettingsDestination) -> some View {
        Button {
            destination = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .frame(width: 18)
                Text(item.title)
                Spacer(minLength: 0)
            }
            .font(FlotisType.body(13, .medium))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
                if destination == item {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.13))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == item ? Color.primary : Color.secondary)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return version.map { "v\($0)" } ?? "Flotis"
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch destination {
        case .shortcuts:
            ShortcutSettingsPage(
                appState: appState,
                hotkeyStore: hotkeyStore
            )
        case .transcription:
            VStack(alignment: .leading, spacing: 0) {
                FlotisPageHeader(
                    title: UIStrings.transcriptionSettings,
                    subtitle: UIStrings.transcriptionSettingsSubtitle
                )
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 20)

                IntatisStyleSpeechProviderSettingsView(
                    providerStore: providerStore,
                    comparisonStore: comparisonStore,
                    isActive: destination == .transcription
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

private enum ShortcutSettingsLayout {
    static let controlWidth: CGFloat = 220
    static let controlHeight: CGFloat = 50
    static let controlCornerRadius: CGFloat = 11
}

private struct ShortcutSettingsPage: View {
    @ObservedObject var appState: AppState
    @ObservedObject var hotkeyStore: HotkeyConfigurationStore

    @State private var recordingHotkey: ConfigurableHotkey?
    @State private var validationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FlotisPageHeader(title: UIStrings.shortcutSettings)

                VStack(spacing: 0) {
                    fixedVoiceShortcutRow

                    Divider()
                        .padding(.vertical, 6)

                    ForEach(ConfigurableHotkey.allCases) { hotkey in
                        shortcutSettingRow(hotkey)

                        if hotkey != .nextComparisonResult {
                            Divider()
                                .padding(.vertical, 6)
                        }
                    }

                    Divider()
                        .padding(.vertical, 12)

                    HStack(alignment: .center, spacing: 16) {
                        Text(UIStrings.comparisonShortcutAvailability)
                            .font(FlotisType.caption(12, .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button(UIStrings.resetDefaults) {
                            recordingHotkey = nil
                            if hotkeyStore.resetToDefaults() {
                                validationMessage = nil
                            } else {
                                validationMessage = hotkeyStore.lastError
                            }
                        }
                        .controlSize(.large)
                    }

                    if let hotkeyStatusMessage {
                        Text(hotkeyStatusMessage)
                            .font(FlotisType.caption(12, .medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .flotisContentSurface(cornerRadius: 18)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onDisappear {
            recordingHotkey = nil
            validationMessage = nil
        }
    }

    private var hotkeyStatusMessage: String? {
        validationMessage ?? hotkeyStore.lastError ?? appState.hotkeyError
    }

    private var fixedVoiceShortcutRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(UIStrings.voiceShortcutTitle)
                .font(FlotisType.body(14, .semibold))

            Spacer(minLength: 16)

            shortcutSurface(
                KeyboardShortcutDescriptor.toggleVoice.displayString
            )
            .help(UIStrings.voiceShortcutDescription)
            .accessibilityLabel(
                "\(UIStrings.voiceShortcutTitle), \(KeyboardShortcutDescriptor.toggleVoice.displayString)"
            )
        }
        .frame(minHeight: 68)
    }

    private func shortcutSettingRow(_ hotkey: ConfigurableHotkey) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(hotkey.displayName)
                .font(FlotisType.body(14, .semibold))

            Spacer(minLength: 16)

            if recordingHotkey == hotkey {
                ShortcutRecorderView(
                    onRecord: { descriptor in
                        if let message = hotkeyStore.validationError(
                            for: descriptor,
                            hotkey: hotkey
                        ) {
                            validationMessage = message
                            return
                        }

                        if hotkeyStore.setShortcut(descriptor, for: hotkey) {
                            validationMessage = nil
                            recordingHotkey = nil
                        } else {
                            validationMessage = hotkeyStore.lastError
                        }
                    },
                    onCancel: {
                        recordingHotkey = nil
                        validationMessage = nil
                    }
                )
                .frame(
                    width: ShortcutSettingsLayout.controlWidth,
                    height: ShortcutSettingsLayout.controlHeight
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ShortcutSettingsLayout.controlCornerRadius,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: ShortcutSettingsLayout.controlCornerRadius,
                        style: .continuous
                    )
                    .stroke(Color.accentColor, lineWidth: 1.5)
                )
            } else {
                Button {
                    validationMessage = nil
                    recordingHotkey = hotkey
                } label: {
                    HStack(spacing: 12) {
                        Text(hotkeyStore.configuration[hotkey].displayString)
                            .font(FlotisType.mono(17, .semibold))
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(
                        width: ShortcutSettingsLayout.controlWidth,
                        height: ShortcutSettingsLayout.controlHeight
                    )
                    .contentShape(Rectangle())
                    .background(
                        Color.secondary.opacity(0.1),
                        in: RoundedRectangle(
                            cornerRadius: ShortcutSettingsLayout.controlCornerRadius,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .help(UIStrings.clickToRecordShortcut)
                .accessibilityLabel(
                    "\(hotkey.displayName), \(hotkeyStore.configuration[hotkey].displayString)"
                )

                if hotkeyStore.configuration[hotkey] != hotkey.defaultDescriptor {
                    Button {
                        if hotkeyStore.resetShortcut(hotkey) {
                            validationMessage = nil
                        } else {
                            validationMessage = hotkeyStore.lastError
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(UIStrings.resetThisShortcut)
                    .accessibilityLabel(UIStrings.resetThisShortcut)
                }
            }
        }
        .frame(minHeight: 68)
    }

    private func shortcutSurface(_ shortcut: String) -> some View {
        Text(shortcut)
            .font(FlotisType.mono(17, .semibold))
            .frame(
                width: ShortcutSettingsLayout.controlWidth,
                height: ShortcutSettingsLayout.controlHeight
            )
            .background(
                Color.secondary.opacity(0.1),
                in: RoundedRectangle(
                    cornerRadius: ShortcutSettingsLayout.controlCornerRadius,
                    style: .continuous
                )
            )
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
                                Text("\(provider.displayNameForUI) · \(provider.model)")
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
    case edit(String)
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
    @ObservedObject var comparisonStore: TranscriptionComparisonStore
    let isActive: Bool

    @State private var selectedProviderID: String?
    @State private var providerDraft: SpeechProviderConfig?
    @State private var editorMode: ProviderEditorMode?
    @State private var modelListInput = ""
    @State private var selectedModelID = ""
    @State private var apiKeyInput = ""
    @State private var notice: ProviderNotice?
    @State private var connectionTestState: ConnectionTestViewState = .idle
    @State private var connectionTestGeneration = UUID()
    @State private var connectionTestTask: Task<Void, Never>?

    private var visibleProviders: [SpeechProviderConfig] {
        providerStore.providers.filter(SpeechSettingsPresentation.includes)
    }

    private var visibleProviderGroups: [SpeechProviderGroup] {
        providerStore.providerGroups.filter {
            $0.adapterID == SpeechSettingsPresentation.visibleAdapterID
        }
    }

    private var preferredVisibleProviderID: String? {
        if let active = visibleProviders.first(where: {
            $0.id == providerStore.activeProviderID
        })?.configurationProviderID {
            return active
        }
        return visibleProviderGroups.first?.id
    }

    private var hasUnsavedDraftChanges: Bool {
        guard let providerDraft else { return false }
        if editorMode == .add { return true }
        guard let persistedSelectedProvider, let persistedSelectedGroup else { return true }
        return providerDraft != persistedSelectedProvider
            || parsedModelIDs != persistedSelectedGroup.modelIDs
            || !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedComparisonConnectionCount: Int {
        comparisonStore.selectedModelSelectors.count
    }

    private var parsedModelIDs: [String] {
        var seen = Set<String>()
        return modelListInput.components(separatedBy: .newlines).compactMap { line in
            let modelID = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelID.isEmpty, seen.insert(modelID).inserted else { return nil }
            return modelID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !visibleProviderGroups.isEmpty || editorMode == .add {
                connectionAndComparisonControls
            }

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
                    modelListInput: $modelListInput,
                    selectedModelID: $selectedModelID,
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
                VStack(spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 5) {
                        Text(UIStrings.noOpenAICompatibleConnections)
                            .font(FlotisType.headline(15, .semibold))
                        Text(UIStrings.addConnectionDescription)
                            .font(FlotisType.body(12))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    Button {
                        beginAddingConnection()
                    } label: {
                        Label(UIStrings.addTranscriptionConnection, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            reconcileComparisonConnections()
            selectedProviderID = preferredVisibleProviderID
            loadProviderDraft()
        }
        .onChange(of: selectedProviderID) { newProviderID in
            guard let newProviderID else { return }
            if case .edit(let editingID) = editorMode,
               editingID == newProviderID,
               providerDraft?.configurationProviderID == newProviderID {
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
        .onChange(of: providerStore.providerGroups.map(\.id)) { _ in
            reconcileComparisonConnections()
        }
        .onDisappear {
            cancelConnectionTest(resetState: true)
        }
    }

    private var connectionAndComparisonControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker(
                    UIStrings.editConnection,
                    selection: Binding(
                        get: { selectedProviderID },
                        set: { selectedProviderID = $0 }
                    )
                ) {
                    if editorMode == .add {
                        Text(UIStrings.newConnection)
                            .tag(Optional<String>.none)
                    }
                    ForEach(visibleProviderGroups) { group in
                        Text(providerMenuLabel(group))
                            .tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(hasUnsavedDraftChanges)

                Button {
                    beginAddingConnection()
                } label: {
                    Label(UIStrings.add, systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(hasUnsavedDraftChanges)
                .help(UIStrings.addAnotherConnection)
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Toggle(
                    UIStrings.comparisonMode,
                    isOn: Binding(
                        get: { comparisonStore.isEnabled },
                        set: { _ = comparisonStore.setEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(
                    !comparisonStore.isEnabled
                        && selectedComparisonConnectionCount < 2
                )

                Spacer(minLength: 12)

                Text(UIStrings.comparisonSelectedCount(selectedComparisonConnectionCount))
                    .font(FlotisType.mono(10, .medium))
                    .foregroundStyle(.secondary)
            }

            Text(UIStrings.comparisonModeDescription)
                .font(FlotisType.caption(11, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visibleProviders) { provider in
                        comparisonConnectionToggle(provider)
                    }
                }
            }

            Label(UIStrings.comparisonPrivacyWarning, systemImage: "exclamationmark.shield")
                .font(FlotisType.caption(10, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lastError = comparisonStore.lastError {
                Text(lastError)
                    .font(FlotisType.caption(11, .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .flotisContentSurface(cornerRadius: 14)
    }

    private func comparisonConnectionToggle(
        _ provider: SpeechProviderConfig
    ) -> some View {
        let selector = provider.configurationModelSelector ?? ""
        let isSelected = comparisonStore.isSelected(selector)
        let isReady = providerStore.isProviderReady(provider)
        let selectionLimitReached = selectedComparisonConnectionCount
            >= TranscriptionComparisonStore.maximumConnectionCount

        return Toggle(
            isOn: Binding(
                get: { comparisonStore.isSelected(selector) },
                set: { _ = comparisonStore.setModel(selector, selected: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayNameForUI)
                    .font(FlotisType.body(11, .semibold))
                    .lineLimit(1)
                Text(isReady ? provider.model : UIStrings.connectionNotReady)
                    .font(FlotisType.mono(9, .regular))
                    .foregroundStyle(isReady ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .disabled((!isReady && !isSelected) || (!isSelected && selectionLimitReached))
    }

    private var providerDraftBinding: Binding<SpeechProviderConfig>? {
        guard let providerDraft else { return nil }
        return Binding(
            get: { self.providerDraft ?? providerDraft },
            set: { self.providerDraft = $0 }
        )
    }

    private var persistedSelectedProvider: SpeechProviderConfig? {
        guard let selectedProviderID,
              let group = providerStore.providerGroup(id: selectedProviderID) else { return nil }
        if group.modelIDs.contains(selectedModelID) {
            return group.connection(modelID: selectedModelID)
        }
        return group.modelIDs.first.flatMap(group.connection)
    }

    private var persistedSelectedGroup: SpeechProviderGroup? {
        guard let selectedProviderID else { return nil }
        return providerStore.providerGroup(id: selectedProviderID)
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
        guard let selectedProviderID,
              let group = providerStore.providerGroup(id: selectedProviderID),
              !group.modelIDs.isEmpty else {
            providerDraft = nil
            editorMode = nil
            modelListInput = ""
            selectedModelID = ""
            apiKeyInput = ""
            return
        }
        let activeSelector = FlotisModelSelector(rawValue: providerStore.activeModelSelector)
        let preferredModelID = activeSelector?.providerID == selectedProviderID
            && group.modelIDs.contains(activeSelector?.modelID ?? "")
            ? activeSelector!.modelID
            : group.modelIDs[0]
        selectedModelID = preferredModelID
        modelListInput = group.modelIDs.joined(separator: "\n")
        providerDraft = group.connection(modelID: preferredModelID)
        editorMode = .edit(selectedProviderID)
        apiKeyInput = ""
    }

    private func beginAddingConnection() {
        cancelConnectionTest(resetState: true)
        var draft = providerStore.makeNewConnection(
            adapterID: SpeechSettingsPresentation.visibleAdapterID
        )
        let baseName = UIStrings.newTranscriptionConnectionName
        draft.name = visibleProviderGroups.isEmpty
            ? baseName
            : "\(baseName) \(visibleProviderGroups.count + 1)"
        draft.lastConnectionTest = nil

        selectedProviderID = nil
        providerDraft = draft
        selectedModelID = draft.model
        modelListInput = draft.model
        editorMode = .add
        apiKeyInput = ""
        notice = nil
    }

    private func reconcileComparisonConnections() {
        comparisonStore.reconcileAvailableModelSelectors(
            providerStore.availableModelSelectors
        )
    }

    private func providerMenuLabel(_ group: SpeechProviderGroup) -> String {
        let representative = group.modelIDs.first.flatMap(group.connection)
        let destination = representative?.credentialDestinationIdentifier ?? UIStrings.localDevice
        return "\(group.name) · \(group.modelIDs.count) \(UIStrings.modelsLowercase) · \(destination)"
    }

    private func cancelProviderDraft() {
        notice = nil
        if editorMode == .add {
            selectedProviderID = preferredVisibleProviderID
        }
        loadProviderDraft()
    }

    private func saveProviderDraft() {
        guard var providerDraft,
              !parsedModelIDs.isEmpty,
              parsedModelIDs.contains(selectedModelID) else {
            notice = ProviderNotice(kind: .error, text: UIStrings.modelsRequired)
            return
        }
        providerDraft.model = selectedModelID
        let candidate = providerDraft.normalizedForProtocol()
        if let error = candidate.configurationValidationError() {
            notice = ProviderNotice(kind: .error, text: error)
            return
        }
        let trimmedAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
        let existingProviderID: String?
        switch editorMode {
        case .add:
            existingProviderID = nil
        case .edit(let providerID):
            existingProviderID = providerID
        case nil:
            return
        }

        guard let persistedProviderID = providerStore.saveProviderGroup(
            existingProviderID: existingProviderID,
            draft: candidate,
            modelIDs: parsedModelIDs,
            selectedModelID: selectedModelID,
            savingAPIKey: apiKey
        ),
        let selector = FlotisModelSelector(
            providerID: persistedProviderID,
            modelID: selectedModelID
        ),
        let persisted = providerStore.providers.first(where: {
            $0.configurationModelSelector == selector.rawValue
        }) else {
            notice = ProviderNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.providerConfigSaveFailed
            )
            return
        }

        selectedProviderID = persistedProviderID
        self.providerDraft = persisted
        modelListInput = parsedModelIDs.joined(separator: "\n")
        editorMode = .edit(persistedProviderID)
        apiKeyInput = ""
        cancelConnectionTest(resetState: true)
        reconcileComparisonConnections()
        if persisted.protocolSchema.requiresAPIKey,
           !providerStore.hasAPIKey(for: persisted) {
            notice = ProviderNotice(kind: .warning, text: UIStrings.providerSavedNeedsAPIKey)
        } else {
            notice = ProviderNotice(kind: .success, text: UIStrings.providerSaved)
        }
    }

    private func clearSelectedAPIKey() {
        guard editorMode != .add, let persistedSelectedProvider else { return }
        guard providerStore.clearAPIKey(for: persistedSelectedProvider.id) else {
            notice = ProviderNotice(
                kind: .error,
                text: providerStore.lastError ?? UIStrings.apiKeyClearFailed
            )
            return
        }
        apiKeyInput = ""
        loadProviderDraft()
        notice = ProviderNotice(kind: .success, text: UIStrings.apiKeyCleared)
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
                let tester = TranscriptionConnectionTester(
                    secretLoader: { providerStore.load(for: $0) }
                )
                let record = try await tester.test(
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
    @Binding var modelListInput: String
    @Binding var selectedModelID: String
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
                VStack(alignment: .leading, spacing: 16) {
                    editorSection(
                        UIStrings.connectionDetails,
                        subtitle: UIStrings.connectionDetailsDescription,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    ) {
                        editorField(UIStrings.connectionName) {
                            TextField(
                                UIStrings.connectionName,
                                text: connectionNameBinding
                            )
                        }

                        if provider.protocolSchema.supportsEditableModel {
                            editorField(UIStrings.models) {
                                TextEditor(text: modelListBinding)
                                .font(FlotisType.mono())
                                .frame(minHeight: 72, maxHeight: 112)
                                .padding(6)
                                .background(
                                    Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )

                                Text(UIStrings.modelsOnePerLine)
                                    .font(FlotisType.caption(10, .regular))
                                    .foregroundStyle(.secondary)

                                Picker(UIStrings.currentModel, selection: selectedModelBinding) {
                                    ForEach(parsedModelIDs, id: \.self) { modelID in
                                        Text(modelID).tag(modelID)
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(parsedModelIDs.isEmpty)
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
                                HStack(spacing: 10) {
                                    TextField(
                                        UIStrings.baseURL,
                                        text: baseURLBinding
                                    )
                                    .font(FlotisType.mono())
                                    .frame(minWidth: 260)

                                    TextField(
                                        UIStrings.endpointPath,
                                        text: endpointPathBinding
                                    )
                                    .font(FlotisType.mono())
                                    .frame(minWidth: 150)
                                }
                            }
                        }

                        if let host = provider.credentialDestinationIdentifier,
                           !provider.usesTrustedEndpoint {
                            VStack(alignment: .leading, spacing: 9) {
                                Label {
                                    Text(host)
                                        .font(FlotisType.mono(12, .medium))
                                        .textSelection(.enabled)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .foregroundStyle(.orange)

                                Toggle(
                                    UIStrings.confirmCustomEndpoint,
                                    isOn: customEndpointApprovalBinding
                                )
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.orange.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                        }
                    }

                    if provider.protocolSchema.requiresAPIKey {
                        editorSection(
                            UIStrings.credentials,
                            subtitle: UIStrings.credentialsDescription,
                            systemImage: "key"
                        ) {
                            HStack(spacing: 10) {
                                SecureField(
                                    hasSavedAPIKey
                                        ? UIStrings.apiKeySavedPlaceholder
                                        : UIStrings.apiKey,
                                    text: apiKeyBinding
                                )

                                Button(role: .destructive) {
                                    onClearAPIKey()
                                } label: {
                                    Label(UIStrings.clear, systemImage: "key.slash")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canClearSavedAPIKey)
                                .help(UIStrings.clearAPIKey)
                            }

                            if hasSavedAPIKey {
                                Label(UIStrings.apiKeyStoredLocally, systemImage: "checkmark.circle.fill")
                                    .font(FlotisType.caption(11, .medium))
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    if hasAdvancedSettings {
                        editorSection(
                            UIStrings.optionalParameters,
                            subtitle: nil,
                            systemImage: "slider.horizontal.3"
                        ) {
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

                                    if provider.adapterID == .openAIAudioTranscriptionsHTTPV1 {
                                        editorField(UIStrings.requestEncoding) {
                                            Picker(
                                                UIStrings.requestEncoding,
                                                selection: requestEncodingBinding
                                            ) {
                                                Text(UIStrings.requestEncodingMultipart)
                                                    .tag(TranscriptionRequestEncoding.multipartFormData)
                                                Text(UIStrings.requestEncodingJSONBase64)
                                                    .tag(TranscriptionRequestEncoding.jsonBase64)
                                            }
                                            .pickerStyle(.menu)
                                        }
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                Text(UIStrings.advancedSettings)
                                    .font(FlotisType.body(12, .medium))
                            }
                        }
                    }

                    editorSection(
                        UIStrings.connectionTest,
                        subtitle: UIStrings.connectionTestPrivacyNote,
                        systemImage: "checkmark.circle"
                    ) {
                        HStack(alignment: .center, spacing: 10) {
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
                                .font(FlotisType.caption(11, .medium))
                                .foregroundStyle(connectionTestStatusColor)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.bottom, 20)
            }

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
            .padding(.horizontal, 2)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func editorSection<Content: View>(
        _ title: String,
        subtitle: String?,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(FlotisType.headline(14, .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(FlotisType.caption(11, .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flotisContentSurface(cornerRadius: 16)
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

    private var parsedModelIDs: [String] {
        var seen = Set<String>()
        return modelListInput.components(separatedBy: .newlines).compactMap { line in
            let modelID = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelID.isEmpty, seen.insert(modelID).inserted else { return nil }
            return modelID
        }
    }

    private var modelListBinding: Binding<String> {
        Binding(
            get: { modelListInput },
            set: {
                modelListInput = $0
                if !parsedModelIDs.contains(selectedModelID) {
                    selectedModelID = parsedModelIDs.first ?? ""
                    if !selectedModelID.isEmpty {
                        provider.model = selectedModelID
                    }
                }
                manualConfigurationChanged()
            }
        )
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { selectedModelID },
            set: {
                selectedModelID = $0
                provider.model = $0
                manualConfigurationChanged()
            }
        )
    }

    private var connectionNameBinding: Binding<String> {
        Binding(
            get: { provider.name },
            set: {
                provider.name = $0
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
                if isOpenRouterHost(provider.credentialDestinationIdentifier) {
                    provider.requestEncoding = .jsonBase64
                }
                manualConfigurationChanged()
            }
        )
    }

    private var requestEncodingBinding: Binding<TranscriptionRequestEncoding> {
        Binding(
            get: { provider.requestEncoding },
            set: {
                provider.requestEncoding = $0
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
            || provider.adapterID == .openAIAudioTranscriptionsHTTPV1
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

    private func isOpenRouterHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "openrouter.ai" || host.hasSuffix(".openrouter.ai")
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
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
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
