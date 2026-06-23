import Foundation

enum VoiceInputMode: String, Codable, CaseIterable, Identifiable {
    case appleSpeech = "appleSpeech"
    case externalProvider = "externalProvider"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .externalProvider:
            return "External Provider"
        }
    }
}

enum VoiceInputState: Equatable {
    case idle
    case requestingPermission
    case connecting
    case recording
    case streaming
    case stopping
    case transcribing
    case injecting
    case failed(String)
}
