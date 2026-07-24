import AppKit
import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var providerStore: SpeechProviderStore
    let voiceController: VoiceInputController
    let onPreferredSizeChange: (CGSize) -> Void

    @State private var showingSettings = false
    @State private var lastReportedPreferredSize: CGSize = .zero

    private var layout: FloatingPanelLayout {
        FloatingPanelLayout(
            state: appState.voiceState,
            hasStatusArea: statusMessage != nil
        )
    }

    var body: some View {
        let layout = layout

        VStack(spacing: 0) {
            capsuleHeader
                .padding(.horizontal, 12)
                .frame(height: FloatingPanelLayout.headerHeight)

            if appState.voiceState == .reviewing {
                reviewEditor
            }

            if let statusMessage {
                statusArea(message: statusMessage)
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                appState: appState,
                providerStore: providerStore,
                closeMode: .back,
                onClose: {
                    showingSettings = false
                }
            )
        }
        .onAppear {
            appState.checkAccessibility()
            reportPreferredSize(layout.panelSize)
        }
        .onChange(of: layout.panelSize) { newSize in
            reportPreferredSize(newSize)
        }
        .onExitCommand {
            voiceController.cancel()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            appState.checkAccessibility()
        }
    }

    private var capsuleHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 32, height: 32)

                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(statusDetail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(UIStrings.settings)

            Button {
                voiceController.toggleRecording()
            } label: {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(actionColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(appState.voiceState == .injecting)
            .help(actionHelp)
        }
    }

    private var reviewEditor: some View {
        VStack(spacing: 8) {
            Divider()

            TextEditor(text: $appState.transcriptPreview)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(height: 72)

            HStack(spacing: 8) {
                Button(UIStrings.cancel) {
                    voiceController.cancel()
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("\(KeyboardShortcutDescriptor.toggleVoice.displayString) 再按输入")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Button(UIStrings.insertText) {
                    voiceController.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    appState.transcriptPreview
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func statusArea(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer(minLength: 4)

            if !appState.hasAccessibilityPermission {
                Button(UIStrings.openSettings) {
                    AccessibilityPermission.openSettings()
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: FloatingPanelLayout.statusAreaHeight)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusMessage: String? {
        if !appState.hasAccessibilityPermission {
            return UIStrings.accessibilityPastePermission
        }
        return appState.pasteError ?? appState.hotkeyError ?? providerStore.lastError
    }

    private var statusTitle: String {
        switch appState.voiceState {
        case .idle:
            return "Flotis"
        case .requestingPermission:
            return UIStrings.requestingPermission
        case .connecting:
            return UIStrings.connecting
        case .recording, .streaming:
            return UIStrings.recording
        case .stopping:
            return UIStrings.stopping
        case .transcribing:
            return UIStrings.transcribing
        case .reviewing:
            return UIStrings.reviewTranscript
        case .injecting:
            return UIStrings.injecting
        case .failed:
            return UIStrings.failed
        }
    }

    private var statusDetail: String {
        if case .failed(let message) = appState.voiceState {
            return message
        }

        switch appState.voiceState {
        case .idle:
            return "按 \(KeyboardShortcutDescriptor.toggleVoice.displayString) 开始录音"
        case .recording, .streaming:
            if !appState.transcriptPreview.isEmpty,
               appState.transcriptPreview != UIStrings.dictating {
                return appState.transcriptPreview
            }
            return "再按 \(KeyboardShortcutDescriptor.toggleVoice.displayString) 停止"
        case .reviewing:
            return UIStrings.reviewThenInsert
        case .requestingPermission, .connecting, .stopping, .transcribing:
            return UIStrings.hotkeyCancelsCurrentOperation
        case .injecting:
            return UIStrings.verifyingTarget
        case .failed:
            return UIStrings.retry
        }
    }

    private var statusIcon: String {
        switch appState.voiceState {
        case .idle:
            return "mic.fill"
        case .recording, .streaming:
            return "waveform"
        case .reviewing:
            return "text.cursor"
        case .failed:
            return "exclamationmark"
        case .injecting:
            return "arrow.up.forward"
        case .requestingPermission, .connecting, .stopping, .transcribing:
            return "ellipsis"
        }
    }

    private var statusColor: Color {
        switch appState.voiceState {
        case .recording, .streaming:
            return .red
        case .failed:
            return .orange
        case .reviewing:
            return .green
        default:
            return .accentColor
        }
    }

    private var actionIcon: String {
        switch appState.voiceState.hotkeyAction {
        case .start:
            return "mic.fill"
        case .stop:
            return "stop.fill"
        case .cancel:
            return "xmark"
        case .inject:
            return "arrow.up.forward"
        case .none:
            return "ellipsis"
        }
    }

    private var actionColor: Color {
        switch appState.voiceState.hotkeyAction {
        case .stop:
            return .red
        case .inject:
            return .green
        case .cancel:
            return .orange
        case .start, .none:
            return .accentColor
        }
    }

    private var actionHelp: String {
        switch appState.voiceState.hotkeyAction {
        case .start:
            return UIStrings.start
        case .stop:
            return UIStrings.stop
        case .cancel:
            return UIStrings.cancel
        case .inject:
            return UIStrings.insertText
        case .none:
            return UIStrings.speechBusy
        }
    }

    private func reportPreferredSize(_ size: CGSize) {
        guard size != lastReportedPreferredSize else { return }
        lastReportedPreferredSize = size
        DispatchQueue.main.async {
            onPreferredSizeChange(size)
        }
    }
}

struct FloatingPanelLayout: Equatable {
    static let minPanelWidth: CGFloat = 280
    static let minPanelHeight: CGFloat = 58
    static let maxPanelWidth: CGFloat = 520
    static let maxPanelHeight: CGFloat = 240
    static let screenCoverage: CGFloat = 0.9
    static let headerHeight: CGFloat = 58
    static let reviewWidth: CGFloat = 440
    static let reviewHeight: CGFloat = 168
    static let statusAreaHeight: CGFloat = 42

    let panelSize: CGSize

    init(state: VoiceInputState, hasStatusArea: Bool) {
        let isReviewing = state == .reviewing
        let width = isReviewing ? Self.reviewWidth : Self.minPanelWidth
        let baseHeight = isReviewing ? Self.reviewHeight : Self.headerHeight
        let height = baseHeight + (hasStatusArea ? Self.statusAreaHeight : 0)
        panelSize = CGSize(width: width, height: height)
    }
}
