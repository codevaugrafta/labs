import SwiftUI
import SwiftData
import ServiceManagement

@main
struct TiempoApp: App {
    @NSApplicationDelegateAdaptor(TiempoAppDelegate.self) var appDelegate
    @State private var engine = TimeEntryEngine()

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(engine: engine, appDelegate: appDelegate)
        }
        .modelContainer(for: [
            Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self
        ])

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
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var engine: TimeEntryEngine?

    func wireUp(engine: TimeEntryEngine) {
        guard self.engine == nil else { return } // Only once
        self.engine = engine
        menuBarManager.setup(engine: engine, floatingPanel: floatingPanel)
        floatingPanel.setup(engine: engine)
        registerGlobalHotkey()

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
        // Make the app a proper foreground application so text fields receive keyboard focus
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    private func registerGlobalHotkey() {
        // Request Accessibility permission — required for global key monitoring.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            print("Tiempo: Grant Accessibility permission in System Settings → Privacy & Security → Accessibility for global hotkeys.")
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Ctrl+Shift+T — Toggle active timer
            if mods == [.control, .shift] && event.keyCode == 17 { // 't'
                Task { @MainActor in
                    if self?.engine?.activeEntry != nil {
                        TiempoFeedback.onTimerStop()
                    }
                    self?.engine?.toggleCurrentTimer()
                }
            }

            // Ctrl+Shift+F — Toggle floating timer panel
            if mods == [.control, .shift] && event.keyCode == 3 { // 'f'
                Task { @MainActor in
                    if self?.floatingPanel.isVisible ?? false {
                        self?.floatingPanel.hide()
                    } else {
                        self?.floatingPanel.show()
                    }
                }
            }

            // Ctrl+Shift+C — Open countdown picker
            if mods == [.control, .shift] && event.keyCode == 8 { // 'c'
                Task { @MainActor in
                    self?.floatingPanel.showWithCountdownPicker()
                }
            }
        }

        // Local monitor — works when Tiempo is the active app (no Accessibility needed)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if mods == [.control, .shift] && event.keyCode == 17 {
                Task { @MainActor in
                    if self?.engine?.activeEntry != nil { TiempoFeedback.onTimerStop() }
                    self?.engine?.toggleCurrentTimer()
                }
                return nil // Consume the event
            }
            if mods == [.control, .shift] && event.keyCode == 3 {
                Task { @MainActor in
                    if self?.floatingPanel.isVisible ?? false { self?.floatingPanel.hide() }
                    else { self?.floatingPanel.show() }
                }
                return nil
            }
            if mods == [.control, .shift] && event.keyCode == 8 {
                Task { @MainActor in
                    self?.floatingPanel.showWithCountdownPicker()
                }
                return nil
            }
            return event // Pass through other events
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    let engine: TimeEntryEngine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var themeManager = ThemeManager.shared

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

            Section("Global Shortcut") {
                Text("Ctrl+Shift+T — Toggle active timer")
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
                    ForEach(ThemeManager.defaultSchedule, id: \.themeId) { rule in
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
                Toggle("Sound effects", isOn: .constant(true))
                Toggle("Haptic feedback (trackpad)", isOn: .constant(true))
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
