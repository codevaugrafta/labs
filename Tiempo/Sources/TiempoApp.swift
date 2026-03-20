import SwiftUI
import SwiftData
import ServiceManagement
import AppKit

@main
struct TiempoApp: App {
    @NSApplicationDelegateAdaptor(TiempoAppDelegate.self) var appDelegate
    @State private var engine = TimeEntryEngine()

    /// Isolated database for Tiempo — not shared with other apps.
    static let modelContainer: ModelContainer = {
        let schema = Schema([
            Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self
        ])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tiempoDir = appSupport.appendingPathComponent("Tiempo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tiempoDir, withIntermediateDirectories: true)

        let storeURL = tiempoDir.appendingPathComponent("Tiempo.store")
        let config = ModelConfiguration("Tiempo", schema: schema, url: storeURL)

        // Tighten file permissions to owner-only (600) after creation
        defer {
            let path = storeURL.path
            if FileManager.default.fileExists(atPath: path) {
                chmod(path, 0o600)
                // Also secure the WAL and SHM files
                chmod(path + "-wal", 0o600)
                chmod(path + "-shm", 0o600)
            }
        }

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create Tiempo database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(engine: engine, appDelegate: appDelegate)
        }
        .modelContainer(Self.modelContainer)
        .commands {
            // Tiempo menu commands — work when app is focused
            CommandGroup(after: .toolbar) {
                Section {
                    Button("Toggle Timer") {
                        if engine.activeEntry != nil {
                            TiempoFeedback.onTimerStop()
                        }
                        engine.toggleCurrentTimer()
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                    Button("Show Floating Timer") {
                        if appDelegate.floatingPanel.isVisible {
                            appDelegate.floatingPanel.hide()
                        } else {
                            appDelegate.floatingPanel.show()
                        }
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    Button("Set Countdown") {
                        appDelegate.floatingPanel.showWithCountdownPicker()
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                    Button("Cycle Theme") {
                        ThemeManager.shared.cycleTheme()
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                }
            }
        }

        Settings {
            SettingsTab(engine: engine)
                .environment(ThemeManager.shared)
        }
    }
}

// MARK: - Bootstrap View (connects modelContext → engine → menu bar)

/// This view exists to bridge SwiftUI's @Environment(\.modelContext)
/// to the engine before ContentView renders, so the menu bar has data.
struct AppBootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    let engine: TimeEntryEngine
    let appDelegate: TiempoAppDelegate

    var body: some View {
        ContentView()
            .environment(engine)
            .environment(ThemeManager.shared)
            .onAppear {
                engine.configure(with: modelContext)
                appDelegate.wireUp(engine: engine)
            }
    }
}

// MARK: - App Delegate (menu bar + floating widget + global hotkey)

@MainActor
class TiempoAppDelegate: NSObject, NSApplicationDelegate {
    let menuBarManager = MenuBarManager()
    let floatingPanel = FloatingTimerPanel()
    private weak var engine: TimeEntryEngine?
    /// Local monitor: SwiftUI `.commands` shortcuts are flaky until menus are used; status-item `NSMenu` shortcuts only work while that menu is open.
    private var keyDownMonitor: Any?

    func wireUp(engine: TimeEntryEngine) {
        guard self.engine == nil else { return }
        self.engine = engine
        menuBarManager.setup(engine: engine, floatingPanel: floatingPanel)
        floatingPanel.setup(engine: engine)
        installLocalKeyboardShortcuts()

        // Auto-show floating timer when a timer starts
        NotificationCenter.default.addObserver(forName: .autoShowFloatingTimer, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if !(self?.floatingPanel.isVisible ?? true) {
                    self?.floatingPanel.show()
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must match LSUIElement in Info.plist — .regular overrides it and forces a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        // Do not activate at launch; menu bar + "Show Main Window" calls activate when needed for focus.
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeLocalKeyboardShortcuts()
    }

    // MARK: - App-wide shortcuts (while Tiempo is the active app)

    private func installLocalKeyboardShortcuts() {
        removeLocalKeyboardShortcuts()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Local monitors run on the thread that received the event (main for UI).
            return self.handleLocalKeyDown(event)
        }
    }

    private func removeLocalKeyboardShortcuts() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    /// Returns `nil` if the event was handled (do not propagate).
    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        // Accessory apps are often not "active" while a window still has key — match Adhan’s guard.
        guard NSApp.isActive || NSApp.keyWindow != nil else { return event }
        if Self.keyWindowHasTextFocus() { return event }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        let ctrlShift: NSEvent.ModifierFlags = [.control, .shift]
        let isCmdShift = mods.intersection(cmdShift) == cmdShift
        let isCtrlShift = mods.intersection(ctrlShift) == ctrlShift

        let code = event.keyCode
        let ch = event.charactersIgnoringModifiers?.lowercased().first

        // Prefer physical key codes: some ⌘⇧ combos report an empty `charactersIgnoringModifiers` (notably K for some layouts/states).
        // US ANSI key codes: F=3, C=8, T=17, K=40.
        let isT = code == 17 || ch == "t"
        let isF = code == 3 || ch == "f"
        let isC = code == 8 || ch == "c"
        let isK = code == 40 || ch == "k"

        // Toggle timer: ⌘⇧T or ⌃⇧T (Settings)
        if isT, isCmdShift || isCtrlShift {
            guard let engine else { return event }
            if engine.activeEntry != nil { TiempoFeedback.onTimerStop() }
            engine.toggleCurrentTimer()
            return nil
        }

        guard isCmdShift else { return event }

        if isF {
            if floatingPanel.isVisible { floatingPanel.hide() } else { floatingPanel.show() }
            return nil
        }
        if isC {
            floatingPanel.showWithCountdownPicker()
            return nil
        }
        if isK {
            ThemeManager.shared.cycleTheme()
            return nil
        }

        return event
    }

    /// Avoid stealing shortcuts while typing in text fields / search.
    private static func keyWindowHasTextFocus() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if current is NSTextView || current is NSTextField { return true }
            responder = current.nextResponder
        }
        return false
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    let engine: TimeEntryEngine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            GeneralSettingsView(engine: engine, launchAtLogin: $launchAtLogin)
                .tabItem { Label("General", systemImage: "gear") }
            ThemeSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettingsView: View {
    let engine: TimeEntryEngine
    @Binding var launchAtLogin: Bool

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }

                Toggle("Allow concurrent timers", isOn: Binding(
                    get: { engine.allowConcurrentTimers },
                    set: { engine.allowConcurrentTimers = $0 }
                ))
            }

            Section("Keyboard shortcuts") {
                Text("While Tiempo is the active app: ⌘⇧T or ⌃⇧T — stop active timer · ⌘⇧F — floating timer · ⌘⇧C — countdown · ⌘⇧K — cycle theme. From another app, use the Dock or click the menu bar timer; there is no global hotkey.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

struct ThemeSettingsView: View {
    var body: some View {
        Form {
            Section("Theme") {
                let entries = ThemeManager.themeEntries
                let currentId = ThemeManager.shared.current.id
                ForEach(entries) { entry in
                    ThemeRow(entry: entry, isSelected: entry.id == currentId)
                }
            }

            Section("Auto Schedule") {
                let autoEnabled = ThemeManager.shared.autoScheduleEnabled
                Toggle("Switch themes by time of day", isOn: Binding(
                    get: { ThemeManager.shared.autoScheduleEnabled },
                    set: { ThemeManager.shared.autoScheduleEnabled = $0 }
                ))

                if autoEnabled {
                    ForEach(Array(ThemeManager.defaultSchedule.enumerated()), id: \.offset) { _, rule in
                        let themeName = ThemeManager.allThemes.first { $0.id == rule.themeId }?.displayName ?? rule.themeId
                        HStack {
                            Text(themeName)
                                .font(.caption)
                            Spacer()
                            Text("\(rule.startHour):00 – \(rule.endHour):00")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Feedback") {
                Toggle("Sound effects", isOn: Binding(
                    get: { ThemeManager.shared.feedbackSoundEnabled },
                    set: { ThemeManager.shared.feedbackSoundEnabled = $0 }
                ))
                Toggle("Haptic feedback (trackpad)", isOn: Binding(
                    get: { ThemeManager.shared.feedbackHapticEnabled },
                    set: { ThemeManager.shared.feedbackHapticEnabled = $0 }
                ))
                Text("Timer start/stop, countdown complete, and theme switches. Sounds use macOS system alerts (check Sound in System Settings). Haptics need a Magic Trackpad or built-in trackpad with haptics enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ThemeRow: View {
    let entry: ThemeManager.ThemeEntry
    let isSelected: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(entry.accent)
                .frame(width: 12, height: 12)
            Text(entry.name)
                .font(.body)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ThemeManager.shared.setTheme(entry.id)
        }
        .padding(.vertical, 2)
    }
}
