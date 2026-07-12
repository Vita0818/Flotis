import XCTest
@testable import Flotis

final class HotkeyAndInjectionPolicyTests: XCTestCase {
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
