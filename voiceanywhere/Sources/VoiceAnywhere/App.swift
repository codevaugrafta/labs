import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let speakSelection = Self("speakSelection", default: .init(.s, modifiers: [.option]))
    static let repeatLast = Self("repeatLast", default: .init(.r, modifiers: [.option]))
}

@main
struct VoiceAnywhereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
        }
    }
}
