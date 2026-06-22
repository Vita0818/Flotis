import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var appState: AppState
    let voiceController: VoiceInputController
    @State private var showingSettings = false
    let commands = CommandStore.defaultCommands
    
    let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(commands) { command in
                    Button(action: {
                        injectCommand(command)
                    }) {
                        Text("\(command.title) ⌘⌥⇧\(command.shortcutIndex ?? 0)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, minHeight: 28)
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
            .padding(.top, 24) // Added more top padding
            
            Spacer()
            
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
                .padding(.bottom, 8)
            } else if let error = appState.pasteError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.bottom, 8)
            }
            
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
                    
                    Picker("", selection: $appState.voiceMode) {
                        ForEach(VoiceInputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                    
                    Spacer()
                    
                    Button("设置") {
                        showingSettings = true
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                }
                
                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 380, height: 280) // Made the interface larger
        .sheet(isPresented: $showingSettings) {
            VoiceSettingsView(appState: appState)
        }
        .onAppear {
            appState.checkAccessibility()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            appState.checkAccessibility()
        }
    }
    
    private func injectCommand(_ command: PromptCommand) {
        ClipboardPasteInjector.shared.inject(text: command.content) { success in
            if !success {
                appState.pasteError = "粘贴失败，可能没有权限"
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
        case .recording: return "stop.circle.fill"
        case .transcribing: return "hourglass"
        case .injecting: return "square.and.arrow.down.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    private var voiceButtonText: String {
        switch appState.voiceState {
        case .idle: return "开始"
        case .requestingPermission: return "请求中"
        case .recording: return "停止"
        case .transcribing: return "转写中"
        case .injecting: return "注入中"
        case .failed: return "重试"
        }
    }
    
    private var voiceButtonColor: Color {
        switch appState.voiceState {
        case .recording: return .red
        case .failed: return .orange
        default: return .blue
        }
    }
    
    private var previewText: String {
        if case .failed(let errorMsg) = appState.voiceState {
            return "错误: \(errorMsg)"
        }
        return appState.transcriptPreview.isEmpty ? "转写预览文本……" : appState.transcriptPreview
    }
}
