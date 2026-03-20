import SwiftUI
import SwiftData
import ServiceManagement
import AppKit

@main
struct AdhanApp: App {
    @NSApplicationDelegateAdaptor(AdhanAppDelegate.self) var appDelegate
    @State private var engine = PrayerTimesEngine()

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(engine: engine, appDelegate: appDelegate)
        }
        .defaultSize(width: 520, height: 680)
        .modelContainer(for: [PrayerDay.self])
        .commands {
            CommandGroup(after: .toolbar) {
                Section {
                    Button("Show Main Window") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
                    }
                    .keyboardShortcut("o", modifiers: [.command])

                    Button("Show Floating Panel") {
                        if appDelegate.floatingPanel.isVisible {
                            appDelegate.floatingPanel.hide()
                        } else {
                            appDelegate.floatingPanel.show()
                        }
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    Button("Stop Adhan") {
                        appDelegate.adhanPlayer.stop()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Button("Cycle Theme") {
                        AdhanThemeManager.shared.cycleTheme()
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])

                    Button("Recalculate Prayer Times") {
                        engine.recalculate()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
        }

        Settings {
            SettingsView()
                .environment(engine)
                .environment(\.adhanPlayer, appDelegate.adhanPlayer)
        }
    }
}

// MARK: - Bootstrap View

struct AppBootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    let engine: PrayerTimesEngine
    let appDelegate: AdhanAppDelegate

    var body: some View {
        ContentView()
            .environment(engine)
            .onAppear {
                let mosqueCache = MosqueCacheManager()
                mosqueCache.configure(with: modelContext)
                engine.configure(mosqueCache: mosqueCache)
                appDelegate.wireUp(engine: engine)
                // Menu bar "Settings…" / ⌘, must use SwiftUI’s settings action (private selectors fail from NSStatusItem).
                appDelegate.menuBarManager.configureOpenSettings { openSettings() }

                // Auto-fetch mosque times on launch
                Task {
                    await engine.fetchMosqueTimes()
                }
            }
    }
}

// MARK: - App Delegate

@MainActor
class AdhanAppDelegate: NSObject, NSApplicationDelegate {
    let menuBarManager = MenuBarManager()
    let floatingPanel = FloatingPrayerPanel()
    let adhanPlayer = AdhanPlayer()
    let prayerScheduler = PrayerScheduler()
    let notificationScheduler = NotificationScheduler()
    private weak var engine: PrayerTimesEngine?
    private var midnightTimer: Timer?
    /// Local monitor: SwiftUI `.commands` shortcuts are unreliable for accessory / menu-bar-first apps.
    private var keyDownMonitor: Any?

    func wireUp(engine: PrayerTimesEngine) {
        guard self.engine == nil else { return }
        self.engine = engine
        menuBarManager.setup(engine: engine, floatingPanel: floatingPanel, adhanPlayer: adhanPlayer)
        floatingPanel.setup(engine: engine)
        installLocalKeyboardShortcuts()

        // Wire scheduler
        prayerScheduler.engine = engine
        prayerScheduler.adhanPlayer = adhanPlayer
        prayerScheduler.onPrayerTime = { [weak self] _ in
            // Refresh pending UN notifications for the rest of the day (audio is primary).
            self?.notificationScheduler.scheduleAll()
        }
        prayerScheduler.start()

        // Schedule notifications
        notificationScheduler.setup(engine: engine)
        notificationScheduler.scheduleAll()

        // Schedule midnight re-sync for next day's times
        scheduleMidnightRefresh()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular activation so the app can become key/main, SwiftUI menu commands work, and the local
        // key monitor runs while a window or panel is focused (accessory + isActive stays false too often).
        NSApp.setActivationPolicy(.regular)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeLocalKeyboardShortcuts()
        prayerScheduler.stop()
        adhanPlayer.stopImmediately()
        midnightTimer?.invalidate()
    }

    // MARK: - Keyboard shortcuts (while Adhan is active)

    private func installLocalKeyboardShortcuts() {
        removeLocalKeyboardShortcuts()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event)
        }
    }

    private func removeLocalKeyboardShortcuts() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        // Accept when any of our windows is key (covers regular app + edge cases where isActive lags).
        guard NSApp.isActive || NSApp.keyWindow != nil else { return event }
        if Self.keyWindowHasTextFocus() { return event }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        let isCmdShift = mods.intersection(cmdShift) == cmdShift
        let isCmdOnly = mods.contains(.command) && !mods.contains(.shift) && !mods.contains(.option) && !mods.contains(.control)

        let code = event.keyCode
        let ch = event.charactersIgnoringModifiers?.lowercased().first

        let isO = code == 31 || ch == "o"
        let isF = code == 3 || ch == "f"
        let isS = code == 1 || ch == "s"
        let isK = code == 40 || ch == "k"
        let isR = code == 15 || ch == "r"

        if isO, isCmdOnly {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
            return nil
        }

        guard isCmdShift else { return event }

        if isF {
            if floatingPanel.isVisible { floatingPanel.hide() } else { floatingPanel.show() }
            return nil
        }
        if isS {
            adhanPlayer.stop()
            return nil
        }
        if isK {
            AdhanThemeManager.shared.cycleTheme()
            return nil
        }
        if isR {
            engine?.recalculate()
            return nil
        }

        return event
    }

    private static func keyWindowHasTextFocus() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if current is NSTextView || current is NSTextField { return true }
            responder = current.nextResponder
        }
        return false
    }

    // MARK: - Midnight Refresh

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()

        // Calculate seconds until next midnight + 10 seconds buffer
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) else { return }
        let interval = tomorrow.timeIntervalSinceNow + 10

        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let engine = self.engine else { return }

                // Recalculate for the new day
                engine.recalculate()

                // Re-fetch mosque times before alarms/notifications so schedules use fresh cache.
                await engine.fetchMosqueTimes()

                // Reschedule prayer alarms and notifications
                self.prayerScheduler.reschedule()
                self.notificationScheduler.scheduleAll()

                // Schedule next midnight refresh
                self.scheduleMidnightRefresh()
            }
        }
    }
}
