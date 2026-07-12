import AppKit
import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var commandStore: CommandStore
    @ObservedObject var providerStore: SpeechProviderStore
    let voiceController: VoiceInputController
    let onPreferredSizeChange: (CGSize) -> Void
    @State private var showingSettings = false
    @State private var lastReportedPreferredSize: CGSize = .zero

    private var layout: FloatingPanelLayout {
        FloatingPanelLayout(
            commands: commandStore.enabledCommands,
            hasStatusArea: hasStatusArea
        )
    }

    private var hasStatusArea: Bool {
        !appState.hasAccessibilityPermission
            || appState.pasteError != nil
            || appState.hotkeyError != nil
            || commandStore.lastError != nil
            || providerStore.lastError != nil
    }

    var body: some View {
        let layout = layout

        VStack(spacing: FloatingPanelLayout.verticalSpacing) {
            commandArea(layout: layout)

            if hasStatusArea {
                statusArea
                    .frame(height: FloatingPanelLayout.statusAreaHeight)
            }

            Divider().background(Color.primary.opacity(0.15))

            VStack(alignment: .leading, spacing: FloatingPanelLayout.previewSpacing) {
                HStack {
                    Button(action: {
                        voiceController.toggleRecording()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: voiceButtonIcon)
                            Text(voiceButtonText)
                        }
                        .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(voiceButtonColor)

                    Picker("", selection: Binding(
                        get: { providerStore.activeProviderID },
                        set: { providerStore.setActiveProvider(id: $0) }
                    )) {
                        ForEach(providerStore.providers) { provider in
                            Text(provider.name)
                                .tag(provider.id)
                                .disabled(!providerStore.isProviderReady(provider))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 128)
                    .disabled(!canChangeProvider)

                    Spacer()

                    Button(UIStrings.settings) {
                        showingSettings = true
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                }

                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundColor(previewColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(height: FloatingPanelLayout.bottomAreaHeight, alignment: .top)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                appState: appState,
                commandStore: commandStore,
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
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            appState.checkAccessibility()
        }
    }

    @ViewBuilder
    private func commandArea(layout: FloatingPanelLayout) -> some View {
        if commandStore.enabledCommands.isEmpty {
            Text(UIStrings.noEnabledCommands)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: layout.commandAreaHeight)
                .padding(.horizontal, FloatingPanelLayout.horizontalPadding)
        } else if layout.requiresCommandScroll {
            ScrollView {
                commandGrid(layout: layout)
            }
            .frame(height: layout.commandAreaHeight)
        } else {
            commandGrid(layout: layout)
                .frame(height: layout.commandAreaHeight, alignment: .top)
        }
    }

    private func commandGrid(layout: FloatingPanelLayout) -> some View {
        LazyVGrid(columns: layout.gridColumns, spacing: FloatingPanelLayout.buttonSpacing) {
            ForEach(commandStore.enabledCommands) { command in
                Button(action: {
                    injectCommand(command)
                }) {
                    VStack(spacing: 2) {
                        Text(command.title.isEmpty ? UIStrings.untitledCommand : command.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)
                        if let shortcut = command.shortcut {
                            Text(shortcut.displayString)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: layout.buttonWidth, height: FloatingPanelLayout.buttonHeight)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(6)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(.horizontal, FloatingPanelLayout.horizontalPadding)
        .padding(.top, FloatingPanelLayout.commandTopPadding)
        .padding(.bottom, FloatingPanelLayout.commandBottomPadding)
    }

    @ViewBuilder
    private var statusArea: some View {
        if !appState.hasAccessibilityPermission {
            VStack(spacing: 4) {
                Text(UIStrings.accessibilityPastePermission)
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)

                Button(UIStrings.openSettings) {
                    AccessibilityPermission.openSettings()
                }
                .font(.system(size: 10, weight: .bold))
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
        } else if let error = appState.pasteError ?? appState.hotkeyError ?? commandStore.lastError ?? providerStore.lastError {
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.red)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private func injectCommand(_ command: PromptCommand) {
        ClipboardPasteInjector.shared.inject(text: command.content) { success in
            if !success {
                appState.pasteError = UIStrings.pasteFailed
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    appState.pasteError = nil
                }
            }
        }
    }

    private func reportPreferredSize(_ size: CGSize) {
        guard size != lastReportedPreferredSize else { return }
        lastReportedPreferredSize = size
        DispatchQueue.main.async {
            onPreferredSizeChange(size)
        }
    }

    private var voiceButtonIcon: String {
        switch appState.voiceState {
        case .idle: return "mic.fill"
        case .requestingPermission, .connecting, .stopping, .transcribing:
            return "xmark.circle.fill"
        case .recording, .streaming: return "stop.circle.fill"
        case .injecting: return "square.and.arrow.down.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var voiceButtonText: String {
        switch appState.voiceState {
        case .idle: return UIStrings.start
        case .requestingPermission, .connecting, .stopping, .transcribing:
            return UIStrings.cancel
        case .recording: return UIStrings.stop
        case .streaming: return UIStrings.stop
        case .injecting: return UIStrings.injectingShort
        case .failed: return UIStrings.retry
        }
    }

    private var voiceButtonColor: Color {
        switch appState.voiceState {
        case .recording, .streaming:
            return .red
        case .failed:
            return .orange
        default:
            return .blue
        }
    }

    private var previewText: String {
        if case .failed(let errorMessage) = appState.voiceState {
            return "\(UIStrings.failed)：\(errorMessage)"
        }

        if !appState.transcriptPreview.isEmpty {
            return appState.transcriptPreview
        }

        switch appState.voiceState {
        case .idle:
            return UIStrings.transcriptPreviewPlaceholder
        case .requestingPermission:
            return UIStrings.requestingPermission
        case .connecting:
            return UIStrings.connecting
        case .recording:
            return UIStrings.dictating
        case .streaming:
            return UIStrings.realtimeTranscribing
        case .stopping:
            return UIStrings.stopping
        case .transcribing:
            return UIStrings.transcribing
        case .injecting:
            return UIStrings.injecting
        case .failed:
            return UIStrings.failed
        }
    }

    private var previewColor: Color {
        if case .failed = appState.voiceState {
            return .red
        }
        return .secondary
    }

    private var canChangeProvider: Bool {
        switch appState.voiceState {
        case .idle, .failed:
            return true
        case .requestingPermission, .connecting, .recording, .streaming, .stopping, .transcribing, .injecting:
            return false
        }
    }
}

struct FloatingPanelLayout: Equatable {
    static let minPanelWidth: CGFloat = 300
    static let minPanelHeight: CGFloat = 188
    static let maxPanelWidth: CGFloat = 720
    static let screenCoverage: CGFloat = 0.8
    static let horizontalPadding: CGFloat = 12
    static let commandTopPadding: CGFloat = 12
    static let commandBottomPadding: CGFloat = 0
    static let buttonMinWidth: CGFloat = 92
    static let buttonMaxWidth: CGFloat = 220
    static let buttonHeight: CGFloat = 44
    static let buttonSpacing: CGFloat = 8
    static let verticalSpacing: CGFloat = 10
    static let previewSpacing: CGFloat = 6
    static let dividerHeight: CGFloat = 1
    static let statusAreaHeight: CGFloat = 44
    static let bottomAreaHeight: CGFloat = 82
    static let emptyCommandHeight: CGFloat = 32
    static let minimumScrollableCommandAreaHeight: CGFloat = 120

    let panelSize: CGSize
    let commandAreaHeight: CGFloat
    let buttonWidth: CGFloat
    let columnCount: Int
    let requiresCommandScroll: Bool

    var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(buttonWidth), spacing: Self.buttonSpacing, alignment: .center),
            count: columnCount
        )
    }

    init(commands: [PromptCommand], hasStatusArea: Bool) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let maxAllowedWidth = max(Self.minPanelWidth, min(Self.maxPanelWidth, visibleFrame.width * Self.screenCoverage))
        let maxAllowedHeight = max(Self.minPanelHeight, visibleFrame.height * Self.screenCoverage)
        let buttonWidth = Self.preferredButtonWidth(for: commands)
        let maxColumns = max(
            1,
            Int(floor((maxAllowedWidth - Self.horizontalPadding * 2 + Self.buttonSpacing) / (buttonWidth + Self.buttonSpacing)))
        )
        let idealColumns = Self.idealColumnCount(for: commands.count)
        let columnCount = min(maxColumns, idealColumns)
        let rowCount = commands.isEmpty ? 1 : Int(ceil(Double(commands.count) / Double(columnCount)))
        let commandContentHeight: CGFloat

        if commands.isEmpty {
            commandContentHeight = Self.emptyCommandHeight
        } else {
            commandContentHeight = CGFloat(rowCount) * Self.buttonHeight
                + CGFloat(max(0, rowCount - 1)) * Self.buttonSpacing
        }

        let naturalCommandAreaHeight = Self.commandTopPadding + commandContentHeight + Self.commandBottomPadding
        let spacingCount = hasStatusArea ? 3 : 2
        let fixedHeight = Self.bottomAreaHeight
            + Self.dividerHeight
            + CGFloat(spacingCount) * Self.verticalSpacing
            + (hasStatusArea ? Self.statusAreaHeight : 0)
        let maxCommandAreaHeight = max(
            Self.minimumScrollableCommandAreaHeight,
            maxAllowedHeight - fixedHeight
        )
        let requiresCommandScroll = naturalCommandAreaHeight > maxCommandAreaHeight
        let commandAreaHeight = requiresCommandScroll ? maxCommandAreaHeight : naturalCommandAreaHeight
        let naturalWidth = Self.horizontalPadding * 2
            + CGFloat(columnCount) * buttonWidth
            + CGFloat(max(0, columnCount - 1)) * Self.buttonSpacing
        let panelWidth = min(maxAllowedWidth, max(Self.minPanelWidth, naturalWidth))
        let panelHeight = min(maxAllowedHeight, max(Self.minPanelHeight, commandAreaHeight + fixedHeight))

        self.panelSize = CGSize(width: ceil(panelWidth), height: ceil(panelHeight))
        self.commandAreaHeight = ceil(commandAreaHeight)
        self.buttonWidth = ceil(buttonWidth)
        self.columnCount = columnCount
        self.requiresCommandScroll = requiresCommandScroll
    }

    private static func idealColumnCount(for commandCount: Int) -> Int {
        switch commandCount {
        case ...0:
            return 1
        case 1...2:
            return commandCount
        case 3...5:
            return 3
        case 6...8:
            return 4
        default:
            return max(4, Int(ceil(Double(commandCount) / 2.0)))
        }
    }

    private static func preferredButtonWidth(for commands: [PromptCommand]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let shortcutFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let titleWidth = commands
            .map { ($0.title.isEmpty ? UIStrings.untitledCommand : $0.title) as NSString }
            .map { $0.size(withAttributes: [.font: font]).width }
            .max() ?? Self.buttonMinWidth
        let shortcutWidth = commands
            .compactMap { $0.shortcut?.displayString }
            .map { ($0 as NSString).size(withAttributes: [.font: shortcutFont]).width }
            .max() ?? 0
        let measuredWidth = max(titleWidth, shortcutWidth) + 24
        return min(Self.buttonMaxWidth, max(Self.buttonMinWidth, measuredWidth))
    }
}
