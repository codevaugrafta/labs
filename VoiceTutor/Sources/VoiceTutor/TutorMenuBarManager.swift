import AppKit
import SwiftUI

@MainActor
final class TutorMenuBarManager {
    private var statusItem: NSStatusItem?
    private weak var session: TutorSessionController?
    private var popover: NSPopover?

    func setup(session: TutorSessionController) {
        self.session = session

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            let img = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: "Voice Tutor")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.setAccessibilityIdentifier("voiceTutor.menuBarButton")
            button.setAccessibilityLabel("Voice Tutor")
            button.setAccessibilityHelp("Open Voice Tutor")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover = NSPopover()
        popover?.behavior = .transient
        rebuildPopover()
    }

    func refresh() {
        if popover?.isShown == true {
            rebuildPopover()
        }
    }

    private func rebuildPopover() {
        guard let popover, let session else { return }
        popover.contentViewController = NSHostingController(
            rootView: TutorPopoverView(session: session)
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            rebuildPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
