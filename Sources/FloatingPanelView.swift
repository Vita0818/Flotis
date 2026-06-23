import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var commandStore: CommandStore
    @ObservedObject var providerStore: SpeechProviderStore
    let voiceController: VoiceInputController
    @State private var showingSettings = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(commandStore.enabledCommands) { command in
                        Button(action: {
                            injectCommand(command)
                        }) {
                            VStack(spacing: 2) {
                                Text(command.title)
                                    .lineLimit(1)
                                if let shortcut = command.shortcut {
                                    Text(shortcut.displayString)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Color.primary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 138)

            statusArea

            Divider().background(Color.primary.opacity(0.15))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(action: {
                        voiceController.toggleRecording()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: voiceButtonIcon)
                            Text(voiceButtonText)
                        }
                        .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(voiceButtonColor)

                    Picker("", selection: Binding(
                        get: { providerStore.activeProviderID },
                        set: { providerStore.setActiveProvider(id: $0) }
                    )) {
                        ForEach(providerStore.providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)

                    Spacer()

                    Button("设置") {
                        showingSettings = true
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                }

                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundColor(previewColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 400, height: 300)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                appState: appState,
                commandStore: commandStore,
                providerStore: providerStore
            )
        }
        .onAppear {
            appState.checkAccessibility()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            appState.checkAccessibility()
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if !appState.hasAccessibilityPermission {
            VStack(spacing: 4) {
                Text("需要开启辅助功能权限以粘贴到其他 App")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)

                Button("打开设置") {
                    AccessibilityPermission.openSettings()
                }
                .font(.system(size: 10, weight: .bold))
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
        } else if let error = appState.pasteError ?? appState.hotkeyError ?? commandStore.lastError ?? providerStore.lastError {
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.red)
                .padding(.horizontal, 12)
        }
    }

    private func injectCommand(_ command: PromptCommand) {
        ClipboardPasteInjector.shared.inject(text: command.content) { success in
            if !success {
                appState.pasteError = "粘贴失败，可能没有权限。"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    appState.pasteError = nil
                }
            }
        }
    }

    private var voiceButtonIcon: String {
        switch appState.voiceState {
        case .idle: return "mic.fill"
        case .requestingPermission: return "mic.circle"
        case .connecting: return "network"
        case .recording, .streaming: return "stop.circle.fill"
        case .stopping: return "stopwatch"
        case .transcribing: return "hourglass"
        case .injecting: return "square.and.arrow.down.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var voiceButtonText: String {
        switch appState.voiceState {
        case .idle: return "开始"
        case .requestingPermission: return "请求中"
        case .connecting: return "连接中"
        case .recording: return "停止"
        case .streaming: return "停止"
        case .stopping: return "停止中"
        case .transcribing: return "转写中"
        case .injecting: return "注入中"
        case .failed: return "重试"
        }
    }

    private var voiceButtonColor: Color {
        switch appState.voiceState {
        case .recording, .streaming:
            return .red
        case .failed:
            return .orange
        default:
            return .blue
        }
    }

    private var previewText: String {
        if case .failed(let errorMessage) = appState.voiceState {
            return "失败：\(errorMessage)"
        }

        if !appState.transcriptPreview.isEmpty {
            return appState.transcriptPreview
        }

        switch appState.voiceState {
        case .idle:
            return "转写预览文本……"
        case .requestingPermission:
            return "正在请求权限…"
        case .connecting:
            return "正在连接…"
        case .recording:
            return "正在听写…"
        case .streaming:
            return "实时转写中…"
        case .stopping:
            return "正在停止…"
        case .transcribing:
            return "正在转写…"
        case .injecting:
            return "正在注入…"
        case .failed:
            return "失败"
        }
    }

    private var previewColor: Color {
        if case .failed = appState.voiceState {
            return .red
        }
        return .secondary
    }
}
