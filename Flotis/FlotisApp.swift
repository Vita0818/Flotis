import SwiftUI

@main
struct FlotisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                appState: appDelegate.appState,
                providerStore: appDelegate.providerStore
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: FloatingPanelController?
    let appState = AppState()
    let providerStore = SpeechProviderStore.shared
    var voiceController: VoiceInputController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.checkAccessibility()
        _ = ClipboardPasteInjector.shared
        voiceController = VoiceInputController(appState: appState, providerStore: providerStore)

        panelController = FloatingPanelController(
            appState: appState,
            providerStore: providerStore,
            voiceController: voiceController!
        )
        panelController?.showWindow(nil)

        HotkeyManager.shared.onTogglePanel = { [weak self] in
            guard let self else { return }
            if self.panelController?.window?.isVisible == true {
                self.panelController?.close()
            } else {
                self.panelController?.showWindow(nil)
            }
        }

        HotkeyManager.shared.onToggleVoice = { [weak self] in
            guard let self else { return }
            if self.panelController?.window?.isVisible != true {
                self.panelController?.showWindow(nil)
            }
            self.voiceController?.toggleRecording()
        }

        HotkeyManager.shared.onRegistrationError = { [weak self] message in
            self?.appState.hotkeyError = message
        }

        HotkeyManager.shared.start(commands: [])
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        voiceController?.cancel()
    }

}
