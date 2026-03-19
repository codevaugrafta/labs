import ApplicationServices
import AppKit

class TextCapture {
    /// Capture selected text from the frontmost application.
    /// Uses chain of responsibility: AXUIElement -> clipboard fallback.
    func captureSelectedText() -> String? {
        if let text = captureViaAccessibility() {
            return text.isEmpty ? nil : text
        }
        return captureViaClipboard()
    }

    private func captureViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let focusError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusError == .success, let element = focusedElement else {
            return nil
        }

        // swiftlint:disable:next force_cast
        let axElement = element as! AXUIElement

        var selectedText: AnyObject?
        let textError = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard textError == .success, let text = selectedText as? String else {
            return nil
        }

        return text
    }

    private func captureViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general

        // Snapshot the current clipboard so we can restore it afterwards.
        let savedItems: [(NSPasteboard.PasteboardType, Data)] = pasteboard.pasteboardItems?.compactMap { item in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        // Simulate Cmd+C to copy the current selection.
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 0x08 // 'c'
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Give the target app a moment to update the clipboard.
        Thread.sleep(forTimeInterval: 0.1)

        let text = pasteboard.string(forType: .string)

        // Restore the original clipboard contents.
        pasteboard.clearContents()
        for (type, data) in savedItems {
            pasteboard.setData(data, forType: type)
        }

        return text
    }
}
