import AppKit
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
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() { panel?.close(); panel = nil }
    var isVisible: Bool { panel != nil }
}
