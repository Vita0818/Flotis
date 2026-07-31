import XCTest
@testable import Flotis

final class HotkeyAndInjectionPolicyTests: XCTestCase {
    func testVoiceHotkeyFollowsRecordReviewInjectSequence() {
        XCTAssertEqual(VoiceInputState.idle.hotkeyAction, .start)
        XCTAssertEqual(VoiceInputState.recording.hotkeyAction, .stop)
        XCTAssertEqual(VoiceInputState.streaming.hotkeyAction, .stop)
        XCTAssertEqual(VoiceInputState.reviewing.hotkeyAction, .inject)
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

    func testFloatingPanelUsesTwoStableHeights() {
        XCTAssertEqual(
            FloatingPanelLayout(state: .idle, hasStatusArea: false).panelSize,
            CGSize(width: 120, height: 56)
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
