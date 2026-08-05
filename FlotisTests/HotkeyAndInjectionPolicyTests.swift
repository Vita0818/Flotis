import XCTest
@testable import Flotis

final class HotkeyAndInjectionPolicyTests: XCTestCase {
    func testVoiceHotkeyFollowsRecordReviewCopyAndReturnSequence() {
        XCTAssertEqual(VoiceInputState.idle.hotkeyAction, .start)
        XCTAssertEqual(VoiceInputState.recording.hotkeyAction, .stop)
        XCTAssertEqual(VoiceInputState.streaming.hotkeyAction, .stop)
        XCTAssertEqual(VoiceInputState.reviewing.hotkeyAction, .copyAndReturn)
    }

    @MainActor
    func testReviewedTranscriptCopySuccessResetsSessionForCapsuleReuse() {
        let appState = AppState()
        appState.voiceState = .reviewing
        appState.transcriptPreview = "  Edited transcript  "
        let clipboardWriter = StubTranscriptClipboardWriter(result: true)
        let controller = VoiceInputController(
            appState: appState,
            transcriptClipboardWriter: clipboardWriter
        )

        controller.toggleRecording()
        XCTAssertEqual(clipboardWriter.writtenTexts, ["  Edited transcript  "])
        XCTAssertEqual(appState.voiceState, .idle)
        XCTAssertEqual(appState.transcriptPreview, "")
        XCTAssertNil(appState.pasteError)
    }

    @MainActor
    func testReviewedTranscriptCopyFailurePreservesReviewForRetry() {
        let appState = AppState()
        appState.voiceState = .reviewing
        appState.transcriptPreview = "Keep this text"
        let clipboardWriter = StubTranscriptClipboardWriter(result: false)
        let controller = VoiceInputController(
            appState: appState,
            transcriptClipboardWriter: clipboardWriter
        )

        controller.toggleRecording()
        XCTAssertEqual(clipboardWriter.writtenTexts, ["Keep this text"])
        XCTAssertEqual(appState.voiceState, .reviewing)
        XCTAssertEqual(appState.transcriptPreview, "Keep this text")
        XCTAssertEqual(appState.pasteError, UIStrings.copyReviewedTranscriptFailed)
    }

    func testVoiceHotkeyCancelsPreparationButIgnoresTerminalProcessing() {
        XCTAssertEqual(VoiceInputState.requestingPermission.hotkeyAction, .cancel)
        XCTAssertEqual(VoiceInputState.connecting.hotkeyAction, .cancel)
        XCTAssertEqual(VoiceInputState.stopping.hotkeyAction, .none)
        XCTAssertEqual(VoiceInputState.transcribing.hotkeyAction, .none)
        XCTAssertEqual(VoiceInputState.injecting.hotkeyAction, .none)
    }

    func testHotkeyPressGateAcceptsOnlyOnePressUntilRelease() {
        var gate = HotKeyPressGate()

        XCTAssertTrue(gate.acceptPress(id: 200))
        XCTAssertFalse(gate.acceptPress(id: 200))
        XCTAssertTrue(gate.acceptPress(id: 100))

        gate.release(id: 200)
        XCTAssertTrue(gate.acceptPress(id: 200))

        gate.reset()
        XCTAssertTrue(gate.acceptPress(id: 100))
    }

    func testGlobalHotkeysUseExclusiveRegistration() {
        XCTAssertNotEqual(HotkeyManager.registrationOptions, 0)
    }

    func testPasteWaitsForModifiersAndVoicePrimaryKeyToRelease() {
        XCTAssertFalse(
            ClipboardPasteInjector.shouldWaitForShortcutRelease(
                modifierKeysAreDown: false,
                primaryKeyIsDown: false
            )
        )
        XCTAssertTrue(
            ClipboardPasteInjector.shouldWaitForShortcutRelease(
                modifierKeysAreDown: true,
                primaryKeyIsDown: false
            )
        )
        XCTAssertTrue(
            ClipboardPasteInjector.shouldWaitForShortcutRelease(
                modifierKeysAreDown: false,
                primaryKeyIsDown: true
            )
        )
    }

    func testExplicitPanelRetryCanReactivateCapturedTarget() {
        XCTAssertTrue(
            ClipboardPasteInjector.shouldAllowCapturedTargetReactivation(
                explicitPanelRequest: true,
                ownsKeyWindow: false
            )
        )
        XCTAssertTrue(
            ClipboardPasteInjector.shouldAllowCapturedTargetReactivation(
                explicitPanelRequest: false,
                ownsKeyWindow: true
            )
        )
        XCTAssertFalse(
            ClipboardPasteInjector.shouldAllowCapturedTargetReactivation(
                explicitPanelRequest: false,
                ownsKeyWindow: false
            )
        )
    }

    func testFloatingPanelUsesStableSizes() {
        XCTAssertEqual(
            FloatingPanelLayout(state: .idle, hasStatusArea: false).panelSize,
            CGSize(width: 108, height: 54)
        )
        XCTAssertEqual(
            FloatingPanelLayout(state: .recording, hasStatusArea: false).panelSize,
            CGSize(width: 188, height: 56)
        )
        XCTAssertEqual(
            FloatingPanelLayout(state: .reviewing, hasStatusArea: false).panelSize,
            CGSize(width: 420, height: 160)
        )
        XCTAssertEqual(
            FloatingPanelLayout(state: .reviewing, hasStatusArea: true).panelSize,
            CGSize(width: 420, height: 160)
        )
    }

