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
                        Text(provider.displayNameForUI).tag(provider.id)
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

    private var sortedCommands: [PromptCommand] {
        commandStore.commands.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $selectedCommandID) {
                    ForEach(sortedCommands) { command in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { commandStore.command(with: command.id)?.isEnabled ?? false },
                                set: { commandStore.setEnabled($0, for: command.id) }
                            ))
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
                        selectedCommandID = sortedCommands.last?.id
                    }

                    Button(UIStrings.delete) {
                        guard let selectedCommandID else { return }
                        commandStore.deleteCommand(id: selectedCommandID)
                        self.selectedCommandID = sortedCommands.first?.id
                    }
                    .disabled(selectedCommandID == nil)

                    Spacer()

                    Button(UIStrings.moveUp) {
                        guard let selectedCommandID else { return }
                        commandStore.moveCommand(id: selectedCommandID, direction: -1)
                    }
                    .disabled(selectedCommandID == nil)

                    Button(UIStrings.moveDown) {
                        guard let selectedCommandID else { return }
                        commandStore.moveCommand(id: selectedCommandID, direction: 1)
                    }
                    .disabled(selectedCommandID == nil)
                }

                Button(UIStrings.resetDefaults) {
                    commandStore.resetToDefaults()
                    selectedCommandID = commandStore.commands.first?.id
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let selectedCommandID,
                   let binding = commandBinding(for: selectedCommandID) {
                    CommandEditorView(
                        command: binding,
                        commandStore: commandStore,
                        recordingCommandID: $recordingCommandID,
                        validationMessage: $validationMessage
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
        }
    }

    private func commandBinding(for id: UUID) -> Binding<PromptCommand>? {
        guard let fallback = commandStore.command(with: id) else { return nil }
        return Binding(
            get: { commandStore.command(with: id) ?? fallback },
            set: { commandStore.updateCommand($0) }
        )
    }
}

struct CommandEditorView: View {
    @Binding var command: PromptCommand
    @ObservedObject var commandStore: CommandStore
    @Binding var recordingCommandID: UUID?
    @Binding var validationMessage: String?

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
        }
    }
}

struct SpeechProviderSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore
    @State private var selectedProviderID: UUID?
    @State private var apiKeyInput = ""
    @State private var message: String?

    private var selectedID: UUID {
        selectedProviderID ?? providerStore.activeProviderID
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $selectedProviderID) {
                    ForEach(providerStore.providers) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayNameForUI)
                                    .lineLimit(1)
                                Text(provider.kind.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if provider.id == providerStore.activeProviderID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .tag(provider.id)
                    }
                }
                .frame(minWidth: 250)

                HStack {
                    Menu(UIStrings.add) {
                        Button(UIStrings.customRealtime) {
                            providerStore.addProvider(kind: .openAIRealtimeTranscription)
                            selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                        }
                        Button(UIStrings.customHTTP) {
                            providerStore.addProvider(kind: .openAIHTTPTranscription)
                            selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                        }
                        Button(UIStrings.appleSpeech) {
                            providerStore.addProvider(kind: .appleSpeechLive)
                            selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                        }
                    }

                    Button(UIStrings.delete) {
                        providerStore.deleteProvider(id: selectedID)
                        selectedProviderID = providerStore.activeProviderID
                        apiKeyInput = ""
                    }
                    .disabled(providerStore.providers.count <= 1)

                    Spacer()

                    Button(UIStrings.setAsCurrent) {
                        providerStore.setActiveProvider(id: selectedID)
                        syncAppStateFromActiveProvider()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let binding = providerBinding(for: selectedID) {
                    SpeechProviderEditorView(
                        provider: binding,
                        providerStore: providerStore,
                        apiKeyInput: $apiKeyInput,
                        message: $message
                    )
                } else {
                    Text(UIStrings.selectProviderToEdit)
                        .foregroundColor(.secondary)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.contains("失败") ? .red : .secondary)
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
        }
        .onChange(of: selectedProviderID) { _ in
            apiKeyInput = ""
            message = nil
        }
    }

    private func providerBinding(for id: UUID) -> Binding<SpeechProviderConfig>? {
        guard let fallback = providerStore.providers.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { providerStore.providers.first(where: { $0.id == id }) ?? fallback },
            set: { providerStore.updateProvider($0) }
        )
    }

    private func syncAppStateFromActiveProvider() {
        let provider = providerStore.activeProvider
        if provider.kind == .appleSpeechLive {
            appState.selectedSpeechLocale = provider.language ?? "zh-CN"
        }
    }
}

