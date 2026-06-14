import Foundation

struct PromptCommand: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var shortcutIndex: Int?
}
