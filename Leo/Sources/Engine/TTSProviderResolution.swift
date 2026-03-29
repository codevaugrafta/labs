import Foundation

/// Which backend supplies Read aloud audio.
enum LeoTTSBackend: String, Sendable, Equatable {
    /// InWorld REST API (word timestamps when available).
    case inWorld
    /// macOS `AVSpeechSynthesizer` (free, on-device; word range via `willSpeakRangeOfSpeechString`).
    case systemSpeech
}

enum TTSProviderResolution {
    /// - Parameters:
    ///   - hasInWorldKey: Non-empty API key from env or Leo's Keychain-backed settings.
    ///   - preferSystem: When `true`, use system speech even if InWorld is configured.
    static func resolveBackend(hasInWorldKey: Bool, preferSystem: Bool) -> LeoTTSBackend {
        if preferSystem { return .systemSpeech }
        if hasInWorldKey { return .inWorld }
        return .systemSpeech
    }
}
