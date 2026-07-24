import AppKit
import SwiftUI

class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private let appState: AppState

    init(
        appState: AppState,
        providerStore: SpeechProviderStore,
        voiceController: VoiceInputController
    ) {
        self.appState = appState
        let panel = NSPanel(
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
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        
        let hostingView = NSHostingView(
            rootView: FloatingPanelView(
                appState: appState,
                providerStore: providerStore,
                voiceController: voiceController,
                onPreferredSizeChange: { [weak panel] preferredSize in
                    guard let panel else { return }
                    Self.applyPreferredContentSize(preferredSize, to: panel)
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
        panel.contentMinSize = CGSize(
            width: FloatingPanelLayout.minPanelWidth,
            height: FloatingPanelLayout.minPanelHeight
        )
        panel.contentMaxSize = CGSize(
            width: FloatingPanelLayout.maxPanelWidth,
            height: FloatingPanelLayout.maxPanelHeight
        )
        
        if let screen = NSScreen.main {
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.orderFrontRegardless()
        appState.isPanelVisible = true
    }

    func windowWillClose(_ notification: Notification) {
        appState.isPanelVisible = false
    }

    private static func applyPreferredContentSize(_ preferredSize: CGSize, to panel: NSPanel) {
        DispatchQueue.main.async {
            let visibleFrame = panel.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 900, height: 700)
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

            if abs(currentContentSize.width - targetContentSize.width) < 1,
               abs(currentContentSize.height - targetContentSize.height) < 1 {
                keepPanelInsideVisibleFrame(panel, visibleFrame: visibleFrame)
                return
            }

            let targetFrameSize = panel.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetContentSize)
            ).size
            let currentFrame = panel.frame
            var targetOrigin = NSPoint(
                x: currentFrame.midX - targetFrameSize.width / 2,
                y: currentFrame.minY
            )
            targetOrigin = clampedOrigin(
                targetOrigin,
                frameSize: targetFrameSize,
                visibleFrame: visibleFrame
            )

            panel.setFrame(
                NSRect(origin: targetOrigin, size: targetFrameSize),
                display: true,
                animate: false
            )
        }
    }

    private static func keepPanelInsideVisibleFrame(_ panel: NSPanel, visibleFrame: NSRect) {
        let frame = panel.frame
        let origin = clampedOrigin(frame.origin, frameSize: frame.size, visibleFrame: visibleFrame)
        if origin != frame.origin {
            panel.setFrameOrigin(origin)
        }
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
