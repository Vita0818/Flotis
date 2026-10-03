import AppKit
import SwiftUI

struct QuickAskView: View {
    @ObservedObject var session: QuickAskSession
    @ObservedObject var configurationStore: QuickAskConfigurationStore

    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.5)

            if let error = session.lastError {
                QuickAskErrorBanner(
                    message: error.localizedDescription,
                    onDismiss: session.dismissError
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            messageList
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FlotisTheme.separator(colorScheme), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onExitCommand(perform: onClose)
        .font(FlotisType.body())
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text(UIStrings.quickAsk)
                .font(FlotisType.headline(13, .semibold))

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UIStrings.settings)
            .help(UIStrings.settings)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UIStrings.quickAskCloseAndDestroy)
            .help(UIStrings.quickAskCloseAndDestroy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if session.messages.isEmpty {
                        emptyState
                    }

                    ForEach(session.messages) { message in
                        QuickAskMessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages) { messages in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            if configurationStore.configuration.model.isEmpty {
                Image(systemName: "gearshape")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)

                Text(UIStrings.quickAskNotConfigured)
                    .font(FlotisType.body(13, .medium))

                Text(UIStrings.quickAskConfigurePrompt)
                    .font(FlotisType.caption(11, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(UIStrings.quickAskOpenSettings, action: onOpenSettings)
                    .buttonStyle(.link)
                    .font(FlotisType.caption(11, .medium))
            } else {
                Text(UIStrings.quickAskEphemeralConversation)
                    .font(FlotisType.body(13, .medium))
                    .foregroundStyle(.secondary)

                Text(UIStrings.quickAskEphemeralDescription)
                    .font(FlotisType.caption(11, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 48)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            QuickAskTextEditor(
                text: $session.draft,
                onCommit: session.sendDraft
            )
            .frame(height: 64)
            .overlay(alignment: .topLeading) {
                if session.draft.isEmpty {
                    Text(UIStrings.quickAskComposerPlaceholder)
                        .font(FlotisType.body(13, .regular))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .padding(.top, 10)
                        .padding(.leading, 11)
                        .allowsHitTesting(false)
                }
            }
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            if session.isRequesting {
                Button(action: session.cancelCurrent) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(UIStrings.quickAskStopRequest)
                .help(UIStrings.quickAskStopRequest)
                .padding(.bottom, 2)
            } else {
                Button(action: session.sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityLabel(UIStrings.quickAskSend)
                .help(UIStrings.quickAskSend)
                .padding(.bottom, 2)
            }
        }
        .padding(12)
    }
}

private struct QuickAskMessageBubble: View {
    let message: QuickAskMessage

    @State private var copied = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 28) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(message.content)
                    .font(FlotisType.body(13, .regular))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .textSelection(.enabled)

                if !isUser {
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(copied ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copied ? UIStrings.quickAskCopied : UIStrings.copyText)
                    .help(copied ? UIStrings.quickAskCopied : UIStrings.copyText)
                    .opacity(copied ? 1 : 0.55)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isUser
                    ? Color.accentColor.opacity(0.85)
                    : Color.primary.opacity(0.06)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu {
                Button(copied ? UIStrings.quickAskCopied : UIStrings.copyText, action: copy)
            }

            if !isUser { Spacer(minLength: 28) }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(message.content, forType: .string) else { return }
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}

private struct QuickAskErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .padding(.top, 1)

            Text(message)
                .font(FlotisType.caption(11, .regular))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UIStrings.quickAskDismissError)
            .help(UIStrings.quickAskDismissError)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Color.red.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

struct QuickAskTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = QuickAskComposerNSTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 64)
        textView.delegate = context.coordinator
        textView.onCommit = context.coordinator.onCommit
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = FlotisType.appKit(13, .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 7, height: 7)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 64)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        guard let textView = scrollView.documentView as? QuickAskComposerNSTextView else {
            return
        }
        textView.onCommit = onCommit
        textView.font = FlotisType.appKit(13, .regular)
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
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

final class QuickAskComposerNSTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let shouldInsertNewline = event.modifierFlags.contains(.shift)
        if isReturn, !shouldInsertNewline, !hasMarkedText() {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}
