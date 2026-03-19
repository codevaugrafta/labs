import SwiftUI
import KeyboardShortcuts
import ApplicationServices

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    // Local copies of keychain values — updated on appear and committed on change.
    @State private var inworldKey = ""
    @State private var elevenlabsKey = ""
    @State private var geminiKey = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            voicesTab
                .tabItem { Label("Voices", systemImage: "waveform") }

            apiKeysTab
                .tabItem { Label("API Keys", systemImage: "key") }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            inworldKey = KeychainHelper.getKey(for: .inworld) ?? ""
            elevenlabsKey = KeychainHelper.getKey(for: .elevenlabs) ?? ""
            geminiKey = KeychainHelper.getKey(for: .gemini) ?? ""
        }
    }

    // MARK: - Tabs

    var generalTab: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Speak Selection:", name: .speakSelection)
                KeyboardShortcuts.Recorder("Repeat Last:", name: .repeatLast)
            }

            Section("Provider") {
                Picker("Default TTS Provider", selection: $settings.currentProvider) {
                    ForEach(TTSProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Accessibility") {
                AccessibilityStatusRow()
            }
        }
        .padding()
    }

    var voicesTab: some View {
        Form {
            Section("Voice Configuration") {
                ForEach($settings.voiceConfigs) { $config in
                    HStack {
                        Text(languageName(config.language))
                            .frame(width: 100, alignment: .leading)

                        TextField("Voice ID", text: $config.voiceId)
                            .textFieldStyle(.roundedBorder)

                        Picker("", selection: $config.provider) {
                            ForEach(TTSProviderType.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .frame(width: 120)
                    }
                }

                Button("Add Language") {
                    settings.voiceConfigs.append(
                        VoiceConfig(
                            language: "new",
                            provider: settings.currentProvider,
                            voiceId: "default",
                            voiceName: "New Voice"
                        )
                    )
                }
            }
        }
        .padding()
    }

    var apiKeysTab: some View {
        Form {
            Section("API Keys") {
                LabeledContent("Inworld") {
                    SecureField("Paste API key…", text: $inworldKey)
                        .onChange(of: inworldKey) { _, newValue in
                            KeychainHelper.setKey(newValue, for: .inworld)
                        }
                }

                LabeledContent("ElevenLabs") {
                    SecureField("Paste API key…", text: $elevenlabsKey)
                        .onChange(of: elevenlabsKey) { _, newValue in
                            KeychainHelper.setKey(newValue, for: .elevenlabs)
                        }
                }

                LabeledContent("Gemini") {
                    SecureField("Paste API key…", text: $geminiKey)
                        .onChange(of: geminiKey) { _, newValue in
                            KeychainHelper.setKey(newValue, for: .gemini)
                        }
                }
            }

            Section {
                Text("API keys are stored securely in your macOS Keychain and never leave this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func languageName(_ code: String) -> String {
        Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: - Accessibility status row

/// Extracted into its own view so the trusted check runs in a fresh render cycle.
private struct AccessibilityStatusRow: View {
    var body: some View {
        let trusted = AXIsProcessTrusted()
        HStack {
            Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(trusted ? .green : .orange)
            Text(trusted ? "Accessibility access granted" : "Accessibility access required")
            Spacer()
            if !trusted {
                Button("Open Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
#endif
