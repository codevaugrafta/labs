import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var timer: AnyCancellable?
    private weak var engine: TimeEntryEngine?

    func setup(engine: TimeEntryEngine) {
        self.engine = engine

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

        if let active = engine?.activeEntry, let cat = active.category {
            let duration = active.formattedDuration
            button?.title = " \(duration)"

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

        buildMenu()
    }

    private func buildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        if let active = engine?.activeEntry, let cat = active.category {
            let activeItem = NSMenuItem(title: "⏱ \(cat.name) — \(active.formattedDuration)", action: nil, keyEquivalent: "")
            activeItem.isEnabled = false
            menu.addItem(activeItem)

            let stopItem = NSMenuItem(title: "Stop Timer", action: #selector(stopTimer), keyEquivalent: "s")
            stopItem.target = self
            menu.addItem(stopItem)
            menu.addItem(.separator())
        }

        if let ctx = engine?.modelContext {
            let descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived },
                sortBy: [SortDescriptor(\Category.sortOrder)]
            )
            if let categories = try? ctx.fetch(descriptor) {
                for category in categories.prefix(8) {
                    let isActive = engine?.isActive(category: category) ?? false
                    let title = (isActive ? "● " : "○ ") + category.name
                    let item = NSMenuItem(title: title, action: #selector(toggleCategory(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = category
                    menu.addItem(item)
                }
                if !categories.isEmpty {
                    menu.addItem(.separator())
                }
            }
        }

        let quitItem = NSMenuItem(title: "Quit Tiempo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func stopTimer() {
        engine?.stopTimer()
        updateStatusItem()
    }

    @objc private func toggleCategory(_ sender: NSMenuItem) {
        guard let category = sender.representedObject as? Category else { return }
        engine?.toggleTimer(for: category)
        updateStatusItem()
    }
}

// MARK: - NSColor hex

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
