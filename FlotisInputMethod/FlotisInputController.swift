import AppKit
import InputMethodKit

/// One controller is created by InputMethodKit for each active text-input client.
/// Normal keyboard events are left untouched; this controller only commits text when
/// the explicit Flotis interface is invoked.
@objc(FlotisInputController)
@MainActor
final class FlotisInputController: IMKInputController, FlotisInputMethodClientEndpoint {
    private var activeSessionID: UUID?

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        detachFromService()
        activeSessionID = FlotisInputMethodService.shared.activate(endpoint: self)
    }

    override func deactivateServer(_ sender: Any!) {
        detachFromService()
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        detachFromService()
        super.inputControllerWillClose()
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        // Returning false lets the client handle ordinary typing unchanged.
        false
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: InterfaceCopy.menuTitle)
        let item = NSMenuItem(
            title: InterfaceCopy.insertTestText,
            action: #selector(insertInterfaceTestText(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    func insertCommittedText(_ text: String) -> Bool {
        guard let client = client() else {
            return false
        }

        client.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        return true
    }

    @objc
    private func insertInterfaceTestText(_ sender: Any?) {
        guard let activeSessionID else {
            return
        }

        let request = FlotisInputMethodCommitRequest(
            sessionID: activeSessionID,
            text: InterfaceCopy.testText
        )
        _ = FlotisInputMethodService.shared.submit(request)
    }

    private func detachFromService() {
        guard let activeSessionID else {
            return
        }

        FlotisInputMethodService.shared.deactivate(
            endpoint: self,
            sessionID: activeSessionID
        )
        self.activeSessionID = nil
    }
}

private enum InterfaceCopy {
    static var menuTitle: String {
        isSimplifiedChinese ? "Flotis 输入法" : "Flotis Input Method"
    }

    static var insertTestText: String {
        isSimplifiedChinese ? "插入接口测试文本" : "Insert Interface Test Text"
    }

    static var testText: String {
        isSimplifiedChinese ? "Flotis 输入法接口已连接。" : "Flotis input method interface is connected."
    }

    private static var isSimplifiedChinese: Bool {
        guard let language = Locale.preferredLanguages.first?.lowercased() else {
            return false
        }

        return language == "zh-hans"
            || language.hasPrefix("zh-hans-")
            || language == "zh-cn"
            || language.hasPrefix("zh-cn-")
            || language == "zh-sg"
            || language.hasPrefix("zh-sg-")
            || language == "zh-my"
            || language.hasPrefix("zh-my-")
    }
}
