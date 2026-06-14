import Foundation

struct CommandStore {
    static let defaultCommands: [PromptCommand] = [
        PromptCommand(id: UUID(), title: "说中文", content: "请使用中文回答。", shortcutIndex: 1),
        PromptCommand(id: UUID(), title: "不改变量名", content: "不要修改现有变量名、函数名、文件名，除非这是修复该问题所必需的。若必须修改，请先说明原因。", shortcutIndex: 2),
        PromptCommand(id: UUID(), title: "遵循指令", content: "请严格遵循我上一条消息中的所有约束，不要自行扩大任务范围。", shortcutIndex: 3),
        PromptCommand(id: UUID(), title: "还是报错", content: "仍然报错。请不要重复上一轮方案，先定位根因，再给出最小修改。", shortcutIndex: 4),
        PromptCommand(id: UUID(), title: "最小修改", content: "只做解决当前问题所需的最小修改，不要顺手重构，不要引入新的抽象。", shortcutIndex: 5),
        PromptCommand(id: UUID(), title: "不要重构", content: "不要进行重构。保持现有结构，只修复当前明确指出的问题。", shortcutIndex: 6),
        PromptCommand(id: UUID(), title: "先定位根因", content: "先定位根因，再给出修改方案。不要直接猜测式修改。", shortcutIndex: 7),
        PromptCommand(id: UUID(), title: "只输出命令", content: "只输出需要执行的命令，不要解释。", shortcutIndex: 8)
    ]
}
