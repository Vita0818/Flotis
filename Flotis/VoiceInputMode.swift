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
            return UIStrings.externalProvider
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
    case reviewing
    case injecting
    case failed(String)
}

enum VoiceHotkeyAction: Equatable {
    case start
    case stop
    case cancel
    case copyAndReturn
    case none
}

extension VoiceInputState {
    var hotkeyAction: VoiceHotkeyAction {
        switch self {
        case .idle, .failed:
            return .start
        case .recording, .streaming:
            return .stop
        case .requestingPermission, .connecting:
            return .cancel
        case .stopping, .transcribing:
            return .none
        case .reviewing:
            return .copyAndReturn
        case .injecting:
            return .none
        }
    }

    var displayText: String {
        switch self {
        case .idle:
            return UIStrings.idle
        case .requestingPermission:
            return UIStrings.requestingPermission
        case .connecting:
            return UIStrings.connecting
        case .recording:
            return UIStrings.recording
        case .streaming:
            return UIStrings.realtimeTranscribing
        case .stopping:
            return UIStrings.stopping
        case .transcribing:
            return UIStrings.transcribing
        case .reviewing:
            return UIStrings.reviewing
        case .injecting:
            return UIStrings.injecting
        case .failed(let message):
            return UIStrings.failed(message: message)
        }
    }
}
