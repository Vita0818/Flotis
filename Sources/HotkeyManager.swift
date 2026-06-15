import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()
    
    var onHotkeyPressed: ((Int) -> Void)?
    var onTogglePanel: (() -> Void)?
    var onToggleVoice: (() -> Void)?
    
    private var eventMonitor: Any?
    
    private init() {}
    
    func start() {
        let opts = NSDictionary(object: kCFBooleanTrue, forKey: kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString) as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(opts)
        
        if !accessEnabled {
            print("Access Not Enabled")
        }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }
    
    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleEvent(_ event: NSEvent) {
        let isCmdShift = event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift)
        guard isCmdShift else { return }
        
        if event.keyCode == 0x1D { // '0' key code
            onTogglePanel?()
            return
        }
        
        if event.keyCode == 0x0F { // 'R' key code
            onToggleVoice?()
            return
        }
        
        let keyMap: [UInt16: Int] = [
            0x12: 1, // 1
            0x13: 2, // 2
            0x14: 3, // 3
            0x15: 4, // 4
            0x17: 5, // 5
            0x16: 6, // 6
            0x1A: 7, // 7
            0x1C: 8  // 8
        ]
        
        if let index = keyMap[event.keyCode] {
            onHotkeyPressed?(index)
        }
    }
}
