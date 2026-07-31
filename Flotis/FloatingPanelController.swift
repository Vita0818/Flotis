import AppKit
import SwiftUI

private final class FlotisFloatingPanel: NSPanel {
    var pendingResizeWorkItem: DispatchWorkItem?
    var anchoredScreenNumber: NSNumber?
    var latestPreferredContentSize: CGSize?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private let appState: AppState
    private var screenParametersObserver: NSObjectProtocol?
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    init(
        appState: AppState,
        voiceController: VoiceInputController,
        onOpenSettings: @escaping () -> Void
    ) {
        self.appState = appState
        let panel = FlotisFloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: FloatingPanelLayout.minPanelWidth,
                height: FloatingPanelLayout.minPanelHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = FloatingPanelLayout.cornerRadius
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true
        // NSVisualEffectView's material mask also shapes the window-server shadow;
        // a CALayer corner alone only clips the hosted subviews.
        visualEffect.maskImage = Self.makeRoundedMaterialMask(
            cornerRadius: FloatingPanelLayout.cornerRadius
        )
        
        let hostingView = NSHostingView(
            rootView: FloatingPanelView(
                appState: appState,
                voiceController: voiceController,
                onOpenSettings: onOpenSettings,
                onPreferredSizeChange: { [weak panel] preferredSize in
                    guard let panel else { return }
                    Self.schedulePreferredContentSize(preferredSize, to: panel)
                }
            )
        )
        
        visualEffect.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])
        
        panel.contentView = visualEffect
        panel.invalidateShadow()
        panel.contentMinSize = CGSize(
            width: FloatingPanelLayout.minPanelWidth,
            height: FloatingPanelLayout.minPanelHeight
        )
        panel.contentMaxSize = CGSize(
            width: FloatingPanelLayout.maxPanelWidth,
            height: FloatingPanelLayout.maxPanelHeight
        )
        
        if let screen = NSScreen.main {
            panel.anchoredScreenNumber = screen.deviceDescription[Self.screenNumberKey] as? NSNumber
            let screenRect = screen.visibleFrame
            let panelRect = panel.frame
            panel.setFrameOrigin(
                NSPoint(
                    x: screenRect.midX - panelRect.width / 2,
                    y: screenRect.minY + 32
                )
            )
        }
        
        super.init(window: panel)
        panel.delegate = self
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            let contentSize = panel.latestPreferredContentSize
                ?? panel.contentRect(forFrameRect: panel.frame).size
            Self.schedulePreferredContentSize(contentSize, to: panel)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }
    
    override func showWindow(_ sender: Any?) {
        if let panel = window as? FlotisFloatingPanel {
            let contentSize = panel.latestPreferredContentSize
                ?? panel.contentRect(forFrameRect: panel.frame).size
            Self.applyPreferredContentSize(contentSize, to: panel)
        }
        super.showWindow(sender)
        window?.orderFrontRegardless()
        window?.invalidateShadow()
        appState.isPanelVisible = true
    }

    func windowWillClose(_ notification: Notification) {
        appState.isPanelVisible = false
    }

    private static func schedulePreferredContentSize(
        _ preferredSize: CGSize,
        to panel: FlotisFloatingPanel
    ) {
        panel.latestPreferredContentSize = preferredSize
        panel.pendingResizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            applyPreferredContentSize(preferredSize, to: panel)
        }
        panel.pendingResizeWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private static func applyPreferredContentSize(
        _ preferredSize: CGSize,
        to panel: FlotisFloatingPanel
    ) {
        panel.latestPreferredContentSize = preferredSize
        let visibleFrame = anchoredVisibleFrame(for: panel)
        let maxContentSize = CGSize(
            width: max(
                FloatingPanelLayout.minPanelWidth,
                min(FloatingPanelLayout.maxPanelWidth, visibleFrame.width * FloatingPanelLayout.screenCoverage)
            ),
            height: max(
                FloatingPanelLayout.minPanelHeight,
                min(
                    FloatingPanelLayout.maxPanelHeight,
                    visibleFrame.height * FloatingPanelLayout.screenCoverage
                )
            )
        )
        let targetContentSize = CGSize(
            width: min(max(preferredSize.width, FloatingPanelLayout.minPanelWidth), maxContentSize.width),
            height: min(max(preferredSize.height, FloatingPanelLayout.minPanelHeight), maxContentSize.height)
        )
        let currentContentSize = panel.contentRect(forFrameRect: panel.frame).size

        panel.contentMinSize = CGSize(
            width: FloatingPanelLayout.minPanelWidth,
            height: FloatingPanelLayout.minPanelHeight
        )
        panel.contentMaxSize = maxContentSize

        let targetFrameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        var targetOrigin = NSPoint(
            x: visibleFrame.midX - targetFrameSize.width / 2,
            y: visibleFrame.minY + 32
        )
        targetOrigin = clampedOrigin(
            targetOrigin,
            frameSize: targetFrameSize,
            visibleFrame: visibleFrame
        )

        let originChanged = abs(panel.frame.origin.x - targetOrigin.x) >= 1
            || abs(panel.frame.origin.y - targetOrigin.y) >= 1
        let sizeChanged = abs(currentContentSize.width - targetContentSize.width) >= 1
            || abs(currentContentSize.height - targetContentSize.height) >= 1
        guard originChanged || sizeChanged else {
            panel.invalidateShadow()
            return
        }

        panel.setFrame(
            NSRect(origin: targetOrigin, size: targetFrameSize),
            display: true,
            animate: false
        )
        panel.invalidateShadow()
    }

    private static func anchoredVisibleFrame(for panel: FlotisFloatingPanel) -> NSRect {
        if let anchoredScreenNumber = panel.anchoredScreenNumber,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[screenNumberKey] as? NSNumber) == anchoredScreenNumber
           }) {
            return screen.visibleFrame
        }

        let screen = panel.screen ?? NSScreen.main
        panel.anchoredScreenNumber = screen?.deviceDescription[screenNumberKey] as? NSNumber
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
    }

    private static func makeRoundedMaterialMask(cornerRadius: CGFloat) -> NSImage {
        let side = cornerRadius * 2 + 1
        let image = NSImage(
            size: NSSize(width: side, height: side),
            flipped: false
        ) { rect in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    private static func clampedOrigin(
        _ origin: NSPoint,
        frameSize: CGSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let margin: CGFloat = 12
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - margin - frameSize.width
        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - margin - frameSize.height

        let x: CGFloat
        if maxX < minX {
            x = visibleFrame.midX - frameSize.width / 2
        } else {
            x = min(max(origin.x, minX), maxX)
        }

        let y: CGFloat
        if maxY < minY {
            y = visibleFrame.midY - frameSize.height / 2
        } else {
            y = min(max(origin.y, minY), maxY)
        }

        return NSPoint(x: x, y: y)
    }
}
