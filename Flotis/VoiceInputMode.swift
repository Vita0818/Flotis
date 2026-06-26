import Foundation

enum VoiceInputMode: String, Codable, CaseIterable, Identifiable {
    case appleSpeech = "appleSpeech"
    case externalProvider = "externalProvider"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return UIStrings.appleSpeech
        case .externalProvider:
            return "外部提供商"
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

extension VoiceInputState {
    var displayText: String {
        switch self {
        case .idle:
            return "空闲"
        case .requestingPermission:
            return UIStrings.requestingPermission
        case .connecting:
            return UIStrings.connecting
        case .recording:
            return "正在录音"
        case .streaming:
            return UIStrings.realtimeTranscribing
        case .stopping:
            return UIStrings.stopping
        case .transcribing:
            return UIStrings.transcribing
        case .injecting:
            return UIStrings.injecting
        case .failed(let message):
            return "\(UIStrings.failed)：\(message)"
        }
    }
}
