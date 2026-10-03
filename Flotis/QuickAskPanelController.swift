import AppKit
import SwiftUI

enum QuickAskPanelMouseDownAction: Equatable {
    case beginDrag
    case forward
}

enum QuickAskPanelInteraction {
    // The panel remains fixed outside a user gesture so Window Server cannot
    // relocate it during Space/display transitions. The title strip hands the
    // original mouse-down directly to AppKit's native window drag instead.
    static let allowsSystemManagedMovement = false
    static let titleBarHeight: CGFloat = 44
    static let trailingControlsWidth: CGFloat = 80

    static func mouseDownAction(
        clickCount: Int,
        location: NSPoint,
        contentSize: NSSize
    ) -> QuickAskPanelMouseDownAction {
        guard clickCount == 1,
              contentSize.width > trailingControlsWidth,
              contentSize.height >= titleBarHeight,
              location.x >= 0,
              location.x < contentSize.width - trailingControlsWidth,
              location.y >= contentSize.height - titleBarHeight,
              location.y <= contentSize.height else {
            return .forward
        }
        return .beginDrag
    }
}

@MainActor
final class QuickAskPanelController {
    static let panelSize = NSSize(width: 420, height: 560)

    private let panel: QuickAskPanel
    private let session: QuickAskSession
    private weak var anchorWindow: NSWindow?
    private var anchorObservers: [NSObjectProtocol] = []

    init(
        session: QuickAskSession,
        configurationStore: QuickAskConfigurationStore,
        onOpenSettings: @escaping () -> Void
    ) {
        self.session = session
        panel = QuickAskPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize)
        )

        let view = QuickAskView(
            session: session,
            configurationStore: configurationStore,
            onOpenSettings: onOpenSettings,
            onClose: { [weak self] in
                self?.close()
            }
        )
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        panel.contentView = NSHostingView(rootView: view)
    }

    var isVisible: Bool { panel.isVisible }

    func setAnchorWindow(_ window: NSWindow?) {
        for observer in anchorObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        anchorObservers.removeAll()
        anchorWindow = window
        guard let window else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window, self.isVisible else { return }
                    self.reposition(adjacentTo: window.frame)
                }
            }
            anchorObservers.append(observer)
        }
    }

    func show(adjacentTo capsuleFrame: NSRect?) {
        panel.setFrameOrigin(
            resolvedOrigin(adjacentTo: capsuleFrame ?? anchorWindow?.frame)
        )
        // Match the capsule's cross-application ordering without activating
        // every Flotis window. A nonactivating panel can still become key, so
        // the composer keeps keyboard focus while the foreground app remains
        // otherwise undisturbed.
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [weak panel] in
            guard let panel,
                  let textView = Self.firstTextView(in: panel.contentView) else {
                return
            }
            panel.makeFirstResponder(textView)
        }
    }

    func close() {
        panel.orderOut(nil)
        session.close()
    }

    deinit {
        for observer in anchorObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static func resolvedOrigin(
        capsuleFrame: NSRect,
        panelSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let minimumX = visibleFrame.minX
        let maximumX = visibleFrame.maxX - panelSize.width
        let x: CGFloat
        if maximumX < minimumX {
            x = visibleFrame.midX - panelSize.width / 2
        } else {
            var candidate = capsuleFrame.minX - panelSize.width - 12
            if candidate < minimumX {
                candidate = min(capsuleFrame.maxX + 12, maximumX)
            }
            x = min(max(candidate, minimumX), maximumX)
        }

        let minimumY = visibleFrame.minY
        let maximumY = visibleFrame.maxY - panelSize.height
        let y = maximumY < minimumY
            ? visibleFrame.midY - panelSize.height / 2
            : min(max(capsuleFrame.midY - panelSize.height / 2, minimumY), maximumY)
        return NSPoint(x: x, y: y)
    }

    private func reposition(adjacentTo capsuleFrame: NSRect?) {
        panel.setFrameOrigin(resolvedOrigin(adjacentTo: capsuleFrame))
    }

    private func resolvedOrigin(adjacentTo capsuleFrame: NSRect?) -> NSPoint {
        if let capsuleFrame,
           capsuleFrame.width > 0,
           let screen = NSScreen.screens.first(where: {
               $0.frame.contains(NSPoint(x: capsuleFrame.midX, y: capsuleFrame.midY))
           }) ?? NSScreen.main {
            return Self.resolvedOrigin(
                capsuleFrame: capsuleFrame,
                panelSize: Self.panelSize,
                visibleFrame: screen.visibleFrame
            )
        }
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(
            x: visibleFrame.midX - Self.panelSize.width / 2,
            y: visibleFrame.midY - Self.panelSize.height / 2
        )
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? QuickAskComposerNSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

final class QuickAskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let contentSize = contentView?.bounds.size ?? frame.size
            switch QuickAskPanelInteraction.mouseDownAction(
                clickCount: event.clickCount,
                location: event.locationInWindow,
                contentSize: contentSize
            ) {
            case .beginDrag:
                performDrag(with: event)
                return
            case .forward:
                break
            }
        }
        super.sendEvent(event)
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = QuickAskPanelInteraction.allowsSystemManagedMovement
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }
}
