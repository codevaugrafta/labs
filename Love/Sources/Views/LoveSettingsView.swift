import SwiftUI

struct LoveSettingsView: View {
    var body: some View {
        TabView {
            Form {
                Section("Feedback") {
                    Toggle("Sound for capture & complete", isOn: Binding(
                        get: { FeedbackPolicy.soundEnabled },
                        set: { FeedbackPolicy.soundEnabled = $0 }
                    ))
                    Text("Uses named system sounds when available; otherwise a short beep.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Shortcuts") {
                    LabeledContent("Quick capture") {
                        Text("⌃⌥L")
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("Global capture needs Accessibility permission for Love in System Settings → Privacy & Security, if macOS prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Love keeps must-dos, one menu bar focus, and a categorized later drawer. Local-only in v1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 420, height: 320)
    }
}
