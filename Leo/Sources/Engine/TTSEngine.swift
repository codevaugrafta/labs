import Foundation
import AVFoundation

/// TTS Engine with word-level timestamp sync.
/// Primary: InWorld TTS-1.5 Max (word timestamps, Chinese support)
/// Fallback: Edge TTS (free, word boundaries via Python bridge — future)
@MainActor
final class TTSEngine: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentWordIndex: Int = -1
    @Published var error: String?

    private var audioPlayer: AVAudioPlayer?
    private var wordTimestamps: [WordTimestamp] = []
    private var displayLink: Timer?
    private var playbackStartTime: Date?
    private var seekOffset: TimeInterval = 0

    struct WordTimestamp: Sendable {
        let word: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    struct TTSResult: Sendable {
        let audioData: Data
        let timestamps: [WordTimestamp]
    }

    // MARK: - Public API

    /// Generate TTS audio with word timestamps for a text.
    func generate(text: String) async {
        guard !text.isEmpty else { return }
        isLoading = true
        error = nil

        do {
            let result = try await callInWorldTTS(text: text)
            wordTimestamps = result.timestamps
            audioPlayer = try AVAudioPlayer(data: result.audioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Start or resume playback.
    func play() {
        guard let player = audioPlayer else { return }
        player.play()
        isPlaying = true
        startHighlightTimer()
    }

    /// Pause playback.
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopHighlightTimer()
    }

    /// Stop playback and reset.
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentWordIndex = -1
        seekOffset = 0
        stopHighlightTimer()
    }

    /// Seek to a specific word by index.
    func seekToWord(at index: Int) {
        guard index >= 0, index < wordTimestamps.count else { return }
        let timestamp = wordTimestamps[index]
        audioPlayer?.currentTime = timestamp.startTime
        currentWordIndex = index
        if isPlaying {
            audioPlayer?.play()
        }
    }

    /// Seek to a word matching the given text (for click-to-seek from reader).
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

    /// Set playback speed.
    func setSpeed(_ rate: Float) {
        audioPlayer?.rate = rate
        audioPlayer?.enableRate = true
    }

    /// Current playback time in seconds.
    var currentTime: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }

    /// Total duration in seconds.
    var duration: TimeInterval {
        audioPlayer?.duration ?? 0
    }

    /// The word timestamps for UI sync.
    var timestamps: [WordTimestamp] {
        wordTimestamps
    }

    // MARK: - InWorld API

    private func callInWorldTTS(text: String) async throws -> TTSResult {
        guard let apiKey = getAPIKey() else {
            throw TTSError.noAPIKey
        }

        let url = URL(string: "https://api.inworld.ai/tts/v1/voice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "voiceId": "Dennis", // Default — will be configurable
            "modelId": "inworld-tts-1.5-max",
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

        // Extract audio data (base64 encoded)
        guard let audioBase64 = json["audio"] as? String,
              let audioData = Data(base64Encoded: audioBase64) else {
            throw TTSError.parseError
        }

        // Extract word timestamps
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

    // MARK: - Highlight Timer

    private func startHighlightTimer() {
        stopHighlightTimer()
        // Update highlight every 50ms for smooth tracking
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

    // MARK: - API Key Management

    private func getAPIKey() -> String? {
        // Check Keychain first, then environment
        if let key = ProcessInfo.processInfo.environment["INWORLD_API_KEY"], !key.isEmpty {
            return key
        }
        // TODO: Read from Keychain (KeychainHelper integration)
        return nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension TTSEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            currentWordIndex = -1
            stopHighlightTimer()
        }
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No InWorld API key configured. Set INWORLD_API_KEY environment variable."
        case .invalidResponse: "Invalid response from TTS API"
        case .apiError(let code, let msg): "TTS API error (\(code)): \(msg)"
        case .parseError: "Failed to parse TTS response"
        }
    }
}
