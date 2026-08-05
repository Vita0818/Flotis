import AppKit
import CoreGraphics

enum PasteInjectionFailure: Error, Equatable {
    case accessibilityPermissionMissing
    case targetUnavailable
    case queueBusy
    case clipboardUnavailable
    case clipboardChanged
    case clipboardWriteFailed
    case targetActivationFailed
    case targetActivationTimedOut
    case shortcutReleaseTimedOut
    case operationExpired
    case eventCreationFailed
    case clipboardRestoreFailed

    var userMessage: String {
        switch self {
        case .accessibilityPermissionMissing:
            return UIStrings.injectionAccessibilityMissing
        case .targetUnavailable:
            return UIStrings.injectionTargetUnavailable
        case .queueBusy:
            return UIStrings.injectionBusy
        case .clipboardUnavailable:
            return UIStrings.injectionClipboardUnavailable
        case .clipboardChanged:
            return UIStrings.injectionClipboardChanged
        case .clipboardWriteFailed:
            return UIStrings.injectionClipboardWriteFailed
        case .targetActivationFailed, .targetActivationTimedOut:
            return UIStrings.injectionTargetActivationFailed
        case .shortcutReleaseTimedOut:
            return UIStrings.injectionShortcutReleaseTimedOut
        case .operationExpired:
            return UIStrings.injectionOperationExpired
        case .eventCreationFailed:
            return UIStrings.injectionEventFailed
        case .clipboardRestoreFailed:
            return UIStrings.injectionClipboardRestoreFailed
        }
    }
}

enum PasteInjectionResult: Equatable {
    case succeeded
    case failed(PasteInjectionFailure)
}

