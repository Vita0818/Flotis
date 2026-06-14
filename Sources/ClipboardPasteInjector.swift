import AppKit
import CoreGraphics

final class ClipboardPasteInjector {
    static let shared = ClipboardPasteInjector()
    private init() {}
    
    func inject(text: String, completion: @escaping (Bool) -> Void) {
        guard AccessibilityPermission.check() else {
            completion(false)
            return
        }
        
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        simulateCmdV()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let items = previousItems, !items.isEmpty {
                pasteboard.writeObjects(items)
            }
            completion(true)
        }
    }
    
    private func simulateCmdV() {
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
