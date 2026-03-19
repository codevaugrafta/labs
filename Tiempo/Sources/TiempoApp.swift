import SwiftUI
import SwiftData
import ServiceManagement

@main
struct TiempoApp: App {
    @NSApplicationDelegateAdaptor(TiempoAppDelegate.self) var appDelegate
    @State private var engine = TimeEntryEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .onAppear {
                    appDelegate.wireUp(engine: engine)
                }
        }
        .modelContainer(for: [
            Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self
        ])

        Settings {
            SettingsTab(engine: engine)
        }
    }
}

// MARK: - App Delegate (menu bar + floating widget + global hotkey)

@MainActor
class TiempoAppDelegate: NSObject, NSApplicationDelegate {
    let menuBarManager = MenuBarManager()
    let floatingPanel = FloatingTimerPanel()
    private var globalMonitor: Any?
    private weak var engine: TimeEntryEngine?

    func wireUp(engine: TimeEntryEngine) {
        guard self.engine == nil else { return } // Only once
        self.engine = engine
        menuBarManager.setup(engine: engine)
        floatingPanel.setup(engine: engine)
        registerGlobalHotkey()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar is set up when engine is wired
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func registerGlobalHotkey() {
        // Default: Ctrl+Shift+T to toggle timer
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Ctrl+Shift+T
            if event.modifierFlags.contains([.control, .shift]) && event.keyCode == 17 { // 17 = 't'
                Task { @MainActor in
                    self?.engine?.toggleCurrentTimer()
                }
            }
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    let engine: TimeEntryEngine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                            launchAtLogin = !newValue // Revert on failure
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
        .frame(width: 400, height: 250)
    }
}
