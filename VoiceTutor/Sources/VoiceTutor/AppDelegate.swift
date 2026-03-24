import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var session: TutorSessionController?
    let menuBarManager = TutorMenuBarManager()
    private var openMainWindowFromSwiftUI: (() -> Void)?

    func attach(session: TutorSessionController) {
        guard self.session == nil else { return }
        self.session = session
        menuBarManager.setup(session: session)
    }

    func configureOpenMainWindow(_ action: @escaping () -> Void) {
        openMainWindowFromSwiftUI = action
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
}
