import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var timer: AnyCancellable?
    private weak var engine: PrayerTimesEngine?
    private weak var floatingPanel: FloatingPrayerPanel?
    private weak var adhanPlayer: AdhanPlayer?
    private var lastNextPrayerId: String?
    private var lastAdhanPlaying: Bool = false
    /// SwiftUI `Settings` scene — use this instead of private `showSettingsWindow:` (unreliable from NSMenu).
    private var openSettingsFromSwiftUI: (() -> Void)?

    /// Call from `WindowGroup` content once `openSettings` is available (e.g. `AppBootstrapView.onAppear`).
    func configureOpenSettings(_ action: @escaping () -> Void) {
        openSettingsFromSwiftUI = action
    }

    func setup(engine: PrayerTimesEngine, floatingPanel: FloatingPrayerPanel? = nil, adhanPlayer: AdhanPlayer? = nil) {
        self.engine = engine
        self.floatingPanel = floatingPanel
        self.adhanPlayer = adhanPlayer
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyStatusButtonToolTip()
        updateStatusItem()
        buildMenu()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.engine?.tick()
                self?.updateStatusItem()
            }
    }

    // MARK: - Status Item Update

    private func updateStatusItem() {
        guard let statusItem, let engine else { return }
        let button = statusItem.button

        let displayMode = MenuBarDisplayMode(
            rawValue: UserDefaults.standard.integer(forKey: AppSettings.menuBarDisplayModeKey)
        ) ?? .countdown

        switch displayMode {
        case .countdown:
            if let next = engine.nextPrayer {
                let label = next.isNextDayPreview ? "\(next.prayer.displayName) (tmrw)" : next.prayer.displayName
                button?.title = " \(label) in \(next.formattedCountdown)"
                setCrescentIcon(button)
            } else {
                button?.title = ""
                setCrescentIcon(button)
            }

        case .exactTime:
            if let next = engine.nextPrayer {
                let label = next.isNextDayPreview ? "\(next.prayer.displayName) (tmrw)" : next.prayer.displayName
                button?.title = " \(label) \(next.formattedBeginTime)"
                setCrescentIcon(button)
            } else {
                button?.title = ""
                setCrescentIcon(button)
            }

        case .iconOnly:
            button?.title = ""
            setCrescentIcon(button)
        }

        applyStatusButtonToolTip()

        // Rebuild menu when next prayer or playback changes (Stop Adhan enabled state, labels).
        let currentNextId = engine.nextPrayer?.id
        let playing = adhanPlayer?.isPlaying ?? false
        if currentNextId != lastNextPrayerId || playing != lastAdhanPlaying {
            lastNextPrayerId = currentNextId
            lastAdhanPlaying = playing
            buildMenu()
        }
    }

    private func setCrescentIcon(_ button: NSStatusBarButton?) {
        let image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Adhan")
        image?.isTemplate = true
        button?.image = image
        button?.imagePosition = .imageLeading
    }

    private func applyStatusButtonToolTip() {
        statusItem?.button?.toolTip =
            "Adhan \(AdhanBuildInfo.versionSummary) — \(AdhanBuildInfo.runKindMenuLabel). Hover menu first row to verify."
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        guard let statusItem, let engine else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        // ── Build identity (so you can see .app vs swift run at a glance)
        let buildTitle = "Adhan \(AdhanBuildInfo.versionSummary) — \(AdhanBuildInfo.runKindMenuLabel)"
        let buildRow = NSMenuItem(title: buildTitle, action: #selector(showAdhanBuildInfo(_:)), keyEquivalent: "")
        buildRow.target = self
        buildRow.isEnabled = true
        buildRow.toolTip = "Click for build details (bundle path). Use Adhan.app from /Applications or build/ for release behavior."
        menu.addItem(buildRow)

        menu.addItem(.separator())

        // ── Hijri Date / location (click = copy — avoids “dead” menu affordance)
        let hijriItem = NSMenuItem(title: "\u{263D} \(engine.hijriEngine.hijriDateString)", action: #selector(copyMenuItemTitle(_:)), keyEquivalent: "")
        hijriItem.target = self
        hijriItem.isEnabled = true
        hijriItem.toolTip = "Copy Hijri date to clipboard"
        menu.addItem(hijriItem)

        let locationItem = NSMenuItem(title: "\u{1F4CD} \(engine.locationName)", action: #selector(copyMenuItemTitle(_:)), keyEquivalent: "")
        locationItem.target = self
        locationItem.isEnabled = true
        locationItem.toolTip = "Copy location name to clipboard"
        menu.addItem(locationItem)

        menu.addItem(.separator())

        // ── Stop playback (discoverable; same as app menu ⌘⇧S) ──
        let stopItem = NSMenuItem(
            title: "Stop Adhan Playback",
            action: #selector(stopAdhanPlayback),
            keyEquivalent: "s"
        )
        stopItem.target = self
        stopItem.keyEquivalentModifierMask = [.command, .shift]
        stopItem.isEnabled = adhanPlayer?.isPlaying ?? false
        stopItem.toolTip = "Stops Adhan, preview, or pre-reminder chime (⌘⇧S)."
        menu.addItem(stopItem)

        menu.addItem(.separator())

        // ── Prayer Times ──
        let timetableMenuInsertIndex = menu.items.count
        for entry in engine.todayEntries {
            let isNext = entry.id == engine.nextPrayer?.id

            if isNext {
                let plainTitle = "\(entry.prayer.displayName)  \(entry.formattedBeginTime)  (in \(entry.formattedCountdown))"
                let item = NSMenuItem(title: plainTitle, action: #selector(copyPrayerRow(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = Self.rowPayload(for: entry)
                item.attributedTitle = highlightedAttributedString(
                    title: entry.prayer.displayName,
                    time: entry.formattedBeginTime,
                    countdown: entry.formattedCountdown,
                    iqamah: entry.formattedIqamahTime
                )
                item.isEnabled = true
                item.toolTip = Self.rowToolTip(for: entry)
                menu.addItem(item)
            } else {
                let isPassed = entry.hasPassed
                let check = isPassed ? "\u{2713}" : " "
                let iqamahStr = entry.formattedIqamahTime.map { "  Iqamah \($0)" } ?? ""
                let title = " \(check)  \(entry.prayer.displayName.padding(toLength: 10, withPad: " ", startingAt: 0))\(entry.formattedBeginTime)\(iqamahStr)"
                let item = NSMenuItem(title: title, action: #selector(copyPrayerRow(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = Self.rowPayload(for: entry)
                item.isEnabled = true
                item.toolTip = Self.rowToolTip(for: entry)
                menu.addItem(item)
            }
        }

        // Explicit preview — prayer rows are copy-only; target skips sunrise when it is “next”.
        if let previewTarget = previewEntry(for: engine) {
            let preview = NSMenuItem(
                title: "Preview Adhan — \(previewTarget.prayer.displayName)",
                action: #selector(previewAdhanForNextPrayer),
                keyEquivalent: ""
            )
            preview.target = self
            preview.isEnabled = adhanPlayer != nil
            preview.toolTip = "Plays the Adhan sample for this prayer (from Settings recitation)."
            menu.addItem(preview)
        }

        if menu.items.count > timetableMenuInsertIndex {
            menu.addItem(.separator())
        }

        // ── Next Prayer ──
        if let next = engine.nextPrayer {
            let nextLabel = next.isNextDayPreview ? "\(next.prayer.displayName) tomorrow" : next.prayer.displayName
            let countdownItem = NSMenuItem(
                title: "Next: \(nextLabel) in \(next.formattedCountdown)",
                action: #selector(copyMenuItemTitle(_:)),
                keyEquivalent: ""
            )
            countdownItem.target = self
            countdownItem.isEnabled = true
            countdownItem.toolTip = "Copy next-prayer summary to clipboard"
            menu.addItem(countdownItem)
            menu.addItem(.separator())
        }

        // ── Floating Panel ──
        let floatingTitle = (floatingPanel?.isVisible ?? false) ? "Hide Floating Panel" : "Show Floating Panel"
        let floatingItem = NSMenuItem(title: floatingTitle, action: #selector(toggleFloatingPanel), keyEquivalent: "f")
        floatingItem.target = self
        floatingItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(floatingItem)

        // ── Theme ──
        let themeManager = AdhanThemeManager.shared
        let themeItem = NSMenuItem(
            title: "Theme: \(themeManager.current.displayName)",
            action: #selector(cycleTheme),
            keyEquivalent: "k"
        )
        themeItem.target = self
        themeItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(themeItem)

        // ── Display Mode ──
        let currentMode = MenuBarDisplayMode(
            rawValue: UserDefaults.standard.integer(forKey: AppSettings.menuBarDisplayModeKey)
        ) ?? .countdown

        let displayMenu = NSMenu()
        for mode in MenuBarDisplayMode.allCases {
            let modeItem = NSMenuItem(title: mode.label, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.tag = mode.rawValue
            if mode == currentMode { modeItem.state = .on }
            displayMenu.addItem(modeItem)
        }
        let displaySubmenu = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        displaySubmenu.submenu = displayMenu
        menu.addItem(displaySubmenu)

        menu.addItem(.separator())

        let showWindowItem = NSMenuItem(title: "Show Main Window", action: #selector(showMainWindow), keyEquivalent: "o")
        showWindowItem.keyEquivalentModifierMask = .command
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        // ── Settings ──
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // ── Quit ──
        let quitItem = NSMenuItem(title: "Quit Adhan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Attributed String for Next Prayer

    private func highlightedAttributedString(title: String, time: String, countdown: String, iqamah: String?) -> NSAttributedString {
        let str = NSMutableAttributedString()

        str.append(NSAttributedString(string: " \u{25B6}  ", attributes: [
            .foregroundColor: NSColor.systemGreen,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]))

        str.append(NSAttributedString(string: title.padding(toLength: 10, withPad: " ", startingAt: 0), attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]))

        str.append(NSAttributedString(string: time, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        ]))

        str.append(NSAttributedString(string: "  (\(countdown))", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        ]))

        if let iqamah {
            str.append(NSAttributedString(string: "  Iqamah \(iqamah)", attributes: [
                .foregroundColor: NSColor.tertiaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11)
            ]))
        }

        return str
    }

    // MARK: - Row payload (prayer rows)

    /// Next slot that should hear an Adhan preview (when “next” is sunrise, use the following obligatory prayer).
    private func previewEntry(for engine: PrayerTimesEngine) -> PrayerTimeEntry? {
        if let next = engine.nextPrayer, next.prayer != .sunrise { return next }
        return engine.todayEntries.first { $0.isFuture && $0.prayer != .sunrise }
    }

    /// Tab-separated: rawValue, begin HH:mm, optional iqamah HH:mm
    private static func rowPayload(for entry: PrayerTimeEntry) -> String {
        let iq = entry.formattedIqamahTime ?? ""
        return "\(entry.prayer.rawValue)\t\(entry.formattedBeginTime)\t\(iq)"
    }

    private static func parseRowPayload(_ s: String) -> (prayer: PrayerName, begin: String, iqamah: String?)? {
        let parts = s.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let raw = parts.first, let prayer = PrayerName(rawValue: raw) else { return nil }
        let begin = parts.count > 1 ? parts[1] : ""
        let iqamah: String? = {
            guard parts.count > 2, !parts[2].isEmpty else { return nil }
            return parts[2]
        }()
        return (prayer, begin, iqamah)
    }

    private static func rowToolTip(for entry: PrayerTimeEntry) -> String {
        "Copy \(entry.prayer.displayName) time\(entry.formattedIqamahTime.map { ", Iqamah \($0)" } ?? "") to clipboard"
    }

    // MARK: - Actions

    @objc private func showAdhanBuildInfo(_ sender: NSMenuItem?) {
        let alert = NSAlert()
        alert.messageText = "Adhan \(AdhanBuildInfo.versionSummary)"
        let exe = Bundle.main.executablePath ?? "(unknown)"
        let hint: String
        if AdhanBuildInfo.isLikelySwiftPMOrDebugRun {
            hint = """
            This copy is running from a build/debug path (e.g. swift run or Xcode), not the packaged app.

            Quit this instance, then open:
            • /Applications/Adhan.app, or
            • Adhan/build/Adhan.app after ./build-app.sh
            """
        } else {
            hint = "This copy is running from an .app bundle (expected for daily use)."
        }
        alert.informativeText = """
        \(hint)

        Bundle:
        \(AdhanBuildInfo.bundlePath)

        Executable:
        \(exe)
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func copyMenuItemTitle(_ sender: NSMenuItem) {
        let text = sender.title
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Prayer timetable rows: **copy only** (same idea as Hijri / location). Use “Preview Adhan — …” to hear audio.
    @objc private func copyPrayerRow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let parsed = Self.parseRowPayload(raw) else { return }
        copyPrayerTimesLine(prayer: parsed.prayer, begin: parsed.begin, iqamah: parsed.iqamah)
    }

    @objc private func stopAdhanPlayback() {
        adhanPlayer?.stop()
    }

    @objc private func previewAdhanForNextPrayer() {
        guard let engine, let target = previewEntry(for: engine), let player = adhanPlayer else { return }
        let storedId: String?
        if target.prayer == .fajr {
            storedId = UserDefaults.standard.string(forKey: AppSettings.fajrRecitationKey)
        } else {
            storedId = UserDefaults.standard.string(forKey: AppSettings.defaultRecitationKey)
        }
        let recitation = AdhanRecitation.resolveBundled(storedId: storedId, forFajr: target.prayer == .fajr)
        player.play(recitation: recitation)
    }

    private func copyPrayerTimesLine(prayer: PrayerName, begin: String, iqamah: String?) {
        var line = "\(prayer.displayName) begins \(begin)"
        if let iqamah {
            line += ", Iqamah \(iqamah)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }

    @objc private func toggleFloatingPanel() {
        if floatingPanel?.isVisible ?? false {
            floatingPanel?.hide()
        } else {
            floatingPanel?.show()
        }
        buildMenu()
    }

    @objc private func cycleTheme() {
        AdhanThemeManager.shared.cycleTheme()
        buildMenu()
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: AppSettings.menuBarDisplayModeKey)
        updateStatusItem()
        buildMenu()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let openSettingsFromSwiftUI {
            openSettingsFromSwiftUI()
            return
        }
        // Fallbacks when handler not registered yet (e.g. before first window appear).
        let selectors: [Selector] = [
            Selector(("showSettingsWindow:")),
            Selector(("showPreferencesWindow:")),
        ]
        for sel in selectors {
            if NSApp.sendAction(sel, to: nil, from: nil) { return }
        }
    }
}
