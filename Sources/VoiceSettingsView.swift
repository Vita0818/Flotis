import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var commandStore: CommandStore
    @ObservedObject var providerStore: SpeechProviderStore

    var body: some View {
        TabView {
            CommandsSettingsView(commandStore: commandStore)
                .tabItem {
                    Text("Commands")
                }

            SpeechProviderSettingsView(appState: appState, providerStore: providerStore)
                .tabItem {
                    Text("Speech Providers")
                }
        }
        .padding()
        .frame(width: 720, height: 540)
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
                                Text(command.title.isEmpty ? "未命名命令" : command.title)
                                    .lineLimit(1)
                                Text(command.shortcut?.displayString ?? "无快捷键")
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
                    Button("新增") {
                        commandStore.addCommand()
                        selectedCommandID = sortedCommands.last?.id
                    }

                    Button("删除") {
                        guard let selectedCommandID else { return }
                        commandStore.deleteCommand(id: selectedCommandID)
                        self.selectedCommandID = sortedCommands.first?.id
                    }
                    .disabled(selectedCommandID == nil)

                    Spacer()

                    Button("上移") {
                        guard let selectedCommandID else { return }
                        commandStore.moveCommand(id: selectedCommandID, direction: -1)
                    }
                    .disabled(selectedCommandID == nil)

                    Button("下移") {
                        guard let selectedCommandID else { return }
                        commandStore.moveCommand(id: selectedCommandID, direction: 1)
                    }
                    .disabled(selectedCommandID == nil)
                }

                Button("重置默认") {
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
                    Text("选择一个命令进行编辑。")
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
            Text("Command")
                .font(.headline)

            TextField("Title", text: $command.title)

            Text("Content")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $command.content)
                .font(.system(size: 12))
                .frame(minHeight: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25))
                )

            Toggle("Enabled", isOn: $command.isEnabled)

            HStack(spacing: 8) {
                Text("Shortcut:")
                    .foregroundColor(.secondary)
                Text(command.shortcut?.displayString ?? "无")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button(recordingCommandID == command.id ? "Recording..." : "Record Shortcut") {
                    validationMessage = nil
                    recordingCommandID = command.id
                }
                Button("Clear") {
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
                                Text(provider.name)
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
                    Menu("新增") {
                        Button("Custom Realtime") {
                            providerStore.addProvider(kind: .openAIRealtimeTranscription)
                            selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                        }
                        Button("Custom HTTP") {
                            providerStore.addProvider(kind: .openAIHTTPTranscription)
                            selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                        }
                        Button("Apple Speech") {
                            providerStore.addProvider(kind: .appleSpeechLive)
                            selectedProviderID = providerStore.activeProviderID
                            apiKeyInput = ""
                        }
                    }

                    Button("删除") {
                        providerStore.deleteProvider(id: selectedID)
                        selectedProviderID = providerStore.activeProviderID
                        apiKeyInput = ""
                    }
                    .disabled(providerStore.providers.count <= 1)

                    Spacer()

                    Button("设为当前") {
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
                    Text("选择一个 provider。")
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
                TextField("Provider Name", text: $provider.name)

                Picker("Provider Kind", selection: $provider.kind) {
                    ForEach(SpeechProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                TextField("Model", text: $provider.model)
                    .disabled(provider.kind == .appleSpeechLive)

                TextField("Language", text: optionalStringBinding(\.language))
            }

            if provider.kind == .openAIHTTPTranscription {
                Section(header: Text("HTTP Transcription")) {
                    TextField("Base URL", text: $provider.baseURL)
                    TextField("Endpoint Path", text: $provider.endpointPath)
                    TextField("Prompt", text: optionalStringBinding(\.prompt))
                    TextField("Temperature", text: doubleBinding(\.temperature))
                }
            }

            if provider.kind == .openAIRealtimeTranscription {
                Section(header: Text("Realtime Streaming")) {
                    TextField("Realtime URL", text: optionalStringBinding(\.realtimeURL))
                    TextField("Realtime Path", text: optionalStringBinding(\.realtimePath))
                    TextField("Input Audio Format", text: optionalStringBinding(\.inputAudioFormat))
                    TextField("Sample Rate", text: intBinding(\.sampleRate))
                    TextField("Channels", text: intBinding(\.channels))
                    TextField("Prompt", text: optionalStringBinding(\.prompt))
                    Toggle("Server VAD", isOn: $provider.enableServerVAD)
                }
            }

            if provider.kind != .appleSpeechLive {
                Section(header: Text("API Key")) {
                    HStack {
                        SecureField(providerStore.hasAPIKey(for: provider) ? "已保存，输入新值可覆盖" : "API Key", text: $apiKeyInput)
                        Button("保存 Key") {
                            saveAPIKey()
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }

                    Text("API Key 只保存到 Keychain，不写入配置文件。")
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
            message = "API Key 已保存。"
        } else {
            message = "API Key 保存失败。"
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
        let text = "按下快捷键，Esc 取消"
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
