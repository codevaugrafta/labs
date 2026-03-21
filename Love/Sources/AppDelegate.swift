import AppKit
import SwiftData
import SwiftUI

@MainActor
final class LoveAppDelegate: NSObject, NSApplicationDelegate {
    let menuBarManager = MenuBarManager()
    private weak var engine: LoveEngine?
    private var modelContainer: ModelContainer?
    private var quickCaptureController: QuickCapturePanelController?
    private var globalKeyMonitor: Any?
    private var localObservers: [NSObjectProtocol] = []

    func wireUp(engine: LoveEngine, modelContainer: ModelContainer) {
        guard self.engine == nil else { return }
        self.engine = engine
        self.modelContainer = modelContainer
        menuBarManager.setup(engine: engine)

        localObservers.append(
            NotificationCenter.default.addObserver(forName: .loveDataDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.menuBarManager.refresh()
                }
            }
        )
        localObservers.append(
            NotificationCenter.default.addObserver(forName: .loveQuickCapture, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.presentQuickCapture()
                }
            }
        )
        localObservers.append(
            NotificationCenter.default.addObserver(forName: .loveShowMainWindow, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.isVisible && !(window is NSPanel) && window.canBecomeKey {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            }
        )

        installGlobalCaptureShortcut()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeGlobalCaptureShortcut()
        for obs in localObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        localObservers.removeAll()
    }

    private func installGlobalCaptureShortcut() {
        removeGlobalCaptureShortcut()
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let need: NSEvent.ModifierFlags = [.control, .option]
            guard mods.intersection(need) == need else { return }
            let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard ch == "l" else { return }
            Task { @MainActor in
                NotificationCenter.default.post(name: .loveQuickCapture, object: nil)
            }
        }
    }

    private func removeGlobalCaptureShortcut() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func presentQuickCapture() {
        guard let engine, let modelContainer else { return }
        if quickCaptureController == nil {
            quickCaptureController = QuickCapturePanelController(modelContainer: modelContainer, engine: engine)
        }
        quickCaptureController?.show()
    }
}
