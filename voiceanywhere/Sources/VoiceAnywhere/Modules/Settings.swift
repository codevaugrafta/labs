import Foundation
import SwiftUI

// MARK: - Provider type

enum TTSProviderType: String, CaseIterable, Codable {
    case inworld = "inworld"
    case elevenlabs = "elevenlabs"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .inworld: return "Inworld"
        case .elevenlabs: return "ElevenLabs"
        case .gemini: return "Gemini"
        }
    }
}

// MARK: - Voice configuration

struct VoiceConfig: Codable, Identifiable {
    var id: String { "\(language)-\(provider.rawValue)" }
    var language: String
    var provider: TTSProviderType
    var voiceId: String
    var voiceName: String
}

// MARK: - App settings

class AppSettings: ObservableObject {
    @Published var currentProvider: TTSProviderType {
        didSet {
            UserDefaults.standard.set(currentProvider.rawValue, forKey: Keys.currentProvider)
        }
    }

    @Published var voiceConfigs: [VoiceConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(voiceConfigs) {
                UserDefaults.standard.set(data, forKey: Keys.voiceConfigs)
            }
        }
    }

    // MARK: Init

    init() {
        let providerStr = UserDefaults.standard.string(forKey: Keys.currentProvider) ?? TTSProviderType.inworld.rawValue
        self.currentProvider = TTSProviderType(rawValue: providerStr) ?? .inworld

        if let data = UserDefaults.standard.data(forKey: Keys.voiceConfigs),
           let configs = try? JSONDecoder().decode([VoiceConfig].self, from: data) {
            self.voiceConfigs = configs
        } else {
            self.voiceConfigs = Self.defaultVoiceConfigs
        }
    }

    // MARK: - Lookup

    /// Returns the best matching voice for `language` using the current provider,
    /// falling back to any voice for that language, then to English.
    func voiceForLanguage(_ language: String) -> VoiceConfig {
        if let config = voiceConfigs.first(where: {
            $0.language == language && $0.provider == currentProvider
        }) {
            return config
        }

        if let config = voiceConfigs.first(where: { $0.language == language }) {
            return config
        }

        return voiceConfigs.first ?? VoiceConfig(
            language: "en",
            provider: currentProvider,
            voiceId: "default",
            voiceName: "Default"
        )
    }

    // MARK: - Defaults

    private static let defaultVoiceConfigs: [VoiceConfig] = [
        VoiceConfig(language: "en", provider: .inworld, voiceId: "default", voiceName: "Default English"),
        VoiceConfig(language: "ar", provider: .inworld, voiceId: "default", voiceName: "Default Arabic"),
        VoiceConfig(language: "es", provider: .inworld, voiceId: "default", voiceName: "Default Spanish"),
        VoiceConfig(language: "fr", provider: .inworld, voiceId: "default", voiceName: "Default French"),
    ]

    private enum Keys {
        static let currentProvider = "currentProvider"
        static let voiceConfigs = "voiceConfigs"
    }
}