struct SpeechProviderEditorView: View {
    @Binding var provider: SpeechProviderConfig
    @ObservedObject var providerStore: SpeechProviderStore
    @Binding var apiKeyInput: String
    @Binding var message: String?

    var body: some View {
        Form {
            Section {
                TextField(UIStrings.providerName, text: $provider.name)

                Picker(UIStrings.providerKind, selection: $provider.kind) {
                    ForEach(SpeechProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                TextField(UIStrings.model, text: $provider.model)
                    .disabled(provider.kind == .appleSpeechLive)

                TextField(UIStrings.language, text: optionalStringBinding(\.language))
            }

            if provider.kind == .openAIHTTPTranscription {
                Section(header: Text(UIStrings.httpTranscriptionSection)) {
                    TextField(UIStrings.baseURL, text: $provider.baseURL)
                    TextField(UIStrings.endpointPath, text: $provider.endpointPath)
                    TextField(UIStrings.prompt, text: optionalStringBinding(\.prompt))
                    TextField(UIStrings.temperature, text: doubleBinding(\.temperature))
                }
            }

            if provider.kind == .openAIRealtimeTranscription {
                Section(header: Text(UIStrings.realtimeStreamingSection)) {
                    TextField(UIStrings.realtimeURL, text: optionalStringBinding(\.realtimeURL))
                    TextField(UIStrings.realtimePath, text: optionalStringBinding(\.realtimePath))
                    TextField(UIStrings.inputAudioFormat, text: optionalStringBinding(\.inputAudioFormat))
                    TextField(UIStrings.sampleRate, text: intBinding(\.sampleRate))
                    TextField(UIStrings.channels, text: intBinding(\.channels))
                    TextField(UIStrings.prompt, text: optionalStringBinding(\.prompt))
                    Toggle(UIStrings.serverVAD, isOn: $provider.enableServerVAD)
                }
            }

            if provider.kind != .appleSpeechLive {
                Section(header: Text(UIStrings.apiKey)) {
                    HStack {
                        SecureField(providerStore.hasAPIKey(for: provider) ? UIStrings.apiKeySavedPlaceholder : UIStrings.apiKey, text: $apiKeyInput)
                        Button(UIStrings.saveAPIKey) {
                            saveAPIKey()
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }

                    Text(UIStrings.apiKeyStoredInKeychain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<SpeechProviderConfig, String?>) -> Binding<String> {
        Binding(
            get: { provider[keyPath: keyPath] ?? "" },
            set: { provider[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<SpeechProviderConfig, Int?>) -> Binding<String> {
        Binding(
            get: {
                if let value = provider[keyPath: keyPath] {
                    return "\(value)"
                }
                return ""
            },
            set: { provider[keyPath: keyPath] = Int($0) }
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
            set: { provider[keyPath: keyPath] = Double($0) }
        )
    }

    private func saveAPIKey() {
        if provider.apiKeyReference == nil {
            provider.apiKeyReference = "flotis.speechprovider.\(provider.id.uuidString).apikey"
        }

        if providerStore.saveAPIKey(apiKeyInput, for: provider) {
            apiKeyInput = ""
            message = UIStrings.apiKeySaved
        } else {
            message = UIStrings.apiKeySaveFailed
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
