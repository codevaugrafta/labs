import AppKit
import SwiftData
import SwiftUI

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private weak var engine: LoveEngine?

    func setup(engine: LoveEngine) {
        self.engine = engine
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            let img = NSImage(systemSymbolName: "heart.circle.fill", accessibilityDescription: "Love")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageLeading
        }
        buildMenu()
        updateTitle()
    }

    func refresh() {
        updateTitle()
        buildMenu()
    }

    private func updateTitle() {
        guard let statusItem, let engine else { return }
        let button = statusItem.button
        if let focus = engine.focusedItem() {
            let title = Self.truncate(focus.title, maxChars: 42)
            button?.title = title
            button?.toolTip = focus.title
        } else {
            button?.title = "Love"
            button?.toolTip = "No focus set"
        }
    }

    private static func truncate(_ s: String, maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        let idx = s.index(s.startIndex, offsetBy: maxChars - 1)
        return String(s[..<idx]) + "…"
    }

    private func buildMenu() {
        guard let statusItem, let engine else { return }
        let menu = NSMenu()

        let completeItem = NSMenuItem(title: "Complete focus", action: #selector(completeFocus), keyEquivalent: "")
        completeItem.target = self
        completeItem.isEnabled = engine.focusedItem() != nil
        menu.addItem(completeItem)

        let nextItem = NSMenuItem(title: "Clear focus", action: #selector(clearFocus), keyEquivalent: "")
        nextItem.target = self
        nextItem.isEnabled = engine.focusedItem() != nil
        menu.addItem(nextItem)

        menu.addItem(.separator())

        let captureItem = NSMenuItem(title: "Quick capture…", action: #selector(quickCapture), keyEquivalent: "l")
        captureItem.keyEquivalentModifierMask = [.control, .option]
        captureItem.target = self
        menu.addItem(captureItem)

        let showItem = NSMenuItem(title: "Show main window", action: #selector(showMain), keyEquivalent: "o")
        showItem.keyEquivalentModifierMask = .command
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Love", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.appearsDisabled = false
    }

    @objc private func completeFocus() {
        engine?.completeFocused(advanceToNext: true)
        refresh()
    }

    @objc private func clearFocus() {
        engine?.clearFocus()
        refresh()
    }

    @objc private func quickCapture() {
        NotificationCenter.default.post(name: .loveQuickCapture, object: nil)
    }

    @objc private func showMain() {
        NotificationCenter.default.post(name: .loveShowMainWindow, object: nil)
    }
}
