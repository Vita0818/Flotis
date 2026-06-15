import Combine
import Foundation

final class AppState: ObservableObject {
    @Published var hasAccessibilityPermission: Bool = false
    @Published var isPanelVisible: Bool = true
    @Published var pasteError: String? = nil
    
    @Published var voiceMode: VoiceInputMode = .appleSpeech
    @Published var voiceState: VoiceInputState = .idle
    @Published var transcriptPreview: String = ""
    @Published var selectedSpeechLocale: String = "zh-CN"
    
    func checkAccessibility() {
        self.hasAccessibilityPermission = AccessibilityPermission.check()
    }
}
