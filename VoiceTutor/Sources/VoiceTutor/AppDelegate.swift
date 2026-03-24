import AppKit
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.franciscodilussor.voicetutor", category: "app")

    private var openMainWindowFromSwiftUI: (() -> Void)?
    private var openSettingsFromSwiftUI: (() -> Void)?
    private var fallbackSettingsWindow: NSWindow?

    func configureOpenMainWindow(_ action: @escaping () -> Void) {
        openMainWindowFromSwiftUI = action
    }

    /// Capture `EnvironmentValues.openSettings` from any SwiftUI root that receives it (main `Window`
    /// and `MenuBarExtra`). `NSApp.sendAction(showSettingsWindow:)` often has **no responder** for
    /// LSUIElement apps, so this closure is the primary path.
    func configureOpenSettings(_ action: @escaping () -> Void) {
        openSettingsFromSwiftUI = action
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowFromSwiftUI?()
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let openSettingsFromSwiftUI {
            openSettingsFromSwiftUI()
            return
        }

        let ok = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: NSApp)
        if ok {
            return
        }

        Self.log.notice("showSettingsWindow: had no responder; using fallback settings window")
        presentFallbackSettingsWindowIfNeeded()
    }

    private func presentFallbackSettingsWindowIfNeeded() {
        if fallbackSettingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "IMI Settings"
            w.isReleasedWhenClosed = false
            w.center()
            let host = NSHostingView(rootView: VoiceTutorSettingsView())
            host.autoresizingMask = [.width, .height]
            w.contentView = host
            fallbackSettingsWindow = w
        }
        fallbackSettingsWindow?.makeKeyAndOrderFront(nil)
    }
}
