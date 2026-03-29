import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                        .accessibilityIdentifier("leo.settings.button.general")
                }

            TTSSettingsTab()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                        .accessibilityIdentifier("leo.settings.button.voice")
                }

            AnkiSettingsTab()
                .tabItem {
                    Label("Anki", systemImage: "rectangle.stack.badge.plus")
                        .accessibilityIdentifier("leo.settings.button.anki")
                }

            ReadingSettingsTab()
                .tabItem {
                    Label("Reading", systemImage: "book")
                        .accessibilityIdentifier("leo.settings.button.reading")
                }
        }
        .accessibilityIdentifier("leo.settings.root")
        .frame(width: 520, height: 420)
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("leo.lookupModel") private var lookupModel = "qwen/qwen-2.5-72b-instruct"
    @State private var openRouterKey = ""

    private let secretStore = LeoKeychainHelper()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)
                .accessibilityIdentifier("leo.settings.tab.general")

            Form {
                Section("LLM Contextual Definitions") {
                    SecureField("OpenRouter API Key", text: $openRouterKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openRouterKey) { _, newValue in
                            persistSecret(newValue, for: .openRouter)
                        }
                    TextField("Model", text: $lookupModel)
                        .textFieldStyle(.roundedBorder)
                    Text("Uses OpenRouter over the network. Leave the key empty for CC-CEDICT-only popups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Your API key is stored in the macOS Keychain, not in Leo’s plain settings store.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .task {
            openRouterKey = secretStore.getSecret(for: .openRouter) ?? ""
        }
    }

    private func persistSecret(_ value: String, for key: LeoSecretKey) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secretStore.deleteSecret(for: key)
        } else {
            secretStore.setSecret(trimmed, for: key)
        }
    }
}

struct AnkiSettingsTab: View {
    @Query(sort: \VocabularyEntry.text) private var vocabulary: [VocabularyEntry]
    @State private var lastExportMessage: String?
    @State private var lastImportMessage: String?

    var body: some View {
        Form {
            Section("Import") {
                Button("Import Anki Deck (.apkg)…") {
                    NotificationCenter.default.post(name: .leoImportAnki, object: nil)
                }
                Text("Card states map to Leo familiarity: New → Unknown, Learning → Learning, Young review → Familiar, Mature (≥21 day interval) → Known.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastImportMessage {
                    Text(lastImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Export") {
                Button("Export vocabulary as Anki TSV…") {
                    exportVocabularyTSV()
                }
                .disabled(vocabulary.isEmpty)
                Text("Exports all \(vocabulary.count) saved word\(vocabulary.count == 1 ? "" : "s") as a tab-separated file. Import into Anki via File → Import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastExportMessage {
                    Text(lastExportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .accessibilityIdentifier("leo.settings.tab.anki")
        .onReceive(NotificationCenter.default.publisher(for: .leoAnkiImportResult)) { note in
            lastImportMessage = note.object as? String
        }
    }

    private func exportVocabularyTSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "leo-vocabulary-anki.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let cards = vocabulary.map {
            AnkiExporter.ExportCard(
                word: $0.text,
                pinyin: $0.pinyin,
                definition: $0.definition,
                contextSentence: ""
            )
        }
        do {
            try AnkiExporter().exportCards(cards, to: url)
            lastExportMessage = "Saved \(cards.count) rows."
        } catch {
            lastExportMessage = error.localizedDescription
        }
    }
}

struct TTSSettingsTab: View {
    @AppStorage("leo.ttsPreferSystem") private var preferSystem = true
    @AppStorage("leo.ttsVoice") private var voiceId = "Dennis"
    @AppStorage("leo.ttsModel") private var model = "inworld-tts-1.5-max"
    @AppStorage("leo.ttsSpeed") private var speed = 1.0
    @State private var inworldKey = ""

    private let secretStore = LeoKeychainHelper()

    var body: some View {
        Form {
            Section("Voice output") {
                Toggle("Use macOS voices (free, on-device)", isOn: $preferSystem)
                Text("When off, InWorld is used if an API key is set; otherwise Leo uses macOS speech automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("InWorld TTS (optional)") {
                SecureField("InWorld API Key (Basic auth)", text: $inworldKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: inworldKey) { _, newValue in
                        persistSecret(newValue, for: .inWorld)
                    }
                TextField("Voice ID", text: $voiceId)
                    .textFieldStyle(.roundedBorder)
                Picker("Model", selection: $model) {
                    Text("TTS-1.5 Max (quality)").tag("inworld-tts-1.5-max")
                    Text("TTS-1.5 Mini (speed)").tag("inworld-tts-1.5-mini")
                }
                Slider(value: $speed, in: 0.5...2.0, step: 0.1) {
                    Text("Speed: \(speed, specifier: "%.1f")x")
                }
                Text("InWorld returns word-level timestamps for highlighting. macOS voices also support word-level highlighting via AVSpeechSynthesizer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Leo stores the InWorld key in your macOS Keychain.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .accessibilityIdentifier("leo.settings.tab.voice")
        .task {
            inworldKey = secretStore.getSecret(for: .inWorld) ?? ""
        }
    }

    private func persistSecret(_ value: String, for key: LeoSecretKey) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secretStore.deleteSecret(for: key)
        } else {
            secretStore.setSecret(trimmed, for: key)
        }
    }
}

struct ReadingSettingsTab: View {
    @AppStorage("leo.fontSize") private var fontSize = 18.0
    @AppStorage("leo.lineHeight") private var lineHeight = 1.8
    @AppStorage("leo.showPinyin") private var showPinyin = false
    @AppStorage("leo.showHighlights") private var showHighlights = true
    @AppStorage("leo.textDirection") private var textDirection = "horizontal"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadingPreferencesForm(
                fontSize: $fontSize,
                lineHeight: $lineHeight,
                textDirection: $textDirection,
                showPinyin: $showPinyin,
                showHighlights: $showHighlights
            )
        }
        .padding()
        .accessibilityIdentifier("leo.settings.tab.reading")
    }
}
