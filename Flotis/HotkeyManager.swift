import AppKit
import Carbon

struct HotKeyPressGate {
    private var pressedIDs: Set<UInt32> = []

    mutating func acceptPress(id: UInt32) -> Bool {
        pressedIDs.insert(id).inserted
    }

    mutating func release(id: UInt32) {
        pressedIDs.remove(id)
    }

    mutating func reset() {
        pressedIDs.removeAll()
    }
}

final class HotkeyManager {
    static let shared = HotkeyManager()
    static let registrationOptions = UInt32(kEventHotKeyExclusive)

    var onCommandHotkeyPressed: ((UUID) -> Void)?
    var onTogglePanel: (() -> Void)?
    var onToggleVoice: (() -> Void)?
    var onPreviousComparisonResult: (() -> Void)?
    var onNextComparisonResult: (() -> Void)?
    var onRegistrationError: ((String?) -> Void)?

    private enum FixedHotKeyID {
        static let togglePanel: UInt32 = 100
        static let toggleVoice: UInt32 = 200
        static let previousComparisonResult: UInt32 = 300
        static let nextComparisonResult: UInt32 = 400
        static let firstCommand: UInt32 = 1000
    }

    private struct DesiredHotKey {
        let descriptor: KeyboardShortcutDescriptor
        let commandID: UUID?
        let displayName: String
    }

    private let hotKeySignature: OSType = 0x464C5448 // "FLTH"
    private let retryDelay: TimeInterval = 2
    private var desiredHotKeysByID: [UInt32: DesiredHotKey] = [:]
    private var hotKeyRefsByID: [UInt32: EventHotKeyRef] = [:]
    private var activeDescriptorsByID: [UInt32: KeyboardShortcutDescriptor] = [:]
    private var commandIDsByHotKeyID: [UInt32: UUID] = [:]
    private var hotKeyIDsByCommandID: [UUID: UInt32] = [:]
    private var registrationFailureStatusByID: [UInt32: OSStatus] = [:]
    private var configurationFailureMessages: [String] = []
    private var eventHandlerFailureStatus: OSStatus?
    private var eventHandlerRef: EventHandlerRef?
    private var retryWorkItem: DispatchWorkItem?
    private var nextCommandHotKeyID = FixedHotKeyID.firstCommand
    private var lastPublishedError: String?
    private var isStarted = false
    private var comparisonNavigationEnabled = false
    private var currentCommands: [PromptCommand] = []
    private var currentHotkeyConfiguration = FlotisHotkeyConfiguration.defaults
    private var pressGate = HotKeyPressGate()

    private init() {}

    func start(
        commands: [PromptCommand],
        hotkeyConfiguration: FlotisHotkeyConfiguration = .defaults
    ) {
        performOnMainThread {
            self.isStarted = true
            self.currentCommands = commands
            self.currentHotkeyConfiguration = hotkeyConfiguration
            self.updateDesiredHotKeys(commands: commands)
            self.synchronizeRegistrations()
        }
    }

    func updateCommands(_ commands: [PromptCommand]) {
        performOnMainThread {
            guard self.isStarted else {
                self.start(
                    commands: commands,
                    hotkeyConfiguration: self.currentHotkeyConfiguration
                )
                return
            }
            self.currentCommands = commands
            self.updateDesiredHotKeys(commands: commands)
            self.synchronizeRegistrations()
        }
    }

    func setComparisonNavigationEnabled(_ enabled: Bool) {
        performOnMainThread {
            guard self.comparisonNavigationEnabled != enabled else { return }
            self.comparisonNavigationEnabled = enabled
            guard self.isStarted else { return }
            self.updateDesiredHotKeys(commands: self.currentCommands)
            self.synchronizeRegistrations()
        }
    }

    func updateHotkeyConfiguration(_ configuration: FlotisHotkeyConfiguration) {
        performOnMainThread {
            guard configuration.isValid else { return }
            self.currentHotkeyConfiguration = configuration
            guard self.isStarted else { return }
            self.updateDesiredHotKeys(commands: self.currentCommands)
            self.synchronizeRegistrations()
        }
    }

    func stop() {
        performOnMainThread {
            self.isStarted = false
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil

            for hotKeyRef in self.hotKeyRefsByID.values {
                UnregisterEventHotKey(hotKeyRef)
            }
            self.hotKeyRefsByID.removeAll()
            self.activeDescriptorsByID.removeAll()
            self.commandIDsByHotKeyID.removeAll()
            self.registrationFailureStatusByID.removeAll()
            self.configurationFailureMessages.removeAll()
            self.desiredHotKeysByID.removeAll()
            self.hotKeyIDsByCommandID.removeAll()
            self.nextCommandHotKeyID = FixedHotKeyID.firstCommand
            self.comparisonNavigationEnabled = false
            self.currentCommands = []
            self.currentHotkeyConfiguration = .defaults
            self.pressGate.reset()

            if let eventHandlerRef = self.eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            self.eventHandlerFailureStatus = nil
            self.publishRegistrationState()
        }
    }

