import AppKit
import SwiftUI

// MARK: - Controller

/// Singleton that owns the floating NSPanel and routes word-tap events to it.
///
/// Action callbacks (onKnow, onReview, onListen) are injected at `show()` time
/// by the WKWebView Coordinator, which already holds references to
/// FamiliarityTracker and FSRSEngine via the existing `onPopupAction` bridge.
/// This avoids threading SwiftData's ModelContext through another layer.
///
/// Usage:
/// ```swift
/// FloatingDictionaryController.shared.show(
///     data: lookupData,
///     screenPoint: screenPoint,
///     onKnow: { coordinator.onPopupAction(.markKnown, word) },
///     onReview: { coordinator.onPopupAction(.addToSRS, word) },
///     onListen: { NotificationCenter.default.post(name: .leoPlayTTS, object: word) }
/// )
/// ```
@MainActor
final class FloatingDictionaryController {

    static let shared = FloatingDictionaryController()

    private var panel: FloatingDictionaryPanel?
    private var hostingView: NSHostingView<FloatingDictionaryContent>?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?

    private init() {}

    // MARK: - Show

    /// Display (or update) the floating panel near `screenPoint`.
    func show(
        data: DictionaryLookupData,
        screenPoint: CGPoint,
        onKnow: @escaping () -> Void,
        onReview: @escaping () -> Void,
        onListen: @escaping () -> Void
    ) {
        if let existingPanel = panel {
            updateContent(in: existingPanel, data: data, onKnow: onKnow, onReview: onReview, onListen: onListen)
            repositionPanel(existingPanel, near: screenPoint)
            if !existingPanel.isVisible {
                existingPanel.orderFront(nil)
            }
        } else {
            let newPanel = makePanel(data: data, onKnow: onKnow, onReview: onReview, onListen: onListen)
            self.panel = newPanel
            repositionPanel(newPanel, near: screenPoint)
            newPanel.orderFront(nil)
        }
        installMonitors()
    }

    // MARK: - Dismiss

    func dismiss() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    // MARK: - Private helpers

    private func makePanel(
        data: DictionaryLookupData,
        onKnow: @escaping () -> Void,
        onReview: @escaping () -> Void,
        onListen: @escaping () -> Void
    ) -> FloatingDictionaryPanel {
        let content = FloatingDictionaryContent(
            data: data,
            onKnow: { onKnow() },
            onReview: { onReview() },
            onListen: { onListen() },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        self.hostingView = hosting

        let panel = FloatingDictionaryPanel(contentRect: .zero)
        panel.contentView = hosting
        return panel
    }

    private func updateContent(
        in panel: FloatingDictionaryPanel,
        data: DictionaryLookupData,
        onKnow: @escaping () -> Void,
        onReview: @escaping () -> Void,
        onListen: @escaping () -> Void
    ) {
        let newContent = FloatingDictionaryContent(
            data: data,
            onKnow: { onKnow() },
            onReview: { onReview() },
            onListen: { onListen() },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        if let hosting = hostingView {
            hosting.rootView = newContent
        } else {
            let hosting = NSHostingView(rootView: newContent)
            hosting.sizingOptions = [.preferredContentSize]
            self.hostingView = hosting
            panel.contentView = hosting
        }
    }

    // MARK: - Click-outside & Escape monitors

    private func installMonitors() {
        removeMonitors()

        // Dismiss when clicking outside the panel
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            // If the click landed inside the panel, let it through
            let clickLocation = NSEvent.mouseLocation
            if panel.frame.contains(clickLocation) {
                return event
            }
            self.dismiss()
            return event
        }

        // Dismiss on Escape key
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            if event.keyCode == 53 { // Escape
                self.dismiss()
                return nil // consume the event
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    /// Position the panel below the tapped word; flip above if it clips the bottom edge.
    private func repositionPanel(_ panel: FloatingDictionaryPanel, near point: CGPoint) {
        hostingView?.layoutSubtreeIfNeeded()

        let size = panel.contentView?.fittingSize ?? CGSize(width: 340, height: 180)
        let verticalOffset: CGFloat = 12

        let screen = NSScreen.screens.first(where: { NSMouseInCocoaScreen($0) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        // Default: below the tap point.
        var origin = CGPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height - verticalOffset
        )

        // Flip above if there is not enough room below.
        if origin.y < visibleFrame.minY {
            origin.y = point.y + verticalOffset
        }

        // Clamp horizontally so the panel stays on-screen.
        origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - size.width - 8))

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when the user taps "Listen" in the floating panel.
    /// `object` is the word String. ReaderView subscribes and calls ttsEngine.generate().
    static let leoPlayTTS = Notification.Name("leoPlayTTS")
}

// MARK: - Screen helper

private func NSMouseInCocoaScreen(_ screen: NSScreen) -> Bool {
    screen.frame.contains(NSEvent.mouseLocation)
}
