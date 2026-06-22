import AppKit
import CoreGraphics

final class ClipboardPasteInjector {
    static let shared = ClipboardPasteInjector()
    
    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    private var lastTargetApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    
    private init() {
        rememberFrontmostApplication()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.remember(application: application)
        }
    }
    
    func inject(text: String, completion: @escaping (Bool) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.inject(text: text, completion: completion)
            }
            return
        }
        
        guard AccessibilityPermission.check() else {
            completion(false)
            return
        }
        
        let targetApplication = targetApplicationForInjection()
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
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(pasteboard, with: previousItems)
            completion(false)
            return
        }
        
        activateTargetApplicationIfNeeded(targetApplication)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForModifierKeysToRelease(until: Date().addingTimeInterval(0.8)) {
                let didPostPaste = self.simulateCmdV()
            
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.restorePasteboard(pasteboard, with: previousItems)
                    completion(didPostPaste)
                }
            }
        }
    }
    
    private func rememberFrontmostApplication() {
        if let application = NSWorkspace.shared.frontmostApplication {
            remember(application: application)
        }
    }
    
    private func remember(application: NSRunningApplication) {
        guard application.bundleIdentifier != ownBundleIdentifier else { return }
        lastTargetApplication = application
    }
    
    private func targetApplicationForInjection() -> NSRunningApplication? {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != ownBundleIdentifier {
            remember(application: application)
            return application
        }
        return lastTargetApplication
    }
    
    private func activateTargetApplicationIfNeeded(_ application: NSRunningApplication?) {
        guard let application else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier else { return }
        application.activate(options: [.activateIgnoringOtherApps])
    }
    
    private func waitForModifierKeysToRelease(until deadline: Date, completion: @escaping () -> Void) {
        let flags = CGEventSource.flagsState(.hidSystemState)
        let modifierFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        
        if flags.intersection(modifierFlags).isEmpty || Date() >= deadline {
            completion()
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            self.waitForModifierKeysToRelease(until: deadline, completion: completion)
        }
    }
    
    private func restorePasteboard(_ pasteboard: NSPasteboard, with items: [NSPasteboardItem]?) {
        pasteboard.clearContents()
        if let items, !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
    
    private func simulateCmdV() -> Bool {
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        guard let keyDown, let keyUp else { return false }
        
        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    }
}
