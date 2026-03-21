import SwiftUI

struct LoveSettingsView: View {
    var body: some View {
        TabView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        LoveAccentRule(width: 32)
                        Text("Love")
                            .font(LoveTypography.brandTitle)
                        Text("Preferences")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("Sound for capture & complete", isOn: Binding(
                        get: { FeedbackPolicy.soundEnabled },
                        set: { FeedbackPolicy.soundEnabled = $0 }
                    ))
                    Text("Uses named system sounds when available; otherwise a short beep.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Feedback")
                        .font(LoveTypography.sectionHeader)
                }

                Section {
                    LabeledContent("Quick capture") {
                        Text("⌃⌥L")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    Text("Global capture may need Accessibility permission for Love under System Settings → Privacy & Security.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Shortcuts")
                        .font(LoveTypography.sectionHeader)
                }

                Section {
                    Text("Love holds must-dos, one menu bar focus, and a categorized later drawer. Local-only in v1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("About")
                        .font(LoveTypography.sectionHeader)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 480, height: 440)
        .tint(LoveTheme.accent)
        .background(LoveWindowBackdrop())
    }
}
