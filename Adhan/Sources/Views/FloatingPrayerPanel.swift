import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class FloatingPrayerPanel {
    private var panel: NSPanel?
    private weak var engine: PrayerTimesEngine?

    func setup(engine: PrayerTimesEngine) {
        self.engine = engine
    }

    func show() {
        guard let engine, panel == nil else { return }
        let content = FloatingPrayerView(engine: engine, onClose: { [weak self] in self?.hide() })
        let hostingView = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: sf.maxX - 370, y: sf.midY - 210))
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFront(nil)
        } else {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        AdhanFeedback.onPanelReveal()
        self.panel = panel
    }

    func hide() { panel?.close(); panel = nil }
    var isVisible: Bool { panel != nil }
}
