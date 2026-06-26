import SwiftUI

@main
struct FlotisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                appState: appDelegate.appState,
                commandStore: appDelegate.commandStore,
                providerStore: appDelegate.providerStore
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: FloatingPanelController?
    let appState = AppState()
    let commandStore = CommandStore.shared
    let providerStore = SpeechProviderStore.shared
    var voiceController: VoiceInputController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.checkAccessibility()
        _ = ClipboardPasteInjector.shared
        voiceController = VoiceInputController(appState: appState, providerStore: providerStore)

        panelController = FloatingPanelController(
            appState: appState,
            commandStore: commandStore,
            providerStore: providerStore,
            voiceController: voiceController!
        )
        panelController?.showWindow(nil)

        HotkeyManager.shared.onCommandHotkeyPressed = { [weak self] commandID in
            guard let self,
                  let command = self.commandStore.command(with: commandID),
                  command.isEnabled else { return }
            self.injectCommand(command)
        }

        HotkeyManager.shared.onTogglePanel = { [weak self] in
            guard let self else { return }
            self.appState.isPanelVisible.toggle()
            if self.appState.isPanelVisible {
                self.panelController?.showWindow(nil)
            } else {
                self.panelController?.close()
            }
        }

        HotkeyManager.shared.onToggleVoice = { [weak self] in
            self?.voiceController?.toggleRecording()
        }

        HotkeyManager.shared.onRegistrationError = { [weak self] message in
            self?.showHotkeyError(message)
        }

        commandStore.onCommandsChanged = { commands in
            DispatchQueue.main.async {
                HotkeyManager.shared.updateCommands(commands)
            }
        }

        HotkeyManager.shared.start(commands: commandStore.commands)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        voiceController?.cancel()
    }

    private func injectCommand(_ command: PromptCommand) {
        ClipboardPasteInjector.shared.inject(text: command.content) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if !success {
                    self.appState.pasteError = UIStrings.pasteFailed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.appState.pasteError = nil
                    }
                }
            }
        }
    }

    private func showHotkeyError(_ message: String) {
        appState.hotkeyError = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.appState.hotkeyError == message {
                self?.appState.hotkeyError = nil
            }
        }
    }
}
