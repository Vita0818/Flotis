import AppKit
import CoreGraphics

final class ClipboardPasteInjector {
    static let shared = ClipboardPasteInjector()
    
    private struct ClipboardSnapshot {
        let items: [NSPasteboardItem]
    }
    
    private struct PasteOperation {
        let generation: UInt64
        let text: String
        let targetApplication: NSRunningApplication?
        let completion: (Bool) -> Void
    }
    
    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    private var lastTargetApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var generation: UInt64 = 0
    private var pendingOperations: [PasteOperation] = []
    private var isProcessingPaste = false
    private var pendingRestoreWorkItem: DispatchWorkItem?
    private var burstOriginalClipboard: ClipboardSnapshot?
    
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
        
        let pasteboard = NSPasteboard.general
        pendingRestoreWorkItem?.cancel()
        pendingRestoreWorkItem = nil
        
        if burstOriginalClipboard == nil {
            burstOriginalClipboard = snapshot(from: pasteboard)
        }
        
        generation &+= 1
        let operation = PasteOperation(
            generation: generation,
            text: text,
            targetApplication: targetApplicationForInjection(),
            completion: completion
        )
        pendingOperations.append(operation)
        processNextOperationIfNeeded()
    }
    
    private func processNextOperationIfNeeded() {
        guard !isProcessingPaste, !pendingOperations.isEmpty else { return }
        
        isProcessingPaste = true
        let operation = pendingOperations.removeFirst()
        let pasteboard = NSPasteboard.general
        
        pasteboard.clearContents()
        guard pasteboard.setString(operation.text, forType: .string) else {
            finish(operation: operation, success: false)
            return
        }
        
        activateTargetApplicationIfNeeded(operation.targetApplication)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForModifierKeysToRelease(until: Date().addingTimeInterval(0.8)) {
                let didPostPaste = self.simulateCmdV()
            
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.finish(operation: operation, success: didPostPaste)
                }
            }
        }
    }
    
    private func finish(operation: PasteOperation, success: Bool) {
        operation.completion(success)
        isProcessingPaste = false
        
        if pendingOperations.isEmpty {
            scheduleRestoreIfCurrent(operationGeneration: operation.generation)
        }
        
        processNextOperationIfNeeded()
    }
    
    private func scheduleRestoreIfCurrent(operationGeneration: UInt64) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.generation == operationGeneration,
                  !self.isProcessingPaste,
                  self.pendingOperations.isEmpty,
                  let snapshot = self.burstOriginalClipboard else {
                return
            }
            
            self.restorePasteboard(NSPasteboard.general, with: snapshot)
            self.burstOriginalClipboard = nil
            self.pendingRestoreWorkItem = nil
        }
        
        pendingRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
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
    
    private func snapshot(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
        return ClipboardSnapshot(items: items)
    }
    
    private func restorePasteboard(_ pasteboard: NSPasteboard, with snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        if !snapshot.items.isEmpty {
            pasteboard.writeObjects(snapshot.items)
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