    private func performOnMainThread(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func updateDesiredHotKeys(commands: [PromptCommand]) {
        var desiredHotKeys: [UInt32: DesiredHotKey] = [
            FixedHotKeyID.togglePanel: DesiredHotKey(
                descriptor: currentHotkeyConfiguration.togglePanel,
                commandID: nil,
                displayName: UIStrings.showHideFloatingPanel
            ),
            FixedHotKeyID.toggleVoice: DesiredHotKey(
                descriptor: currentHotkeyConfiguration.toggleVoice,
                commandID: nil,
                displayName: UIStrings.voiceInput
            )
        ]
        if comparisonNavigationEnabled {
            desiredHotKeys[FixedHotKeyID.previousComparisonResult] = DesiredHotKey(
                descriptor: currentHotkeyConfiguration.previousComparisonResult,
                commandID: nil,
                displayName: UIStrings.previousComparisonResult
            )
            desiredHotKeys[FixedHotKeyID.nextComparisonResult] = DesiredHotKey(
                descriptor: currentHotkeyConfiguration.nextComparisonResult,
                commandID: nil,
                displayName: UIStrings.nextComparisonResult
            )
        }
        var configurationFailures: [String] = []
        let currentCommandIDs = Set(commands.map(\.id))

        for commandID in Array(hotKeyIDsByCommandID.keys) where !currentCommandIDs.contains(commandID) {
            hotKeyIDsByCommandID.removeValue(forKey: commandID)
        }

        for command in commands.sorted(by: commandSortOrder) {
            guard command.isEnabled, let shortcut = command.shortcut else { continue }
            if let message = CommandStore.shortcutSafetyError(shortcut) {
                configurationFailures.append(
                    UIStrings.localized(
                        english: "Shortcut \(shortcut.displayString) was not registered: \(message)",
                        simplifiedChinese: "快捷键 \(shortcut.displayString) 未注册：\(message)"
                    )
                )
                continue
            }

            let hotKeyID = hotKeyIDsByCommandID[command.id] ?? allocateHotKeyID(for: command.id)
            desiredHotKeys[hotKeyID] = DesiredHotKey(
                descriptor: shortcut,
                commandID: command.id,
                displayName: command.title.isEmpty ? shortcut.displayString : command.title
            )
        }

        desiredHotKeysByID = desiredHotKeys
        configurationFailureMessages = configurationFailures
    }

    private func commandSortOrder(_ lhs: PromptCommand, _ rhs: PromptCommand) -> Bool {
        if lhs.sortIndex == rhs.sortIndex {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.sortIndex < rhs.sortIndex
    }

    private func allocateHotKeyID(for commandID: UUID) -> UInt32 {
        let hotKeyID = nextCommandHotKeyID
        nextCommandHotKeyID &+= 1
        hotKeyIDsByCommandID[commandID] = hotKeyID
        return hotKeyID
    }

    private func synchronizeRegistrations() {
        retryWorkItem?.cancel()
        retryWorkItem = nil

        for hotKeyID in Array(hotKeyRefsByID.keys) {
            guard let activeDescriptor = activeDescriptorsByID[hotKeyID],
                  let desiredHotKey = desiredHotKeysByID[hotKeyID],
                  activeDescriptor == desiredHotKey.descriptor,
                  commandIDsByHotKeyID[hotKeyID] == desiredHotKey.commandID else {
                unregisterHotKey(id: hotKeyID)
                continue
            }
        }

        for hotKeyID in Array(registrationFailureStatusByID.keys) {
            guard desiredHotKeysByID[hotKeyID] != nil else {
                registrationFailureStatusByID.removeValue(forKey: hotKeyID)
                continue
            }
        }

        guard installEventHandlerIfNeeded() else {
            publishRegistrationState()
            scheduleRetryIfNeeded()
            return
        }

        for hotKeyID in desiredHotKeysByID.keys.sorted() where hotKeyRefsByID[hotKeyID] == nil {
            registerHotKey(id: hotKeyID, desiredHotKey: desiredHotKeysByID[hotKeyID]!)
        }

        publishRegistrationState()
        scheduleRetryIfNeeded()
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerRef != nil {
            eventHandlerFailureStatus = nil
            return true
        }

        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

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
            guard hotKeyID.signature == manager.hotKeySignature else { return noErr }
            let eventKind = GetEventKind(eventRef)
            DispatchQueue.main.async {
                if eventKind == UInt32(kEventHotKeyPressed) {
                    manager.handleHotKeyPress(id: hotKeyID.id)
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    manager.handleHotKeyRelease(id: hotKeyID.id)
                }
            }
            return noErr
        }

        var installedHandlerRef: EventHandlerRef?
        let status = eventTypes.withUnsafeBufferPointer { eventTypeBuffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                eventTypeBuffer.count,
                eventTypeBuffer.baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &installedHandlerRef
            )
        }

        guard status == noErr, let installedHandlerRef else {
            eventHandlerRef = nil
            eventHandlerFailureStatus = status == noErr ? OSStatus(-1) : status
            return false
        }

        eventHandlerRef = installedHandlerRef
        eventHandlerFailureStatus = nil
        return true
    }

