import Foundation

/// Which backend supplies Read aloud audio.
enum LeoTTSBackend: String, Sendable, Equatable {
    /// On-device Qwen3-TTS via MLX + ForcedAligner for word timestamps. Apple Silicon only.
    case qwen3
    /// InWorld REST API (word timestamps when available).
    case inWorld
    /// Fish Audio REST API (streaming TTS, no word timestamps).
    case fishAudio
    /// macOS `AVSpeechSynthesizer` (free, on-device; word range via `willSpeakRangeOfSpeechString`).
    case systemSpeech
}

enum TTSProviderResolution {
    /// Returns `true` when the process is running on Apple Silicon — Qwen3/MLX requires it.
    static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { rawPtr -> String in
            let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine.hasPrefix("arm")
    }

    /// Resolve the best available TTS backend given the current configuration.
    ///
    /// Priority (when `preferSystem` is false): qwen3 > inWorld > fishAudio > systemSpeech
    ///
    /// - Parameters:
    ///   - hasInWorldKey: Non-empty InWorld API key from env or Leo's Keychain-backed settings.
    ///   - hasFishAudioKey: Non-empty Fish Audio API key from Leo's Keychain-backed settings.
    ///   - preferSystem: When `true`, bypass all API/local backends and use system speech.
    ///   - selectedBackend: Explicit backend preference from Settings; `nil` means auto.
    static func resolveBackend(
        hasInWorldKey: Bool,
        hasFishAudioKey: Bool = false,
        preferSystem: Bool,
        selectedBackend: LeoTTSBackend? = nil
    ) -> LeoTTSBackend {
        if preferSystem { return .systemSpeech }

        // Honour explicit user selection when the backend is viable.
        if let selected = selectedBackend {
            switch selected {
            case .qwen3:
                if isAppleSilicon { return .qwen3 }
            case .inWorld:
                if hasInWorldKey { return .inWorld }
            case .fishAudio:
                if hasFishAudioKey { return .fishAudio }
            case .systemSpeech:
                return .systemSpeech
            }
            // Requested backend is unavailable — fall through to auto.
        }

        // Auto priority.
        if isAppleSilicon { return .qwen3 }
        if hasInWorldKey { return .inWorld }
        if hasFishAudioKey { return .fishAudio }
        return .systemSpeech
    }
}
