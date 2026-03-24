import AppKit
import SwiftUI

@main
struct VoiceTutorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = TutorSessionController()

    fileprivate static let mainWindowID = "main"

    var body: some Scene {
        Window("IMI", id: Self.mainWindowID) {
            VoiceTutorRootView(session: session, appDelegate: appDelegate)
        }
        .defaultSize(width: 520, height: 600)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("IMI") {
                Button("Show Main Window") {
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Menu bar must not depend on Window `onAppear` — LSUIElement apps can defer window
        // content until later, which previously left users with no visible UI at all.
        MenuBarExtra("IMI", systemImage: "bubble.left.and.bubble.right.fill") {
            IMIMenuBarExtraRoot(session: session, appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VoiceTutorSettingsView()
        }
    }
}

/// Wires `openWindow` from the menu-bar scene so **Show Main Window** / reopen work even when the
/// main `Window` body never ran `onAppear` (LSUIElement edge case).
private struct IMIMenuBarExtraRoot: View {
    @ObservedObject var session: TutorSessionController
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TutorPopoverView(session: session) {
            appDelegate.showSettings()
        }
        .accessibilityIdentifier("imi.menuBarExtra")
        .onAppear {
            appDelegate.configureOpenMainWindow {
                openWindow(id: VoiceTutorApp.mainWindowID)
            }
            appDelegate.configureOpenSettings {
                openSettings()
            }
        }
    }
}

private struct VoiceTutorRootView: View {
    @ObservedObject var session: TutorSessionController
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VoiceTutorMainView(session: session, openSettingsAction: { appDelegate.showSettings() })
            .onAppear {
                appDelegate.configureOpenMainWindow {
                    openWindow(id: VoiceTutorApp.mainWindowID)
                }
                appDelegate.configureOpenSettings {
                    openSettings()
                }
            }
    }
}
