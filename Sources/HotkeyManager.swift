import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onCommandHotkeyPressed: ((UUID) -> Void)?
    var onTogglePanel: (() -> Void)?
    var onToggleVoice: (() -> Void)?
    var onRegistrationError: ((String) -> Void)?

    private enum FixedHotKeyID {
        static let togglePanel: UInt32 = 100
        static let toggleVoice: UInt32 = 200
        static let firstCommand: UInt32 = 1000
    }

    private let hotKeySignature: OSType = 0x464C5448 // "FLTH"
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var commandIDsByHotKeyID: [UInt32: UUID] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var registeredCommands: [PromptCommand] = []

    private init() {}

    func start(commands: [PromptCommand]) {
        registeredCommands = commands
        stop()
        installEventHandler()
        registerConfiguredHotKeys(commands: commands)
    }

    func updateCommands(_ commands: [PromptCommand]) {
        registeredCommands = commands
        start(commands: commands)
    }

    func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        commandIDsByHotKeyID.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else { return status }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.handleHotKey(id: hotKeyID.id)
            }

            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            onRegistrationError?("快捷键事件监听注册失败：\(status)")
        }
    }

    private func registerConfiguredHotKeys(commands: [PromptCommand]) {
        registerHotKey(id: FixedHotKeyID.togglePanel, descriptor: .togglePanel)
        registerHotKey(id: FixedHotKeyID.toggleVoice, descriptor: .toggleVoice)

        var nextHotKeyID = FixedHotKeyID.firstCommand
        for command in commands.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            guard command.isEnabled, let shortcut = command.shortcut else { continue }
            let hotKeyID = nextHotKeyID
            nextHotKeyID += 1
            if registerHotKey(id: hotKeyID, descriptor: shortcut) {
                commandIDsByHotKeyID[hotKeyID] = command.id
            }
        }
    }

    @discardableResult
    private func registerHotKey(id: UInt32, descriptor: KeyboardShortcutDescriptor) -> Bool {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
            return true
        }

        onRegistrationError?("快捷键 \(descriptor.displayString) 注册失败：\(status)")
        return false
    }

    private func handleHotKey(id: UInt32) {
        if id == FixedHotKeyID.togglePanel {
            onTogglePanel?()
            return
        }

        if id == FixedHotKeyID.toggleVoice {
            onToggleVoice?()
            return
        }

        if let commandID = commandIDsByHotKeyID[id] {
            onCommandHotkeyPressed?(commandID)
        }
    }
}

private extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if command { flags |= UInt32(cmdKey) }
        if option { flags |= UInt32(optionKey) }
        if shift { flags |= UInt32(shiftKey) }
        if control { flags |= UInt32(controlKey) }
        return flags
    }
}
