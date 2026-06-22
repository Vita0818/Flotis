import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()
    
    var onHotkeyPressed: ((Int) -> Void)?
    var onTogglePanel: (() -> Void)?
    var onToggleVoice: (() -> Void)?
    
    private let hotKeySignature: OSType = 0x464C5448 // "FLTH"
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    
    private init() {}
    
    func start() {
        stop()
        installEventHandler()
        registerConfiguredHotKeys()
    }
    
    func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        
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
            print("Failed to install hotkey event handler: \(status)")
        }
    }
    
    private func registerConfiguredHotKeys() {
        let keyMap: [(id: UInt32, keyCode: UInt32)] = [
            (1, 18),
            (2, 19),
            (3, 20),
            (4, 21),
            (5, 23),
            (6, 22),
            (7, 26),
            (8, 28),
            (100, 29), // 0
            (200, 15)  // R, existing voice shortcut
        ]
        
        for hotKey in keyMap {
            registerHotKey(id: hotKey.id, keyCode: hotKey.keyCode)
        }
    }
    
    private func registerHotKey(id: UInt32, keyCode: UInt32) {
        let modifiers = UInt32(cmdKey | optionKey | shiftKey)
        var hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        var hotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        } else {
            print("Failed to register hotkey \(id): \(status)")
        }
    }
    
    private func handleHotKey(id: UInt32) {
        if id == 100 {
            onTogglePanel?()
            return
        }
        
        if id == 200 {
            onToggleVoice?()
            return
        }
        
        if (1...8).contains(id) {
            onHotkeyPressed?(Int(id))
        }
    }
}
