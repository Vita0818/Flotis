import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var appState: AppState
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
                        Text("\(command.title) ⌘⇧\(command.shortcutIndex ?? 0)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(Color.white.opacity(0.15))
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
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
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
        }
        .frame(width: 320, height: 180)
        .onAppear {
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
}
