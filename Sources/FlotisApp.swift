import SwiftUI

@main
struct FlotisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: FloatingPanelController?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.checkAccessibility()
        
        panelController = FloatingPanelController(appState: appState)
        panelController?.showWindow(nil)
        
        HotkeyManager.shared.onHotkeyPressed = { [weak self] index in
            guard let self = self else { return }
            let commands = CommandStore.defaultCommands
            if let command = commands.first(where: { $0.shortcutIndex == index }) {
                ClipboardPasteInjector.shared.inject(text: command.content) { success in
                    if !success {
                        self.appState.pasteError = "粘贴失败，可能没有权限"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.appState.pasteError = nil
                        }
                    }
                }
            }
        }
        
        HotkeyManager.shared.onTogglePanel = { [weak self] in
            guard let self = self else { return }
            self.appState.isPanelVisible.toggle()
            if self.appState.isPanelVisible {
                self.panelController?.showWindow(nil)
            } else {
                self.panelController?.close()
            }
        }
        
        HotkeyManager.shared.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
    }
}
