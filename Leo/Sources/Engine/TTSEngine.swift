import Foundation
import AVFoundation

/// Read aloud: InWorld (optional key, word timestamps) or macOS `AVSpeechSynthesizer` (free).
@MainActor
final class TTSEngine: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentWordIndex: Int = -1
    @Published var currentWordRange: NSRange?
    @Published var error: String?

    private var audioPlayer: AVAudioPlayer?
    private var wordTimestamps: [WordTimestamp] = []
    private var displayLink: Timer?

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var systemUtterance: AVSpeechUtterance?
    private var activeBackend: LeoTTSBackend?

    struct WordTimestamp: Sendable {
        let word: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    struct TTSResult: Sendable {
        let audioData: Data
        let timestamps: [WordTimestamp]
    }

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    // MARK: - Public API

    func generate(text: String) async {
        guard !text.isEmpty else { return }
        isLoading = true
        error = nil
        stopAllOutputs()

        let hasKey = getAPIKey() != nil
        // Default to true (system TTS) when the key has never been written — mirrors the
        // @AppStorage default in TTSSettingsTab and avoids UserDefaults.bool returning false
        // for a missing key.
        let preferSystem: Bool
        if UserDefaults.standard.object(forKey: "leo.ttsPreferSystem") != nil {
            preferSystem = UserDefaults.standard.bool(forKey: "leo.ttsPreferSystem")
        } else {
            preferSystem = true
        }
        let backend = TTSProviderResolution.resolveBackend(hasInWorldKey: hasKey, preferSystem: preferSystem)
        activeBackend = backend

        switch backend {
        case .inWorld:
            do {
                let result = try await callInWorldTTS(text: text)
                wordTimestamps = result.timestamps
                audioPlayer = try AVAudioPlayer(data: result.audioData)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                applyUserSpeedToPlayer()
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        case .systemSpeech:
            wordTimestamps = []
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.preferredChineseVoice() ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = Self.clampedSpeechRate(fromUserMultiplier: Self.userSpeedMultiplier())
            systemUtterance = utterance
            isLoading = false
        }
    }

    /// Start or resume playback.
    func play() {
        switch activeBackend {
        case .inWorld:
            guard let player = audioPlayer else { return }
            player.play()
            isPlaying = true
            startHighlightTimer()
        case .systemSpeech:
            guard let utt = systemUtterance else { return }
            if speechSynthesizer.isPaused {
                speechSynthesizer.continueSpeaking()
            } else if !speechSynthesizer.isSpeaking {
                speechSynthesizer.speak(utt)
            }
            isPlaying = true
        case .none:
            break
        }
    }

    /// Pause playback.
    func pause() {
        switch activeBackend {
        case .inWorld:
            audioPlayer?.pause()
            isPlaying = false
            stopHighlightTimer()
        case .systemSpeech:
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.pauseSpeaking(at: .word)
            }
            isPlaying = false
        case .none:
            break
        }
    }

    /// Stop playback and reset.
    func stop() {
        stopAllOutputs()
        isPlaying = false
        currentWordIndex = -1
        activeBackend = nil
        systemUtterance = nil
    }

    func seekToWord(at index: Int) {
        guard index >= 0, index < wordTimestamps.count else { return }
        let timestamp = wordTimestamps[index]
        audioPlayer?.currentTime = timestamp.startTime
        currentWordIndex = index
        if isPlaying {
            audioPlayer?.play()
        }
    }

    func seekToWord(_ word: String, occurrence: Int = 0) {
        var count = 0
        for (index, ts) in wordTimestamps.enumerated() where ts.word == word {
            if count == occurrence {
                seekToWord(at: index)
                return
            }
            count += 1
        }
    }

    func setSpeed(_ rate: Float) {
        audioPlayer?.rate = rate
        audioPlayer?.enableRate = true
        systemUtterance?.rate = Self.clampedSpeechRate(fromUserMultiplier: Double(rate))
    }

    var currentTime: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }

    var duration: TimeInterval {
        audioPlayer?.duration ?? 0
    }

    var timestamps: [WordTimestamp] {
        wordTimestamps
    }

    // MARK: - Private

    private func stopAllOutputs() {
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        stopHighlightTimer()
        wordTimestamps = []
        currentWordIndex = -1
        currentWordRange = nil
        systemUtterance = nil
    }

    private func applyUserSpeedToPlayer() {
        let speed = Self.userSpeedMultiplier()
        if speed > 0 {
            setSpeed(Float(speed))
        }
    }

    private static func userSpeedMultiplier() -> Double {
        let v = UserDefaults.standard.double(forKey: "leo.ttsSpeed")
        return v > 0 ? v : 1.0
    }

    /// Map UI multiplier (0.5...2.0) to AVSpeechUtterance rate.
    private static func clampedSpeechRate(fromUserMultiplier multiplier: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let scaled = base * multiplier
        let lo = Double(AVSpeechUtteranceMinimumSpeechRate)
        let hi = Double(AVSpeechUtteranceMaximumSpeechRate)
        return Float(min(max(scaled, lo + 0.01), hi - 0.01))
    }

    private static func preferredChineseVoice() -> AVSpeechSynthesisVoice? {
        for voice in AVSpeechSynthesisVoice.speechVoices() where voice.language.hasPrefix("zh") {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    private func callInWorldTTS(text: String) async throws -> TTSResult {
        guard let apiKey = getAPIKey() else {
            throw TTSError.noAPIKey
        }

        let url = URL(string: "https://api.inworld.ai/tts/v1/voice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let voiceId = UserDefaults.standard.string(forKey: "leo.ttsVoice") ?? "Dennis"
        let modelId = UserDefaults.standard.string(forKey: "leo.ttsModel") ?? "inworld-tts-1.5-max"

        let body: [String: Any] = [
            "text": text,
            "voiceId": voiceId,
            "modelId": modelId,
            "audioConfig": [
                "audioEncoding": "MP3",
                "sampleRateHertz": 22050,
            ],
            "temperature": 1.1,
            "timestampType": "WORD",
            "autoMode": true,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError(httpResponse.statusCode, errorBody)
        }

        return try parseInWorldResponse(data)
    }

    private func parseInWorldResponse(_ data: Data) throws -> TTSResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TTSError.parseError
        }

        guard let audioBase64 = json["audio"] as? String,
              let audioData = Data(base64Encoded: audioBase64) else {
            throw TTSError.parseError
        }

        var timestamps: [WordTimestamp] = []
        if let timestampInfo = json["timestampInfo"] as? [String: Any],
           let wordAlignment = timestampInfo["wordAlignment"] as? [[String: Any]] {
            for alignment in wordAlignment {
                if let word = alignment["word"] as? String,
                   let start = alignment["wordStartTimeSeconds"] as? Double,
                   let end = alignment["wordEndTimeSeconds"] as? Double {
                    timestamps.append(WordTimestamp(word: word, startTime: start, endTime: end))
                }
            }
        }

        return TTSResult(audioData: audioData, timestamps: timestamps)
    }

    private func startHighlightTimer() {
        stopHighlightTimer()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHighlight()
            }
        }
    }

    private func stopHighlightTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateHighlight() {
        guard let player = audioPlayer, player.isPlaying else { return }
        let currentTime = player.currentTime

        for (index, ts) in wordTimestamps.enumerated() {
            if currentTime >= ts.startTime && currentTime < ts.endTime {
                if currentWordIndex != index {
                    currentWordIndex = index
                }
                return
            }
        }
    }

    private func getAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["INWORLD_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = LeoKeychainHelper().getSecret(for: .inWorld), !key.isEmpty {
            return key
        }
        return nil
    }
}

extension TTSEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            currentWordIndex = -1
            stopHighlightTimer()
        }
    }
}

extension TTSEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            currentWordRange = characterRange
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = false
            currentWordIndex = -1
            currentWordRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = false
            currentWordRange = nil
        }
    }
}

enum TTSError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No InWorld API key configured. Add one in Settings or set INWORLD_API_KEY."
        case .invalidResponse: "Invalid response from TTS API"
        case .apiError(let code, let msg): "TTS API error (\(code)): \(msg)"
        case .parseError: "Failed to parse TTS response"
        }
    }
}
