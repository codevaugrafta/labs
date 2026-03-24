import AppKit
import SwiftUI

@main
struct VoiceTutorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = TutorSessionController()

    fileprivate static let mainWindowID = "main"

    var body: some Scene {
        Window("Voice Tutor", id: Self.mainWindowID) {
            VoiceTutorRootView(session: session, appDelegate: appDelegate)
        }
        .defaultSize(width: 520, height: 600)
        .commands {
            CommandMenu("Voice Tutor") {
                Button("Show Main Window") {
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            VoiceTutorSettingsView()
        }
    }
}

private struct VoiceTutorRootView: View {
    @ObservedObject var session: TutorSessionController
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VoiceTutorMainView(session: session)
            .onAppear {
                appDelegate.attach(session: session)
                appDelegate.configureOpenMainWindow {
                    openWindow(id: VoiceTutorApp.mainWindowID)
                }
            }
    }
}
