import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var timer: AnyCancellable?
    private weak var engine: TimeEntryEngine?
    private weak var floatingPanel: FloatingTimerPanel?
    private var lastActiveEntryId: UUID?

    func setup(engine: TimeEntryEngine, floatingPanel: FloatingTimerPanel? = nil) {
        self.engine = engine
        self.floatingPanel = floatingPanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
    }

    func updateStatusItem() {
        guard let statusItem else { return }
        let button = statusItem.button
        let currentEntryId = engine?.activeEntry?.id

        if let active = engine?.activeEntry, let cat = active.category {
            button?.title = " \(active.formattedDuration)"
            let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                if let color = NSColor(hex: cat.color) {
                    color.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                }
                return true
            }
            image.isTemplate = false
            button?.image = image
            button?.imagePosition = .imageLeading
        } else {
            button?.title = ""
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Tiempo")
            image?.isTemplate = true
            button?.image = image
            button?.imagePosition = .imageOnly
        }

        // Rebuild menu when active entry changes
        if currentEntryId != lastActiveEntryId {
            lastActiveEntryId = currentEntryId
            buildMenu()
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        // ── Active Timer Section ──
        if let active = engine?.activeEntry, let cat = active.category {
            let headerItem = NSMenuItem(title: "⏱ \(cat.name) — \(active.formattedDuration)", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            let stopItem = NSMenuItem(title: "Stop Timer", action: #selector(stopTimer), keyEquivalent: "s")
            stopItem.target = self
            stopItem.keyEquivalentModifierMask = [.command]
            menu.addItem(stopItem)

            menu.addItem(.separator())
        }

        // ── Concurrent running timers (if any besides active) ──
        let running = engine?.runningEntries ?? []
        let nonActiveRunning = running.filter { $0.id != engine?.activeEntry?.id }
        if !nonActiveRunning.isEmpty {
            let runningHeader = NSMenuItem(title: "Also Running", action: nil, keyEquivalent: "")
            runningHeader.isEnabled = false
            menu.addItem(runningHeader)

            for entry in nonActiveRunning {
                let catName = entry.category?.name ?? "Unknown"
                let item = NSMenuItem(
                    title: "  ● \(catName) — \(entry.formattedDuration)",
                    action: #selector(stopRunningEntry(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // ── Favorites Section ──
        let favorites = engine?.favoriteCategories ?? []
        if !favorites.isEmpty {
            let favHeader = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favHeader.isEnabled = false
            menu.addItem(favHeader)

            for (index, category) in favorites.prefix(9).enumerated() {
                let isActive = engine?.isActive(category: category) ?? false
                let dot = isActive ? "●" : "○"
                let colorDot = categoryColorDot(category.color)
                let title = "  \(dot) \(colorDot) \(category.name)"
                let shortcutKey = String(index + 1) // ⌘1, ⌘2, ...
                let item = NSMenuItem(title: title, action: #selector(toggleCategory(_:)), keyEquivalent: shortcutKey)
                item.target = self
                item.keyEquivalentModifierMask = [.command]
                item.representedObject = category
                if isActive {
                    item.state = .on
                }
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // ── All Categories Section ──
        if let ctx = engine?.modelContext {
            let descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived },
                sortBy: [SortDescriptor(\Category.sortOrder)]
            )
            if let categories = try? ctx.fetch(descriptor) {
                let nonFavIds = Set(favorites.map(\.id))
                let nonFavorites = categories.filter { !nonFavIds.contains($0.id) }

                if !nonFavorites.isEmpty {
                    let allHeader = NSMenuItem(title: "Categories", action: nil, keyEquivalent: "")
                    allHeader.isEnabled = false
                    menu.addItem(allHeader)

                    for category in nonFavorites {
                        let isActive = engine?.isActive(category: category) ?? false
                        let dot = isActive ? "●" : "○"
                        let colorDot = categoryColorDot(category.color)
                        let title = "  \(dot) \(colorDot) \(category.name)"
                        let item = NSMenuItem(title: title, action: #selector(toggleCategory(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = category
                        if isActive { item.state = .on }
                        menu.addItem(item)
                    }
                    menu.addItem(.separator())
                }
            }
        }

        // ── Floating Timer ──
        let floatingTitle = (floatingPanel?.isVisible ?? false) ? "Hide Floating Timer" : "Show Floating Timer"
        let floatingItem = NSMenuItem(title: floatingTitle, action: #selector(toggleFloatingPanel), keyEquivalent: "f")
        floatingItem.target = self
        floatingItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(floatingItem)

        // ── Show Main Window ──
        let showWindowItem = NSMenuItem(title: "Show Main Window", action: #selector(showMainWindow), keyEquivalent: "o")
        showWindowItem.target = self
        showWindowItem.keyEquivalentModifierMask = [.command]
        menu.addItem(showWindowItem)

        // ── Theme Section ──
        let themeManager = ThemeManager.shared
        let themeItem = NSMenuItem(
            title: "Theme: \(themeManager.current.displayName)",
            action: #selector(cycleTheme),
            keyEquivalent: "t"
        )
        themeItem.target = self
        themeItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(themeItem)

        menu.addItem(.separator())

        // ── Quit ──
        let quitItem = NSMenuItem(title: "Quit Tiempo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func stopTimer() {
        ThemeManager.shared.playStopFeedback()
        engine?.stopTimer()
        buildMenu()
        updateStatusItem()
    }

    @objc private func stopRunningEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? TimeEntry else { return }
        ThemeManager.shared.playStopFeedback()
        engine?.stopTimer(entry)
        buildMenu()
        updateStatusItem()
    }

    @objc private func toggleCategory(_ sender: NSMenuItem) {
        guard let category = sender.representedObject as? Category else { return }
        let wasActive = engine?.isActive(category: category) ?? false
        engine?.toggleTimer(for: category)
        if wasActive {
            ThemeManager.shared.playStopFeedback()
        } else {
            ThemeManager.shared.playStartFeedback()
        }
        buildMenu()
        updateStatusItem()
    }

    @objc private func toggleFloatingPanel() {
        if floatingPanel?.isVisible ?? false {
            floatingPanel?.hide()
        } else {
            floatingPanel?.show()
        }
        buildMenu()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title != "" && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }

    @objc private func cycleTheme() {
        ThemeManager.shared.cycleTheme()
        buildMenu()
    }

    // MARK: - Helpers

    private func categoryColorDot(_ hex: String) -> String {
        // Unicode colored circles aren't available, so we use the bullet
        // The actual color shows in the NSMenuItem's attributed string in a future iteration
        return "◆"
    }
}

// MARK: - NSColor hex

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
