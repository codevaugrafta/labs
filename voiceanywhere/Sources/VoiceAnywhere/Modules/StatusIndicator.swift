import AppKit
import SwiftUI

/// Controls the small floating waveform panel that appears near the menu bar
/// while VoiceAnywhere is speaking.
@MainActor
class StatusIndicatorController {
    private var panel: NSPanel?

    // MARK: - Public API

    func show(near statusItem: NSStatusItem) {
        if let existing = panel {
            existing.orderFront(nil)
            return
        }

        let view = StatusIndicatorView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 60, height: 32)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 32),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.contentView = hosting

        // Position just below the status item button.
        if let button = statusItem.button, let window = button.window {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let screenFrame = window.convertToScreen(buttonFrame)
            let origin = NSPoint(
                x: screenFrame.midX - 30,
                y: screenFrame.minY - 40
            )
            newPanel.setFrameOrigin(origin)
        }

        newPanel.alphaValue = 0
        newPanel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            newPanel.animator().alphaValue = 1
        }

        panel = newPanel
    }

    func hide() {
        guard let currentPanel = panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            currentPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // The completion block runs off the main thread; hop back to satisfy
            // the @MainActor isolation requirement on `panel` and `close()`.
            Task { @MainActor [weak self] in
                currentPanel.close()
                self?.panel = nil
            }
        })
    }
}
