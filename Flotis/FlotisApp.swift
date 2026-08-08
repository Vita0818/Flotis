import AppKit
import Combine
import SwiftUI

@main
struct FlotisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                appState: appDelegate.appState,
                providerStore: appDelegate.providerStore,
                comparisonStore: appDelegate.comparisonStore,
                hotkeyStore: appDelegate.hotkeyStore
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: FloatingPanelController?
    var settingsWindowController: FlotisSettingsWindowController?
    let appState = AppState()
    let providerStore = SpeechProviderStore.shared
    let comparisonStore = TranscriptionComparisonStore.shared
    let hotkeyStore = HotkeyConfigurationStore.shared
    var voiceController: VoiceInputController?
    private var hotkeyStateCancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        comparisonStore.reconcileAvailableModelSelectors(
            providerStore.availableModelSelectors
        )
        voiceController = VoiceInputController(
            appState: appState,
            providerStore: providerStore,
            comparisonStore: comparisonStore
        )
        settingsWindowController = FlotisSettingsWindowController(
            appState: appState,
            providerStore: providerStore,
            comparisonStore: comparisonStore,
            hotkeyStore: hotkeyStore
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

        HotkeyManager.shared.onPreviousComparisonResult = { [weak self] in
            self?.voiceController?.selectPreviousTranscriptCandidate()
        }

        HotkeyManager.shared.onNextComparisonResult = { [weak self] in
            self?.voiceController?.selectNextTranscriptCandidate()
        }

        HotkeyManager.shared.onRegistrationError = { [weak self] message in
            self?.appState.hotkeyError = message
        }

        HotkeyManager.shared.start(
            commands: [],
            hotkeyConfiguration: hotkeyStore.configuration
        )

        hotkeyStore.$configuration
            .removeDuplicates()
            .sink { configuration in
                HotkeyManager.shared.updateHotkeyConfiguration(configuration)
            }
            .store(in: &hotkeyStateCancellables)

        appState.$voiceState
            .combineLatest(appState.$transcriptCandidates)
            .map { state, candidates in
                state == .reviewing
                    && candidates.lazy.filter(\.isSuccessful).prefix(2).count == 2
            }
            .removeDuplicates()
            .sink { enabled in
                HotkeyManager.shared.setComparisonNavigationEnabled(enabled)
            }
            .store(in: &hotkeyStateCancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyStateCancellables.removeAll()
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
        providerStore: SpeechProviderStore,
        comparisonStore: TranscriptionComparisonStore,
        hotkeyStore: HotkeyConfigurationStore
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.settings
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                appState: appState,
                providerStore: providerStore,
                comparisonStore: comparisonStore,
                hotkeyStore: hotkeyStore,
                onClose: { [weak window] in
                    window?.performClose(nil)
                }
            )
        )
        window.contentMinSize = NSSize(width: 820, height: 600)
        window.setContentSize(NSSize(width: 1100, height: 760))
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
