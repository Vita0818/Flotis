import Foundation

struct PromptCommand: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var isEnabled: Bool
    var sortIndex: Int
    var shortcut: KeyboardShortcutDescriptor?
}

struct KeyboardShortcutDescriptor: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: ShortcutModifiers
}

struct ShortcutModifiers: Codable, Equatable, Hashable {
    var command: Bool
    var option: Bool
    var shift: Bool
    var control: Bool

    var hasAnyModifier: Bool {
        command || option || shift || control
    }

    static let commandOptionShift = ShortcutModifiers(
        command: true,
        option: true,
        shift: true,
        control: false
    )
}

extension KeyboardShortcutDescriptor {
    static let togglePanel = KeyboardShortcutDescriptor(
        keyCode: 29,
        modifiers: .commandOptionShift
    )

    static let toggleVoice = KeyboardShortcutDescriptor(
        keyCode: 15,
        modifiers: .commandOptionShift
    )

    static func defaultNumber(_ number: Int) -> KeyboardShortcutDescriptor? {
        guard let keyCode = KeyCodeDisplay.numberKeyCodes[number] else { return nil }
        return KeyboardShortcutDescriptor(keyCode: keyCode, modifiers: .commandOptionShift)
    }

    var displayString: String {
        "\(modifiers.displayString)\(KeyCodeDisplay.label(for: keyCode))"
    }
}

extension ShortcutModifiers {
    var displayString: String {
        var parts = ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts
    }
}

enum KeyCodeDisplay {
    static let numberKeyCodes: [Int: UInt32] = [
        1: 18,
        2: 19,
        3: 20,
        4: 21,
        5: 23,
        6: 22,
        7: 26,
        8: 28,
        9: 25,
        0: 29
    ]

    private static let labelsByKeyCode: [UInt32: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "↩",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        49: "空格",
        51: "⌫",
        53: "Esc",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]

    static func label(for keyCode: UInt32) -> String {
        labelsByKeyCode[keyCode] ?? "按键 \(keyCode)"
    }
}
