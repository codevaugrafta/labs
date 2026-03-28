import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TTSSettingsTab()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }

            ReadingSettingsTab()
                .tabItem {
                    Label("Reading", systemImage: "book")
                }
        }
        .frame(width: 500, height: 380)
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("leo.openRouterApiKey") private var openRouterKey = ""
    @AppStorage("leo.lookupModel") private var lookupModel = "qwen/qwen-2.5-72b-instruct"

    var body: some View {
        Form {
            Section("LLM Contextual Definitions") {
                SecureField("OpenRouter API Key", text: $openRouterKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $lookupModel)
                    .textFieldStyle(.roundedBorder)
                Text("Used for context-aware word definitions. Leave empty to use CC-CEDICT only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct TTSSettingsTab: View {
    @AppStorage("leo.inworldApiKey") private var inworldKey = ""
    @AppStorage("leo.ttsVoice") private var voiceId = "Dennis"
    @AppStorage("leo.ttsModel") private var model = "inworld-tts-1.5-max"
    @AppStorage("leo.ttsSpeed") private var speed = 1.0

    var body: some View {
        Form {
            Section("InWorld TTS") {
                SecureField("InWorld API Key (Basic auth)", text: $inworldKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Voice ID", text: $voiceId)
                    .textFieldStyle(.roundedBorder)
                Picker("Model", selection: $model) {
                    Text("TTS-1.5 Max (quality)").tag("inworld-tts-1.5-max")
                    Text("TTS-1.5 Mini (speed)").tag("inworld-tts-1.5-mini")
                }
                Slider(value: $speed, in: 0.5...2.0, step: 0.1) {
                    Text("Speed: \(speed, specifier: "%.1f")x")
                }
            }

            Section("Fallback") {
                Text("Azure/Edge TTS is available as a free fallback when InWorld is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct ReadingSettingsTab: View {
    @AppStorage("leo.fontSize") private var fontSize = 18.0
    @AppStorage("leo.lineHeight") private var lineHeight = 1.8
    @AppStorage("leo.showPinyin") private var showPinyin = false
    @AppStorage("leo.showHighlights") private var showHighlights = true
    @AppStorage("leo.textDirection") private var textDirection = "horizontal"

    var body: some View {
        Form {
            Section("Typography") {
                Slider(value: $fontSize, in: 14...28, step: 1) {
                    Text("Font size: \(Int(fontSize))pt")
                }
                Slider(value: $lineHeight, in: 1.2...2.5, step: 0.1) {
                    Text("Line height: \(lineHeight, specifier: "%.1f")")
                }
                Picker("Text direction", selection: $textDirection) {
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
            }

            Section("Display") {
                Toggle("Show pinyin above characters", isOn: $showPinyin)
                Toggle("Show familiarity highlights", isOn: $showHighlights)
            }
        }
        .padding()
    }
}
