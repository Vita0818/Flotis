import Combine
import Foundation

enum TranscriptCandidateNavigationDirection {
    case previous
    case next
}

final class AppState: ObservableObject {
    @Published var hasAccessibilityPermission: Bool = false
    @Published var isPanelVisible: Bool = true
    @Published var pasteError: String? = nil
    @Published var hotkeyError: String? = nil
    
    @Published var voiceMode: VoiceInputMode = .appleSpeech
    @Published var voiceState: VoiceInputState = .idle {
        didSet {
            let wasCapturingAudio = oldValue.isCapturingAudio
            let isCapturingAudio = voiceState.isCapturingAudio
            if isCapturingAudio, !wasCapturingAudio {
                recordingStartedAt = Date()
            } else if !isCapturingAudio, wasCapturingAudio {
                recordingStartedAt = nil
            }
        }
    }
    @Published private(set) var recordingStartedAt: Date?
    @Published var transcriptPreview: String = ""
    @Published private(set) var transcriptCandidates: [TranscriptCandidate] = []
    @Published private(set) var selectedTranscriptCandidateID: UUID?
    @Published var selectedSpeechLocale: String = "zh-CN"

    var isComparisonReview: Bool {
        !transcriptCandidates.isEmpty
    }

    var selectedTranscriptCandidate: TranscriptCandidate? {
        guard let selectedTranscriptCandidateID else { return nil }
        return transcriptCandidates.first { $0.id == selectedTranscriptCandidateID }
    }

    var canNavigateComparisonCandidates: Bool {
        voiceState == .reviewing
            && transcriptCandidates.lazy.filter(\.isSuccessful).prefix(2).count == 2
    }

    func installComparisonCandidates(_ candidates: [TranscriptCandidate]) {
        transcriptCandidates = candidates
        let firstSuccessfulCandidate = candidates.first(where: \.isSuccessful)
        selectedTranscriptCandidateID = firstSuccessfulCandidate?.id
        transcriptPreview = firstSuccessfulCandidate?.text ?? ""
        pasteError = nil
    }

    @discardableResult
    func selectTranscriptCandidate(id: UUID) -> Bool {
        guard let candidate = transcriptCandidates.first(where: {
            $0.id == id && $0.isSuccessful
        }) else {
            return false
        }
        selectedTranscriptCandidateID = candidate.id
        transcriptPreview = candidate.text
        pasteError = nil
        return true
    }

    @discardableResult
    func navigateTranscriptCandidate(
        _ direction: TranscriptCandidateNavigationDirection
    ) -> Bool {
        let successfulCandidates = transcriptCandidates.filter(\.isSuccessful)
        guard !successfulCandidates.isEmpty else { return false }

        let targetIndex: Int
        if let selectedTranscriptCandidateID,
           let selectedIndex = successfulCandidates.firstIndex(where: {
               $0.id == selectedTranscriptCandidateID
           }) {
            switch direction {
            case .previous:
                targetIndex = (selectedIndex - 1 + successfulCandidates.count)
                    % successfulCandidates.count
            case .next:
                targetIndex = (selectedIndex + 1) % successfulCandidates.count
            }
        } else {
            targetIndex = direction == .previous
                ? successfulCandidates.count - 1
                : 0
        }

        return selectTranscriptCandidate(id: successfulCandidates[targetIndex].id)
    }

    func updateReviewedTranscript(_ text: String) {
        transcriptPreview = text
        guard let selectedTranscriptCandidateID,
              let index = transcriptCandidates.firstIndex(where: {
                  $0.id == selectedTranscriptCandidateID
              }) else {
            return
        }
        var updated = transcriptCandidates
        updated[index].text = text
        transcriptCandidates = updated
    }

    func clearComparisonReview() {
        transcriptCandidates = []
        selectedTranscriptCandidateID = nil
    }

    func resetTranscriptReview() {
        transcriptPreview = ""
        clearComparisonReview()
    }
    
    func checkAccessibility() {
        let currentValue = AccessibilityPermission.check()
        if hasAccessibilityPermission != currentValue {
            hasAccessibilityPermission = currentValue
        }
    }
}
