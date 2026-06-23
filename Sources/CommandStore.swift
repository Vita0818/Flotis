import Foundation

final class CommandStore: ObservableObject {
    static let shared = CommandStore()

    @Published private(set) var commands: [PromptCommand] = []
    @Published var lastError: String?

    var onCommandsChanged: (([PromptCommand]) -> Void)?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let defaultCommands: [PromptCommand] = [
        PromptCommand(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, title: "说中文", content: "请使用中文回答。", isEnabled: true, sortIndex: 0, shortcut: .defaultNumber(1)),
        PromptCommand(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, title: "不改变量名", content: "不要修改现有变量名、函数名、文件名，除非这是修复该问题所必需的。若必须修改，请先说明原因。", isEnabled: true, sortIndex: 1, shortcut: .defaultNumber(2)),
        PromptCommand(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, title: "遵循指令", content: "请严格遵循我上一条消息中的所有约束，不要自行扩大任务范围。", isEnabled: true, sortIndex: 2, shortcut: .defaultNumber(3)),
        PromptCommand(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, title: "还是报错", content: "仍然报错。请不要重复上一轮方案，先定位根因，再给出最小修改。", isEnabled: true, sortIndex: 3, shortcut: .defaultNumber(4)),
        PromptCommand(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, title: "最小修改", content: "只做解决当前问题所需的最小修改，不要顺手重构，不要引入新的抽象。", isEnabled: true, sortIndex: 4, shortcut: .defaultNumber(5)),
        PromptCommand(id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!, title: "不要重构", content: "不要进行重构。保持现有结构，只修复当前明确指出的问题。", isEnabled: true, sortIndex: 5, shortcut: .defaultNumber(6)),
        PromptCommand(id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!, title: "先定位根因", content: "先定位根因，再给出修改方案。不要直接猜测式修改。", isEnabled: true, sortIndex: 6, shortcut: .defaultNumber(7)),
        PromptCommand(id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!, title: "只输出命令", content: "只输出需要执行的命令，不要解释。", isEnabled: true, sortIndex: 7, shortcut: .defaultNumber(8))
    ]

    private init(fileURL: URL? = nil) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.fileURL = fileURL ?? Self.defaultCommandsFileURL()
        load()
    }

    static func defaultCommandsFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Flotis", isDirectory: true)
            .appendingPathComponent("commands.json")
    }

    var enabledCommands: [PromptCommand] {
        commands
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.sortIndex == rhs.sortIndex {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    func command(with id: UUID) -> PromptCommand? {
        commands.first { $0.id == id }
    }

    func load() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                let decoded = try decoder.decode([PromptCommand].self, from: data)
                commands = normalized(decoded)
            } else {
                commands = Self.defaultCommands
                try saveToDisk()
            }
            publishChange()
        } catch {
            commands = Self.defaultCommands
            lastError = "命令配置读取失败，已使用默认配置。"
            publishChange()
        }
    }

    func resetToDefaults() {
        commands = Self.defaultCommands
        persistAndPublish()
    }

    func addCommand() {
        let nextIndex = (commands.map(\.sortIndex).max() ?? -1) + 1
        let command = PromptCommand(
            id: UUID(),
            title: "新命令",
            content: "",
            isEnabled: true,
            sortIndex: nextIndex,
            shortcut: nil
        )
        commands.append(command)
        persistAndPublish()
    }

    func updateCommand(_ command: PromptCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        commands = normalized(commands)
        persistAndPublish()
    }

    func deleteCommand(id: UUID) {
        commands.removeAll { $0.id == id }
        commands = normalized(commands)
        persistAndPublish()
    }

    func moveCommand(id: UUID, direction: Int) {
        let sorted = commands.sorted { $0.sortIndex < $1.sortIndex }
        guard let currentIndex = sorted.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = currentIndex + direction
        guard sorted.indices.contains(targetIndex) else { return }

        var reordered = sorted
        reordered.swapAt(currentIndex, targetIndex)
        commands = normalized(reordered)
        persistAndPublish()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard var command = command(with: id) else { return }
        command.isEnabled = isEnabled
        updateCommand(command)
    }

    func setShortcut(_ shortcut: KeyboardShortcutDescriptor?, for id: UUID) -> Bool {
        guard var command = command(with: id) else { return false }
        if let shortcut {
            guard validateShortcut(shortcut, for: id) == nil else { return false }
        }
        command.shortcut = shortcut
        updateCommand(command)
        return true
    }

    func validateShortcut(_ shortcut: KeyboardShortcutDescriptor, for commandID: UUID?) -> String? {
        guard shortcut.modifiers.hasAnyModifier else {
            return "快捷键至少需要一个修饰键。"
        }

        if shortcut == .togglePanel {
            return "该快捷键已用于显示/隐藏浮窗。"
        }

        if shortcut == .toggleVoice {
            return "该快捷键已用于语音输入。"
        }

        if let conflicting = commands.first(where: { command in
            command.id != commandID && command.shortcut == shortcut
        }) {
            return "快捷键已被“\(conflicting.title)”使用。"
        }

        return nil
    }

    private func normalized(_ commands: [PromptCommand]) -> [PromptCommand] {
        commands
            .sorted { lhs, rhs in
                if lhs.sortIndex == rhs.sortIndex {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.sortIndex < rhs.sortIndex
            }
            .enumerated()
            .map { index, command in
                var updated = command
                updated.sortIndex = index
                return updated
            }
    }

    private func persistAndPublish() {
        do {
            try saveToDisk()
            lastError = nil
        } catch {
            lastError = "命令配置保存失败。"
        }
        publishChange()
    }

    private func saveToDisk() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(normalized(commands))
        try data.write(to: fileURL, options: [.atomic])
    }

    private func publishChange() {
        onCommandsChanged?(commands)
    }
}
