import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarManager: NSObject {
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setup(engine: PrayerTimesEngine, floatingPanel: FloatingPrayerPanel? = nil, adhanPlayer: AdhanPlayer? = nil) {
        self.engine = engine
        self.floatingPanel = floatingPanel
        self.adhanPlayer = adhanPlayer
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarNeedsRebuildNotification),
            name: .adhanMenuBarNeedsRebuild,
            object: nil
        )
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

    @objc private func handleMenuBarNeedsRebuildNotification() {
        // Selector-based observers run on the posting thread; AppKit menu work must be main-thread.
        Task { @MainActor in
            self.buildMenu()
            self.applyStatusButtonToolTip()
        }
    }

    // MARK: - Status Item Update

    /// Menu bar uses `menuBarCountdownEntry()` so after Adhan it can count down to **Iqamah** before the next begin time.
    private func menuBarRowMatchesFocus(_ entry: PrayerTimeEntry, focus: PrayerTimeEntry?) -> Bool {
        guard let focus else { return false }
        if focus.isMenuBarIqamahPhase {
            return entry.prayer == focus.prayer && !entry.isNextDayPreview
        }
        return entry.id == focus.id
    }

    private func menuBarStatusButtonTitle(focus: PrayerTimeEntry, mode: MenuBarDisplayMode) -> String {
        let label: String = {
            if focus.isNextDayPreview { return "\(focus.prayer.displayName) (tmrw)" }
            return focus.prayer.displayName
        }()
        switch mode {
        case .countdown:
            if focus.isMenuBarIqamahPhase {
                return " \(label) Iqamah in \(focus.formattedCountdown)"
            }
            return " \(label) in \(focus.formattedCountdown)"
        case .exactTime:
            if focus.isMenuBarIqamahPhase {
                return " \(label) Iqamah \(focus.formattedBeginTime)"
            }
            return " \(label) \(focus.formattedBeginTime)"
        case .iconOnly:
            return ""
        }
    }

    /// Countdown shown in the highlighted timetable row (Iqamah phase → time until congregation).
    private func menuBarRowCountdownLabel(entry: PrayerTimeEntry, focus: PrayerTimeEntry?) -> String {
        if menuBarRowMatchesFocus(entry, focus: focus), let toIqamah = entry.formattedCountdownToIqamah() {
            return toIqamah
        }
        return entry.formattedCountdown
    }

    private func updateStatusItem() {
        guard let statusItem, let engine else { return }
        let button = statusItem.button

        let displayMode = MenuBarDisplayMode(
            rawValue: UserDefaults.standard.integer(forKey: AppSettings.menuBarDisplayModeKey)
        ) ?? .countdown

        let focus = engine.menuBarCountdownEntry()

        switch displayMode {
        case .countdown, .exactTime:
            if let focus {
                button?.title = menuBarStatusButtonTitle(focus: focus, mode: displayMode)
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

        // Rebuild menu when menu-bar focus or playback changes (Stop Adhan enabled state, labels).
        let currentFocusId = focus?.id
        let playing = adhanPlayer?.isPlaying ?? false
        if currentFocusId != lastNextPrayerId || playing != lastAdhanPlaying {
            lastNextPrayerId = currentFocusId
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
        statusItem?.button?.toolTip = "Adhan — click for menu and actions. Version is in Settings → General."
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        guard let statusItem, let engine else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        func appendSeparatorIfNeeded() {
            guard let last = menu.items.last, !last.isSeparatorItem else { return }
            menu.addItem(.separator())
        }

        let showHijri = AppSettings.menuBarShowsHijriDate()
        let showLocation = AppSettings.menuBarShowsLocation()
        let showTimetable = AppSettings.menuBarShowsPrayerTimetable()

        // ── Hijri / location (optional; copy to clipboard)
        if showHijri {
            let hijriItem = NSMenuItem(title: "\u{263D} \(engine.hijriEngine.hijriDateString)", action: #selector(copyMenuItemTitle(_:)), keyEquivalent: "")
            hijriItem.target = self
            hijriItem.isEnabled = true
            hijriItem.toolTip = "Copy Hijri date to clipboard"
            menu.addItem(hijriItem)
        }
        if showLocation {
            let locationItem = NSMenuItem(title: "\u{1F4CD} \(engine.locationName)", action: #selector(copyMenuItemTitle(_:)), keyEquivalent: "")
            locationItem.target = self
            locationItem.isEnabled = true
            locationItem.toolTip = "Copy location name to clipboard"
            menu.addItem(locationItem)
        }
        if showHijri || showLocation {
            appendSeparatorIfNeeded()
        }

        // ── Stop playback (⌘⇧S) ──
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

        // ── Prayer timetable (optional) ──
        let timetableMenuInsertIndex = menu.items.count
        if showTimetable {
            appendSeparatorIfNeeded()

            let menuFocus = engine.menuBarCountdownEntry()

            for entry in engine.todayEntries {
                let isNext = menuBarRowMatchesFocus(entry, focus: menuFocus)
                let rowCountdown = menuBarRowCountdownLabel(entry: entry, focus: menuFocus)

                if isNext {
                    let plainTitle = "\(entry.prayer.displayName)  \(entry.formattedBeginTime)  (in \(rowCountdown))"
                    let item = NSMenuItem(title: plainTitle, action: #selector(copyPrayerRow(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = Self.rowPayload(for: entry)
                    item.attributedTitle = highlightedAttributedString(
                        title: entry.prayer.displayName,
                        time: entry.formattedBeginTime,
                        countdown: rowCountdown,
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
                appendSeparatorIfNeeded()
            }

            // ── Next Prayer summary (only with timetable section) ──
            if let focus = engine.menuBarCountdownEntry() {
                let nameLabel = focus.isNextDayPreview ? "\(focus.prayer.displayName) tomorrow" : focus.prayer.displayName
                let (heading, detail): (String, String) = focus.isMenuBarIqamahPhase
                    ? ("Iqamah", "\(nameLabel) in \(focus.formattedCountdown)")
                    : ("Next", "\(nameLabel) in \(focus.formattedCountdown)")
                let countdownItem = NSMenuItem(
                    title: "\(heading): \(detail)",
                    action: #selector(copyMenuItemTitle(_:)),
                    keyEquivalent: ""
                )
                countdownItem.target = self
                countdownItem.isEnabled = true
                countdownItem.toolTip = focus.isMenuBarIqamahPhase
                    ? "Copy menu bar countdown summary (Iqamah phase)"
                    : "Copy next-prayer summary to clipboard"
                menu.addItem(countdownItem)
            }
        }

        appendSeparatorIfNeeded()

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

        appendSeparatorIfNeeded()

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