struct PasteInjectionTarget {
    fileprivate let application: NSRunningApplication
    let processIdentifier: pid_t
}

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
        let allowsTargetReactivation: Bool
        let activationSourceProcessIdentifier: pid_t?
        let enqueuedAt: TimeInterval
        let completion: (PasteInjectionResult) -> Void
    }

    private struct DeferredCompletion {
        let eventWasPosted: Bool
        let failure: PasteInjectionFailure?
        let completion: (PasteInjectionResult) -> Void
    }

    private enum Limits {
        static let maximumInFlightOperations = 4
        static let maximumOperationsPerBurst = 8
        static let maximumOperationAge: TimeInterval = 5
    }

    private enum Timing {
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

    static func shouldWaitForShortcutRelease(
        modifierKeysAreDown: Bool,
        primaryKeyIsDown: Bool
    ) -> Bool {
        modifierKeysAreDown || primaryKeyIsDown
    }

    static func shouldAllowCapturedTargetReactivation(
        explicitPanelRequest: Bool,
        ownsKeyWindow: Bool
    ) -> Bool {
        explicitPanelRequest || ownsKeyWindow
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func captureTarget() -> PasteInjectionTarget? {
        guard Thread.isMainThread,
              let application = targetApplicationForInjection(),
              isValidTarget(application) else {
            return nil
        }
        return PasteInjectionTarget(
            application: application,
            processIdentifier: application.processIdentifier
        )
    }

    func inject(
        text: String,
        target: PasteInjectionTarget?,
        allowsTargetReactivation: Bool,
        completion: @escaping (PasteInjectionResult) -> Void
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.inject(
                    text: text,
                    target: target,
                    allowsTargetReactivation: allowsTargetReactivation,
                    completion: completion
                )
            }
            return
        }

        guard AccessibilityPermission.check() else {
            completion(.failed(.accessibilityPermissionMissing))
            return
        }

        guard let target else {
            completion(.failed(.targetUnavailable))
            return
        }
        let targetApplication = target.application
        guard isValidTarget(targetApplication),
              target.processIdentifier == targetApplication.processIdentifier else {
            completion(.failed(.targetUnavailable))
            return
        }

        let inFlightCount = pendingOperations.count + (isProcessingPaste ? 1 : 0)
        guard Self.shouldAcceptOperation(
            inFlightCount: inFlightCount,
            burstOperationCount: burstOperationCount
        ) else {
            completion(.failed(.queueBusy))
            return
        }

        let pasteboard = NSPasteboard.general
        if let managedPasteboardChangeCount,
           pasteboard.changeCount != managedPasteboardChangeCount {
            completion(.failed(.clipboardChanged))
            return
        }

        if burstOriginalClipboard == nil {
            guard let snapshot = snapshot(from: pasteboard) else {
                completion(.failed(.clipboardUnavailable))
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
                allowsTargetReactivation: Self.shouldAllowCapturedTargetReactivation(
                    explicitPanelRequest: allowsTargetReactivation,
                    ownsKeyWindow: NSApp.keyWindow?.isKeyWindow == true
                ),
                activationSourceProcessIdentifier: frontmostProcessIdentifier(),
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
        guard isOperationFresh(operation) else {
            deferCompletion(
                for: operation,
                eventWasPosted: false,
                failure: .operationExpired
            )
            processNextOperationIfNeeded()
            return
        }
        guard isValidTarget(operation) else {
            deferCompletion(
                for: operation,
                eventWasPosted: false,
                failure: .targetUnavailable
            )
            processNextOperationIfNeeded()
            return
        }

        let pasteboard = NSPasteboard.general
        guard pasteboardIsUnchangedForCurrentBurst(pasteboard) else {
            abortBurstPreservingExternalClipboard(
                currentOperation: operation,
                failure: .clipboardChanged
            )
            return
        }

        isProcessingPaste = true
        pasteboard.clearContents()
        let didSetText = pasteboard.setString(operation.text, forType: .string)
        managedPasteboardChangeCount = pasteboard.changeCount
        guard didSetText else {
            finish(
                operation: operation,
                eventWasPosted: false,
                failure: .clipboardWriteFailed
            )
            return
        }

        confirmTargetIsFrontmost(for: operation) { [weak self] activationResult in
            guard let self else { return }
            if case .failure(let failure) = activationResult {
                self.finish(
                    operation: operation,
                    eventWasPosted: false,
                    failure: failure
                )
                return
            }

            // A Carbon hotkey is delivered before its modifiers and primary key are
            // necessarily released. Give the full chord the remainder of this
            // already-bounded operation lifetime to release.
            self.waitForVoiceShortcutToRelease(
                until: operation.enqueuedAt + Limits.maximumOperationAge
            ) { modifiersWereReleased in
                guard modifiersWereReleased else {
                    self.finish(
                        operation: operation,
                        eventWasPosted: false,
                        failure: .shortcutReleaseTimedOut
                    )
                    return
                }
                if let failure = self.postValidationFailure(for: operation) {
                    self.finish(
                        operation: operation,
                        eventWasPosted: false,
                        failure: failure
                    )
                    return
                }

                let didPostPaste = self.simulateCmdV(expectedTargetProcessIdentifier: operation.targetProcessIdentifier)
                if didPostPaste {
                    self.lastPostedTargetProcessIdentifier = operation.targetProcessIdentifier
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pasteboardConsumptionDelay) {
                    self.finish(
                        operation: operation,
                        eventWasPosted: didPostPaste,
                        failure: didPostPaste ? nil : .eventCreationFailed
                    )
                }
            }
        }
    }

    private func finish(
        operation: PasteOperation,
        eventWasPosted: Bool,
        failure: PasteInjectionFailure?
    ) {
        deferCompletion(
            for: operation,
            eventWasPosted: eventWasPosted,
            failure: failure
        )
        isProcessingPaste = false

        if pendingOperations.isEmpty {
            completeBurstIfNeeded()
        } else {
            processNextOperationIfNeeded()
        }
    }

    private func deferCompletion(
        for operation: PasteOperation,
        eventWasPosted: Bool,
        failure: PasteInjectionFailure?
    ) {
        deferredCompletions.append(
            DeferredCompletion(
                eventWasPosted: eventWasPosted,
                failure: failure,
                completion: operation.completion
            )
        )
    }

    private func discardExpiredPendingOperations() {
        let now = ProcessInfo.processInfo.systemUptime
        var retainedOperations: [PasteOperation] = []
        for operation in pendingOperations {
            if Self.isOperationExpired(enqueuedAt: operation.enqueuedAt, now: now) {
                deferCompletion(
                    for: operation,
                    eventWasPosted: false,
                    failure: .operationExpired
                )
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
            if deferredCompletion.eventWasPosted && clipboardOutcome {
                deferredCompletion.completion(.succeeded)
            } else {
                deferredCompletion.completion(
                    .failed(
                        deferredCompletion.failure
                            ?? (clipboardOutcome ? .eventCreationFailed : .clipboardRestoreFailed)
                    )
                )
            }
        }
    }

    private func abortBurstPreservingExternalClipboard(
        currentOperation: PasteOperation,
        failure: PasteInjectionFailure
    ) {
        deferCompletion(
            for: currentOperation,
            eventWasPosted: false,
            failure: failure
        )
        for operation in pendingOperations {
            deferCompletion(
                for: operation,
                eventWasPosted: false,
                failure: failure
            )
        }
        pendingOperations.removeAll()
        isProcessingPaste = false

        let completions = deferredCompletions
        resetBurstState()
        for deferredCompletion in completions {
            if deferredCompletion.eventWasPosted {
                deferredCompletion.completion(.succeeded)
            } else {
                deferredCompletion.completion(
                    .failed(deferredCompletion.failure ?? failure)
                )
            }
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
        completion: @escaping (Result<Void, PasteInjectionFailure>) -> Void
    ) {
        guard isValidTarget(operation) else {
            completion(.failure(.targetUnavailable))
            return
        }
        guard isOperationFresh(operation) else {
            completion(.failure(.operationExpired))
            return
        }

        if targetIsReadyForPaste(
            processIdentifier: operation.targetProcessIdentifier
        ) {
            completion(.success(()))
            return
        }

        resignOwnKeyWindowIfNeeded()
        guard mayActivateTargetFromCurrentFrontmostApplication(for: operation) else {
            completion(.failure(.targetUnavailable))
            return
        }
        guard operation.targetApplication.activate(options: [.activateIgnoringOtherApps]) else {
            completion(.failure(.targetActivationFailed))
            return
        }

        waitForTargetToBecomeFrontmost(
            operation,
            until: operation.enqueuedAt + Limits.maximumOperationAge,
            completion: completion
        )
    }

    private func waitForTargetToBecomeFrontmost(
        _ operation: PasteOperation,
        until deadline: TimeInterval,
        completion: @escaping (Result<Void, PasteInjectionFailure>) -> Void
    ) {
        guard isValidTarget(operation) else {
            completion(.failure(.targetUnavailable))
            return
        }

        if targetIsReadyForPaste(
            processIdentifier: operation.targetProcessIdentifier
        ) {
            completion(.success(()))
            return
        }

        guard ProcessInfo.processInfo.systemUptime < deadline else {
            completion(.failure(.targetActivationTimedOut))
            return
        }
        guard frontmostApplicationIsAllowedDuringActivation(
            for: operation
        ) else {
            completion(.failure(.targetUnavailable))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pollInterval) {
            self.waitForTargetToBecomeFrontmost(operation, until: deadline, completion: completion)
        }
    }

    private func mayActivateTargetFromCurrentFrontmostApplication(
        for operation: PasteOperation
    ) -> Bool {
        if operation.allowsTargetReactivation { return true }
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return false }
        if isCurrentProcess(frontmostApplication) { return true }
        if frontmostApplication.processIdentifier == operation.targetProcessIdentifier {
            return true
        }
        return frontmostApplication.processIdentifier == lastPostedTargetProcessIdentifier
    }

    private func frontmostApplicationIsAllowedDuringActivation(
        for operation: PasteOperation
    ) -> Bool {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return true }
        if isCurrentProcess(frontmostApplication) { return true }
        if frontmostApplication.processIdentifier == operation.targetProcessIdentifier {
            return true
        }
        if operation.allowsTargetReactivation,
           frontmostApplication.processIdentifier == operation.activationSourceProcessIdentifier {
            return true
        }
        return frontmostApplication.processIdentifier == lastPostedTargetProcessIdentifier
    }

    private func postValidationFailure(
        for operation: PasteOperation
    ) -> PasteInjectionFailure? {
        guard AccessibilityPermission.check() else {
            return .accessibilityPermissionMissing
        }
        guard isOperationFresh(operation) else {
            return .operationExpired
        }
        guard isValidTarget(operation) else {
            return .targetUnavailable
        }
        guard targetIsReadyForPaste(
            processIdentifier: operation.targetProcessIdentifier
        ) else {
            return .targetActivationFailed
        }
        guard let managedPasteboardChangeCount,
              NSPasteboard.general.changeCount == managedPasteboardChangeCount else {
            return .clipboardChanged
        }
        return nil
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

    private func targetIsReadyForPaste(processIdentifier: pid_t) -> Bool {
        frontmostProcessIdentifier() == processIdentifier
            && NSApp.keyWindow?.isKeyWindow != true
    }

    private func resignOwnKeyWindowIfNeeded() {
        if let keyWindow = NSApp.keyWindow, keyWindow.isKeyWindow {
            keyWindow.makeFirstResponder(nil)
            keyWindow.resignKey()
        }
        if NSApp.isActive {
            NSApp.deactivate()
        }
    }

    private func waitForVoiceShortcutToRelease(
        until deadline: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let flags = CGEventSource.flagsState(.hidSystemState)
        let modifierFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let modifierKeysAreDown = !flags.intersection(modifierFlags).isEmpty
        let primaryKeyIsDown = CGEventSource.keyState(
            .hidSystemState,
            key: CGKeyCode(KeyboardShortcutDescriptor.toggleVoice.keyCode)
        )

        if !Self.shouldWaitForShortcutRelease(
            modifierKeysAreDown: modifierKeysAreDown,
            primaryKeyIsDown: primaryKeyIsDown
        ) {
            completion(true)
            return
        }

        guard ProcessInfo.processInfo.systemUptime < deadline else {
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pollInterval) {
            self.waitForVoiceShortcutToRelease(until: deadline, completion: completion)
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

        // Deliver only to the already-verified target PID. This avoids a global
        // event-stream race if another app becomes frontmost between validation
        // and the two event posts.
        keyDown.postToPid(expectedTargetProcessIdentifier)
        keyUp.postToPid(expectedTargetProcessIdentifier)
        return true
    }
}
