import AppKit
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
    var settingsWindowController: FlotisSettingsWindowController?
    let appState = AppState()
    let providerStore = SpeechProviderStore.shared
    var voiceController: VoiceInputController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        voiceController = VoiceInputController(appState: appState, providerStore: providerStore)
        settingsWindowController = FlotisSettingsWindowController(
            appState: appState,
            providerStore: providerStore
        )

        panelController = FloatingPanelController(
            appState: appState,
            voiceController: voiceController!,
            onOpenSettings: { [weak self] in
                self?.settingsWindowController?.showWindow(nil)
            }
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
            self.voiceController?.toggleRecording()
            if self.panelController?.window?.isVisible != true {
                self.panelController?.showWindow(nil)
            }
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

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        appState.voiceState == .injecting ? .terminateCancel : .terminateNow
    }

}

@MainActor
final class FlotisSettingsWindowController: NSWindowController {
    init(
        appState: AppState,
        providerStore: SpeechProviderStore
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.settings
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 760, height: 540)
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                appState: appState,
                providerStore: providerStore,
                onClose: { [weak window] in
                    window?.performClose(nil)
                }
            )
        )
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