    func testPanelResizePreservesDraggedCenterAndBottomEdge() {
        let origin = FloatingPanelController.resizedOrigin(
            currentFrame: NSRect(x: 320, y: 140, width: 108, height: 54),
            targetFrameSize: CGSize(width: 420, height: 160),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin.x, 164, accuracy: 0.001)
        XCTAssertEqual(origin.y, 140, accuracy: 0.001)
    }

    func testPanelResizeClampsDraggedPositionToVisibleScreen() {
        let origin = FloatingPanelController.resizedOrigin(
            currentFrame: NSRect(x: 0, y: 2, width: 108, height: 54),
            targetFrameSize: CGSize(width: 420, height: 160),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(origin.y, 12, accuracy: 0.001)
    }

    func testPanelShrinkRestoresStoredCapsulePositionAfterReviewWasClamped() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let capsuleFrame = NSRect(x: 880, y: 80, width: 108, height: 54)
        let positionAnchor = FloatingPanelPositionAnchor(frame: capsuleFrame)

        let reviewOrigin = FloatingPanelController.resizedOrigin(
            positionAnchor: positionAnchor,
            targetFrameSize: CGSize(width: 420, height: 160),
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(reviewOrigin.x, 568, accuracy: 0.001)

        let restoredOrigin = FloatingPanelController.resizedOrigin(
            positionAnchor: positionAnchor,
            targetFrameSize: capsuleFrame.size,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(restoredOrigin.x, capsuleFrame.origin.x, accuracy: 0.001)
        XCTAssertEqual(restoredOrigin.y, capsuleFrame.origin.y, accuracy: 0.001)
    }

    func testInjectionFailuresProvideSpecificUserMessages() {
        let failures: [PasteInjectionFailure] = [
            .accessibilityPermissionMissing,
            .targetUnavailable,
            .clipboardUnavailable,
            .targetActivationTimedOut,
            .shortcutReleaseTimedOut,
            .clipboardRestoreFailed
        ]

        XCTAssertTrue(failures.allSatisfy { !$0.userMessage.isEmpty })
        XCTAssertNotEqual(
            PasteInjectionFailure.accessibilityPermissionMissing.userMessage,
            PasteInjectionFailure.targetUnavailable.userMessage
        )
    }

    func testPrintableGlobalShortcutRequiresCommandAndAnotherModifier() {
        let shiftA = KeyboardShortcutDescriptor(
            keyCode: 0,
            modifiers: ShortcutModifiers(command: false, option: false, shift: true, control: false)
        )
        let commandA = KeyboardShortcutDescriptor(
            keyCode: 0,
            modifiers: ShortcutModifiers(command: true, option: false, shift: false, control: false)
        )
        let safeA = KeyboardShortcutDescriptor(
            keyCode: 0,
            modifiers: ShortcutModifiers(command: true, option: true, shift: false, control: false)
        )

        XCTAssertNotNil(CommandStore.shortcutSafetyError(shiftA))
        XCTAssertNotNil(CommandStore.shortcutSafetyError(commandA))
        XCTAssertNil(CommandStore.shortcutSafetyError(safeA))
    }

    func testPasteAndCommonApplicationShortcutsAreRejected() {
        for keyCode in [UInt32(9), 8, 12] { // V, C, Q
            let shortcut = KeyboardShortcutDescriptor(
                keyCode: keyCode,
                modifiers: ShortcutModifiers(command: true, option: false, shift: false, control: false)
            )
            XCTAssertNotNil(CommandStore.shortcutSafetyError(shortcut))
        }
    }

    func testDefaultThreeModifierShortcutRemainsValid() {
        let shortcut = KeyboardShortcutDescriptor(
            keyCode: 18,
            modifiers: .commandOptionShift
        )
        XCTAssertNil(CommandStore.shortcutSafetyError(shortcut))
    }

    func testVoiceShortcutUsesControlOptionA() {
        XCTAssertEqual(KeyboardShortcutDescriptor.toggleVoice.keyCode, 0)
        XCTAssertEqual(KeyboardShortcutDescriptor.toggleVoice.modifiers, .controlOption)
        XCTAssertEqual(KeyboardShortcutDescriptor.toggleVoice.displayString, "⌃⌥A")
    }

    func testPasteQueueCapacityIsBounded() {
        XCTAssertTrue(
            ClipboardPasteInjector.shouldAcceptOperation(inFlightCount: 3, burstOperationCount: 7)
        )
        XCTAssertFalse(
            ClipboardPasteInjector.shouldAcceptOperation(inFlightCount: 4, burstOperationCount: 0)
        )
        XCTAssertFalse(
            ClipboardPasteInjector.shouldAcceptOperation(inFlightCount: 0, burstOperationCount: 8)
        )
    }

    func testPasteOperationExpirationUsesMonotonicAge() {
        XCTAssertFalse(ClipboardPasteInjector.isOperationExpired(enqueuedAt: 100, now: 105))
        XCTAssertTrue(ClipboardPasteInjector.isOperationExpired(enqueuedAt: 100, now: 105.001))
    }
}

private final class StubTranscriptClipboardWriter: TranscriptClipboardWriting {
    private let result: Bool
    private(set) var writtenTexts: [String] = []

    init(result: Bool) {
        self.result = result
    }

    func writeTranscript(_ text: String) -> Bool {
        writtenTexts.append(text)
        return result
    }
}
