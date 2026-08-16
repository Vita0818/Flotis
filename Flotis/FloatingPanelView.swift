import AppKit
import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var hotkeyStore: HotkeyConfigurationStore
    @Environment(\.colorScheme) private var colorScheme

    let voiceController: VoiceInputController
    let onOpenSettings: () -> Void
    let onPreferredSizeChange: (CGSize) -> Void

    @State private var lastReportedPreferredSize: CGSize = .zero

    private var layout: FloatingPanelLayout {
        FloatingPanelLayout(
            state: appState.voiceState,
            hasStatusArea: statusMessage != nil,
            isComparisonReview: appState.isComparisonReview
        )
    }

    var body: some View {
        let layout = layout

        Group {
            if appState.voiceState == .reviewing {
                reviewEditor
            } else {
                compactCapsule
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .onAppear {
            reportPreferredSize(layout.panelSize)
        }
        .onChange(of: layout.panelSize) { newSize in
            reportPreferredSize(newSize)
        }
        .onExitCommand {
            voiceController.cancel()
        }
    }

    private var compactCapsule: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(capsuleIndicatorColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(hotkeyStore.configuration.toggleVoice.displayString)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(FlotisTheme.primary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hotkeyStore.configuration.toggleVoice.displayString)
        .accessibilityValue(capsuleAccessibilityStatus)
        .accessibilityAction(named: Text(UIStrings.settings)) {
            onOpenSettings()
        }
    }

    private var reviewEditor: some View {
        VStack(spacing: 8) {
            if appState.isComparisonReview {
                comparisonResultSelector
            }

            ReviewTextEditor(text: reviewedTranscriptBinding)
                .padding(4)
                .flotisContentSurface(cornerRadius: 12)
                .accessibilityLabel(UIStrings.transcriptPreviewPlaceholder)
                .frame(height: reviewTextEditorHeight)

            HStack(spacing: 8) {
                Button {
                    copyReviewedTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .disabled(appState.transcriptPreview.isEmpty)
                .accessibilityLabel(UIStrings.copyText)
                .help(UIStrings.copyText)

                if let statusMessage {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(statusMessage)
                        .font(FlotisType.caption(11, .regular))
                        .foregroundStyle(FlotisTheme.secondary(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Button {
                    voiceController.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .accessibilityLabel(UIStrings.cancel)
                .help(UIStrings.cancel)

                Button {
                    performPrimaryAction()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderedProminent)
                .flotisCircularButtonBorder()
                .controlSize(.small)
                .accessibilityLabel(UIStrings.copyAndReturn)
                .help(UIStrings.copyAndReturn)
                .disabled(
                    appState.transcriptPreview
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(12)
    }

    private var comparisonResultSelector: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 8)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(appState.transcriptCandidates) { candidate in
                comparisonCandidateButton(candidate)
            }
        }
        .frame(height: comparisonResultSelectorHeight, alignment: .top)
    }

    private func comparisonCandidateButton(
        _ candidate: TranscriptCandidate
    ) -> some View {
        let isSelected = appState.selectedTranscriptCandidateID == candidate.id
        return Button {
            voiceController.selectTranscriptCandidate(id: candidate.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(
                        systemName: candidate.isSuccessful
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .foregroundStyle(candidate.isSuccessful ? Color.green : Color.orange)

                    Text(candidate.primaryDisplayName)
                        .font(
                            candidate.modelDisplayName == nil
                                ? FlotisType.mono(10, .semibold)
                                : FlotisType.body(11, .semibold)
                        )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 2)

                    Text(UIStrings.comparisonElapsed(milliseconds: candidate.elapsedMilliseconds))
                        .font(FlotisType.mono(9, .medium))
                        .foregroundStyle(.secondary)
                }

                if let secondaryDisplayName = candidate.secondaryDisplayName {
                    Text(secondaryDisplayName)
                        .font(FlotisType.body(9, .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Color.secondary.opacity(isSelected ? 0.15 : 0.07),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!candidate.isSuccessful)
        .help(
            candidate.failureMessage
                ?? candidate.accessibilityDisplayName
        )
        .accessibilityLabel(
            candidate.isSuccessful
                ? "\(candidate.accessibilityDisplayName), \(UIStrings.comparisonResultReady)"
                : "\(candidate.accessibilityDisplayName), \(UIStrings.comparisonResultFailed)"
        )
    }

    private var reviewedTranscriptBinding: Binding<String> {
        Binding(
            get: { appState.transcriptPreview },
            set: { appState.updateReviewedTranscript($0) }
        )
    }

    private var comparisonCandidateRowCount: Int {
        max(1, (appState.transcriptCandidates.count + 1) / 2)
    }

    private var comparisonResultSelectorHeight: CGFloat {
        CGFloat(comparisonCandidateRowCount * 50 + (comparisonCandidateRowCount - 1) * 8)
    }

    private var reviewTextEditorHeight: CGFloat {
        guard appState.isComparisonReview else { return 90 }
        return comparisonCandidateRowCount == 1 ? 162 : 112
    }

    private var statusMessage: String? {
        if let pasteError = appState.pasteError {
            return pasteError
        }
        return appState.hotkeyError
    }

    private var capsuleAccessibilityStatus: String {
        if let statusMessage {
            return statusMessage
        }
        return appState.voiceState.displayText
    }

    private var capsuleIndicatorColor: Color {
        if statusMessage != nil {
            return .orange
        }
        switch appState.voiceState {
        case .idle:
            return .green
        case .recording, .streaming:
            return .red
        case .failed:
            return .orange
        case .requestingPermission, .connecting, .stopping, .transcribing:
            return .orange
        case .reviewing, .injecting:
            return .green
        }
    }

    private func reportPreferredSize(_ size: CGSize) {
        guard size != lastReportedPreferredSize else { return }
        lastReportedPreferredSize = size
        onPreferredSizeChange(size)
    }

    private func copyReviewedTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(appState.transcriptPreview, forType: .string) {
            appState.pasteError = nil
        } else {
            appState.pasteError = UIStrings.copyReviewedTranscriptFailed
        }
    }

    private func performPrimaryAction() {
        voiceController.toggleRecording()
    }

}

private final class ReviewNativeTextView: NSTextView {
    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

private struct ReviewTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = ReviewNativeTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }

        let selectedRange = textView.selectedRange()
        textView.string = text
        let safeLocation = min(selectedRange.location, (text as NSString).length)
        let safeLength = min(
            selectedRange.length,
            (text as NSString).length - safeLocation
        )
        textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  text.wrappedValue != textView.string else {
                return
            }
            text.wrappedValue = textView.string
        }
    }
}

struct FloatingPanelLayout: Equatable {
    static let idlePanelWidth: CGFloat = 96
    static let idlePanelHeight: CGFloat = 36
    static let minPanelWidth = idlePanelWidth
    static let minPanelHeight = idlePanelHeight
    static let activePanelWidth = idlePanelWidth
    static let maxPanelWidth: CGFloat = 600
    static let maxPanelHeight: CGFloat = 300
    static let screenCoverage: CGFloat = 0.9
    static let cornerRadius: CGFloat = 18
    static let headerHeight = idlePanelHeight
    static let statusPanelWidth = idlePanelWidth
    static let reviewWidth: CGFloat = 420
    static let reviewHeight: CGFloat = 160
    static let comparisonReviewWidth: CGFloat = 560
    static let comparisonReviewHeight: CGFloat = 300

    let panelSize: CGSize

    init(
        state: VoiceInputState,
        hasStatusArea: Bool,
        isComparisonReview: Bool = false
    ) {
        let isReviewing = state == .reviewing
        let isFailed: Bool
        if case .failed = state {
            isFailed = true
        } else {
            isFailed = false
        }
        let width: CGFloat
        if isReviewing {
            width = isComparisonReview
                ? Self.comparisonReviewWidth
                : Self.reviewWidth
        } else if hasStatusArea || isFailed {
            width = Self.statusPanelWidth
        } else if state == .idle {
            width = Self.idlePanelWidth
        } else {
            width = Self.activePanelWidth
        }
        let height: CGFloat
        if isReviewing {
            height = isComparisonReview
                ? Self.comparisonReviewHeight
                : Self.reviewHeight
        } else if state == .idle, !hasStatusArea {
            height = Self.idlePanelHeight
        } else {
            height = Self.headerHeight
        }
        panelSize = CGSize(width: width, height: height)
    }
}