    private func registerHotKey(id: UInt32, desiredHotKey: DesiredHotKey) {
        let eventHotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            desiredHotKey.descriptor.keyCode,
            desiredHotKey.descriptor.modifiers.carbonFlags,
            eventHotKeyID,
            GetApplicationEventTarget(),
            Self.registrationOptions,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
            registrationFailureStatusByID[id] = status == noErr ? OSStatus(-1) : status
            commandIDsByHotKeyID.removeValue(forKey: id)
            return
        }

        hotKeyRefsByID[id] = hotKeyRef
        activeDescriptorsByID[id] = desiredHotKey.descriptor
        registrationFailureStatusByID.removeValue(forKey: id)
        if let commandID = desiredHotKey.commandID {
            commandIDsByHotKeyID[id] = commandID
        } else {
            commandIDsByHotKeyID.removeValue(forKey: id)
        }
    }

    private func unregisterHotKey(id: UInt32) {
        if let hotKeyRef = hotKeyRefsByID.removeValue(forKey: id) {
            UnregisterEventHotKey(hotKeyRef)
        }
        activeDescriptorsByID.removeValue(forKey: id)
        commandIDsByHotKeyID.removeValue(forKey: id)
        registrationFailureStatusByID.removeValue(forKey: id)
        pressGate.release(id: id)
    }

    private func scheduleRetryIfNeeded() {
        guard isStarted,
              eventHandlerFailureStatus != nil || !registrationFailureStatusByID.isEmpty else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted else { return }
            self.synchronizeRegistrations()
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
    }

    private func publishRegistrationState() {
        var messages = configurationFailureMessages.sorted()
        if let eventHandlerFailureStatus {
            messages.append(
                UIStrings.localized(
                    english: "Shortcut event listener registration failed: \(eventHandlerFailureStatus)",
                    simplifiedChinese: "快捷键事件监听注册失败：\(eventHandlerFailureStatus)"
                )
            )
        }
        for hotKeyID in registrationFailureStatusByID.keys.sorted() {
            guard let status = registrationFailureStatusByID[hotKeyID],
                  let desiredHotKey = desiredHotKeysByID[hotKeyID] else {
                continue
            }
            messages.append(
                UIStrings.localized(
                    english: "Shortcut \(desiredHotKey.descriptor.displayString) (\(desiredHotKey.displayName)) registration failed: \(status)",
                    simplifiedChinese: "快捷键 \(desiredHotKey.descriptor.displayString)（\(desiredHotKey.displayName)）注册失败：\(status)"
                )
            )
        }

        let message: String?
        if messages.isEmpty {
            message = nil
        } else if messages.count == 1 {
            message = messages[0]
        } else {
            message = messages[0] + UIStrings.additionalShortcutIssues(messages.count - 1)
        }

        guard message != lastPublishedError else { return }
        lastPublishedError = message
        onRegistrationError?(message)
    }

    private func handleHotKeyPress(id: UInt32) {
        guard isStarted, hotKeyRefsByID[id] != nil else { return }
        guard pressGate.acceptPress(id: id) else { return }

        if id == FixedHotKeyID.togglePanel {
            onTogglePanel?()
            return
        }

        if id == FixedHotKeyID.toggleVoice {
            onToggleVoice?()
            return
        }

        if id == FixedHotKeyID.previousComparisonResult {
            onPreviousComparisonResult?()
            return
        }

        if id == FixedHotKeyID.nextComparisonResult {
            onNextComparisonResult?()
            return
        }

        if let commandID = commandIDsByHotKeyID[id] {
            onCommandHotkeyPressed?(commandID)
        }
    }

    private func handleHotKeyRelease(id: UInt32) {
        pressGate.release(id: id)
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
