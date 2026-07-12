import AppKit
import CoreGraphics

final class ClipboardPasteInjector {
    static let shared = ClipboardPasteInjector()

    private struct ClipboardSnapshot {
        let items: [NSPasteboardItem]
        let changeCount: Int
    }

    private struct PasteOperation {
        let text: String
        let targetApplication: NSRunningApplication
        let targetProcessIdentifier: pid_t
        let enqueuedAt: TimeInterval
        let completion: (Bool) -> Void
    }

    private struct DeferredCompletion {
        let eventWasPosted: Bool
        let completion: (Bool) -> Void
    }

    private enum Limits {
        static let maximumInFlightOperations = 4
        static let maximumOperationsPerBurst = 8
        static let maximumOperationAge: TimeInterval = 5
    }

    private enum Timing {
        static let activationTimeout: TimeInterval = 1
        static let modifierReleaseTimeout: TimeInterval = 0.8
        static let pollInterval: TimeInterval = 0.03
        static let pasteboardConsumptionDelay: TimeInterval = 0.75
    }

    private let ownBundleIdentifier = Bundle.main.bundleIdentifier
    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    private var lastTargetApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var pendingOperations: [PasteOperation] = []
    private var deferredCompletions: [DeferredCompletion] = []
    private var isProcessingPaste = false
    private var burstOperationCount = 0
    private var burstOriginalClipboard: ClipboardSnapshot?
    private var managedPasteboardChangeCount: Int?
    private var lastPostedTargetProcessIdentifier: pid_t?

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
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self.lastTargetApplication?.processIdentifier == application.processIdentifier else {
                return
            }
            self.lastTargetApplication = nil
        }
    }

    static func shouldAcceptOperation(inFlightCount: Int, burstOperationCount: Int) -> Bool {
        inFlightCount >= 0
            && burstOperationCount >= 0
            && inFlightCount < Limits.maximumInFlightOperations
            && burstOperationCount < Limits.maximumOperationsPerBurst
    }

    static func isOperationExpired(enqueuedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - enqueuedAt > Limits.maximumOperationAge
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func inject(text: String, completion: @escaping (Bool) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.inject(text: text, completion: completion)
            }
            return
        }

        guard AccessibilityPermission.check(),
              let targetApplication = targetApplicationForInjection(),
              isValidTarget(targetApplication) else {
            completion(false)
            return
        }

        let inFlightCount = pendingOperations.count + (isProcessingPaste ? 1 : 0)
        guard Self.shouldAcceptOperation(
            inFlightCount: inFlightCount,
            burstOperationCount: burstOperationCount
        ) else {
            completion(false)
            return
        }

        let pasteboard = NSPasteboard.general
        if let managedPasteboardChangeCount,
           pasteboard.changeCount != managedPasteboardChangeCount {
            completion(false)
            return
        }

        if burstOriginalClipboard == nil {
            guard let snapshot = snapshot(from: pasteboard) else {
                completion(false)
                return
            }
            burstOriginalClipboard = snapshot
            managedPasteboardChangeCount = nil
            lastPostedTargetProcessIdentifier = nil
            burstOperationCount = 0
        }

        burstOperationCount += 1
        pendingOperations.append(
            PasteOperation(
                text: text,
                targetApplication: targetApplication,
                targetProcessIdentifier: targetApplication.processIdentifier,
                enqueuedAt: ProcessInfo.processInfo.systemUptime,
                completion: completion
            )
        )
        processNextOperationIfNeeded()
    }

    private func processNextOperationIfNeeded() {
        guard !isProcessingPaste else { return }

        discardExpiredPendingOperations()
        guard !pendingOperations.isEmpty else {
            completeBurstIfNeeded()
            return
        }

        let operation = pendingOperations.removeFirst()
        guard isOperationFresh(operation), isValidTarget(operation) else {
            deferCompletion(for: operation, eventWasPosted: false)
            processNextOperationIfNeeded()
            return
        }

        let pasteboard = NSPasteboard.general
        guard pasteboardIsUnchangedForCurrentBurst(pasteboard) else {
            abortBurstPreservingExternalClipboard(currentOperation: operation)
            return
        }

        isProcessingPaste = true
        pasteboard.clearContents()
        let didSetText = pasteboard.setString(operation.text, forType: .string)
        managedPasteboardChangeCount = pasteboard.changeCount
        guard didSetText else {
            finish(operation: operation, eventWasPosted: false)
            return
        }

        confirmTargetIsFrontmost(for: operation) { [weak self] targetIsFrontmost in
            guard let self else { return }
            guard targetIsFrontmost else {
                self.finish(operation: operation, eventWasPosted: false)
                return
            }

            self.waitForModifierKeysToRelease(
                until: ProcessInfo.processInfo.systemUptime + Timing.modifierReleaseTimeout
            ) { modifiersWereReleased in
                guard modifiersWereReleased,
                      self.canPostPasteEvent(for: operation) else {
                    self.finish(operation: operation, eventWasPosted: false)
                    return
                }

                let didPostPaste = self.simulateCmdV(expectedTargetProcessIdentifier: operation.targetProcessIdentifier)
                if didPostPaste {
                    self.lastPostedTargetProcessIdentifier = operation.targetProcessIdentifier
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pasteboardConsumptionDelay) {
                    self.finish(operation: operation, eventWasPosted: didPostPaste)
                }
            }
        }
    }

    private func finish(operation: PasteOperation, eventWasPosted: Bool) {
        deferCompletion(for: operation, eventWasPosted: eventWasPosted)
        isProcessingPaste = false

        if pendingOperations.isEmpty {
            completeBurstIfNeeded()
        } else {
            processNextOperationIfNeeded()
        }
    }

    private func deferCompletion(for operation: PasteOperation, eventWasPosted: Bool) {
        deferredCompletions.append(
            DeferredCompletion(
                eventWasPosted: eventWasPosted,
                completion: operation.completion
            )
        )
    }

    private func discardExpiredPendingOperations() {
        let now = ProcessInfo.processInfo.systemUptime
        var retainedOperations: [PasteOperation] = []
        for operation in pendingOperations {
            if Self.isOperationExpired(enqueuedAt: operation.enqueuedAt, now: now) {
                deferCompletion(for: operation, eventWasPosted: false)
            } else {
                retainedOperations.append(operation)
            }
        }
        pendingOperations = retainedOperations
    }

    private func completeBurstIfNeeded() {
        guard !isProcessingPaste,
              pendingOperations.isEmpty,
              burstOriginalClipboard != nil else {
            return
        }

        let pasteboard = NSPasteboard.general
        let clipboardOutcome: Bool
        if pasteboardIsUnchangedForCurrentBurst(pasteboard),
           let snapshot = burstOriginalClipboard {
            clipboardOutcome = restorePasteboard(pasteboard, with: snapshot)
        } else {
            // Another process or the user changed the clipboard. Preserve that newer value.
            clipboardOutcome = true
        }

        let completions = deferredCompletions
        resetBurstState()
        for deferredCompletion in completions {
            deferredCompletion.completion(deferredCompletion.eventWasPosted && clipboardOutcome)
        }
    }

    private func abortBurstPreservingExternalClipboard(currentOperation: PasteOperation) {
        deferCompletion(for: currentOperation, eventWasPosted: false)
        for operation in pendingOperations {
            deferCompletion(for: operation, eventWasPosted: false)
        }
        pendingOperations.removeAll()
        isProcessingPaste = false

        let completions = deferredCompletions
        resetBurstState()
        for deferredCompletion in completions {
            deferredCompletion.completion(deferredCompletion.eventWasPosted)
        }
    }

    private func resetBurstState() {
        pendingOperations.removeAll()
        deferredCompletions.removeAll()
        burstOriginalClipboard = nil
        managedPasteboardChangeCount = nil
        lastPostedTargetProcessIdentifier = nil
        burstOperationCount = 0
        isProcessingPaste = false
    }

    private func rememberFrontmostApplication() {
        if let application = NSWorkspace.shared.frontmostApplication {
            remember(application: application)
        }
    }

    private func remember(application: NSRunningApplication) {
        guard !isOwnApplication(application), !application.isTerminated else { return }
        lastTargetApplication = application
    }

    private func targetApplicationForInjection() -> NSRunningApplication? {
        if let application = NSWorkspace.shared.frontmostApplication,
           !isOwnApplication(application),
           !application.isTerminated {
            remember(application: application)
            return application
        }

        guard let application = lastTargetApplication,
              !application.isTerminated else {
            lastTargetApplication = nil
            return nil
        }
        return application
    }

    private func confirmTargetIsFrontmost(
        for operation: PasteOperation,
        completion: @escaping (Bool) -> Void
    ) {
        guard isValidTarget(operation), isOperationFresh(operation) else {
            completion(false)
            return
        }

        if frontmostProcessIdentifier() == operation.targetProcessIdentifier {
            completion(true)
            return
        }

        guard mayActivateTargetFromCurrentFrontmostApplication(),
              operation.targetApplication.activate(options: [.activateIgnoringOtherApps]) else {
            completion(false)
            return
        }

        waitForTargetToBecomeFrontmost(
            operation,
            until: ProcessInfo.processInfo.systemUptime + Timing.activationTimeout,
            completion: completion
        )
    }

    private func waitForTargetToBecomeFrontmost(
        _ operation: PasteOperation,
        until deadline: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        guard isValidTarget(operation), isOperationFresh(operation) else {
            completion(false)
            return
        }

        if frontmostProcessIdentifier() == operation.targetProcessIdentifier {
            completion(true)
            return
        }

        guard ProcessInfo.processInfo.systemUptime < deadline,
              frontmostApplicationIsAllowedDuringActivation() else {
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pollInterval) {
            self.waitForTargetToBecomeFrontmost(operation, until: deadline, completion: completion)
        }
    }

    private func mayActivateTargetFromCurrentFrontmostApplication() -> Bool {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return false }
        if isCurrentProcess(frontmostApplication) { return true }
        return frontmostApplication.processIdentifier == lastPostedTargetProcessIdentifier
    }

    private func frontmostApplicationIsAllowedDuringActivation() -> Bool {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return true }
        if isCurrentProcess(frontmostApplication) { return true }
        return frontmostApplication.processIdentifier == lastPostedTargetProcessIdentifier
    }

    private func canPostPasteEvent(for operation: PasteOperation) -> Bool {
        guard AccessibilityPermission.check(),
              isOperationFresh(operation),
              isValidTarget(operation),
              frontmostProcessIdentifier() == operation.targetProcessIdentifier,
              let managedPasteboardChangeCount else {
            return false
        }
        return NSPasteboard.general.changeCount == managedPasteboardChangeCount
    }

    private func isValidTarget(_ operation: PasteOperation) -> Bool {
        operation.targetApplication.processIdentifier == operation.targetProcessIdentifier
            && isValidTarget(operation.targetApplication)
    }

    private func isValidTarget(_ application: NSRunningApplication) -> Bool {
        !application.isTerminated && !isOwnApplication(application)
    }

    private func isOwnApplication(_ application: NSRunningApplication) -> Bool {
        if isCurrentProcess(application) { return true }
        guard let ownBundleIdentifier else { return false }
        return application.bundleIdentifier == ownBundleIdentifier
    }

    private func isCurrentProcess(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier == ownProcessIdentifier
    }

    private func isOperationFresh(_ operation: PasteOperation) -> Bool {
        !Self.isOperationExpired(
            enqueuedAt: operation.enqueuedAt,
            now: ProcessInfo.processInfo.systemUptime
        )
    }

    private func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func waitForModifierKeysToRelease(
        until deadline: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let flags = CGEventSource.flagsState(.hidSystemState)
        let modifierFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]

        if flags.intersection(modifierFlags).isEmpty {
            completion(true)
            return
        }

        guard ProcessInfo.processInfo.systemUptime < deadline else {
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pollInterval) {
            self.waitForModifierKeysToRelease(until: deadline, completion: completion)
        }
    }

    private func pasteboardIsUnchangedForCurrentBurst(_ pasteboard: NSPasteboard) -> Bool {
        if let managedPasteboardChangeCount {
            return pasteboard.changeCount == managedPasteboardChangeCount
        }
        guard let snapshot = burstOriginalClipboard else { return true }
        return pasteboard.changeCount == snapshot.changeCount
    }

    private func snapshot(from pasteboard: NSPasteboard) -> ClipboardSnapshot? {
        let initialChangeCount = pasteboard.changeCount
        let sourceItems = pasteboard.pasteboardItems ?? []
        var copiedItems: [NSPasteboardItem] = []
        copiedItems.reserveCapacity(sourceItems.count)

        for item in sourceItems {
            guard !item.types.isEmpty else { return nil }
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type),
                      copy.setData(data, forType: type) else {
                    return nil
                }
            }
            copiedItems.append(copy)
        }

        guard pasteboard.changeCount == initialChangeCount else { return nil }
        return ClipboardSnapshot(items: copiedItems, changeCount: initialChangeCount)
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, with snapshot: ClipboardSnapshot) -> Bool {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return true }
        return pasteboard.writeObjects(snapshot.items)
    }

    private func simulateCmdV(expectedTargetProcessIdentifier: pid_t) -> Bool {
        let vKeyCode: CGKeyCode = 0x09 // 'v'

        guard frontmostProcessIdentifier() == expectedTargetProcessIdentifier,
              let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand

        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    }
}
