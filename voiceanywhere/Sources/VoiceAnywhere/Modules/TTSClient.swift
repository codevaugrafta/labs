import Foundation

// MARK: - Protocol

protocol TTSProvider {
    func stream(text: String, voice: String, apiKey: String) async throws -> AsyncThrowingStream<Data, Error>
}

// MARK: - Client

@MainActor
class TTSClient {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func stream(text: String, voice: VoiceConfig) async throws -> AsyncThrowingStream<Data, Error> {
        let provider = settings.currentProvider
        guard let apiKey = KeychainHelper.getKey(for: provider), !apiKey.isEmpty else {
            throw TTSError.noAPIKey(provider: provider)
        }

        switch provider {
        case .inworld:
            return try await InworldTTS().stream(text: text, voice: voice.voiceId, apiKey: apiKey)
        case .elevenlabs:
            return try await ElevenLabsTTS().stream(text: text, voice: voice.voiceId, apiKey: apiKey)
        case .gemini:
            return try await GeminiTTS().stream(text: text, voice: voice.voiceId, apiKey: apiKey)
        }
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case noAPIKey(provider: TTSProviderType)
    case apiError(String)
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider):
            return "No API key configured for \(provider.displayName). Please add it in Settings."
        case .apiError(let msg):
            return "TTS API error: \(msg)"
        case .streamError(let msg):
            return "Streaming error: \(msg)"
        }
    }
}

// MARK: - Inworld TTS

class InworldTTS: TTSProvider {
    func stream(text: String, voice: String, apiKey: String) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.inworld.ai/v1/tts/stream")!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "text": text,
                        "voice": voice,
                        "output_format": "pcm_16000",
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: TTSError.apiError("Inworld API returned non-200"))
                        return
                    }

                    var buffer = Data()
                    let chunkSize = 4096

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - ElevenLabs TTS

class ElevenLabsTTS: TTSProvider {
    func stream(text: String, voice: String, apiKey: String) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "text": text,
                        "model_id": "eleven_flash_v2_5",
                        "output_format": "pcm_16000",
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: TTSError.apiError("ElevenLabs API returned non-200"))
                        return
                    }

                    var buffer = Data()
                    let chunkSize = 4096

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Gemini TTS

class GeminiTTS: TTSProvider {
    func stream(text: String, voice: String, apiKey: String) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:streamGenerateContent"
                    let url = URL(string: urlString)!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

                    let resolvedVoice = voice.isEmpty ? "Kore" : voice
                    let body: [String: Any] = [
                        "contents": [["parts": [["text": text]]]],
                        "generationConfig": [
                            "response_modalities": ["AUDIO"],
                            "speech_config": [
                                "voice_config": [
                                    "prebuilt_voice_config": ["voice_name": resolvedVoice],
                                ],
                            ],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: TTSError.apiError("Gemini API returned non-200"))
                        return
                    }

                    // Gemini streams newline-delimited JSON objects.
                    // Each object may contain an inlineData.data base64-encoded PCM field.
                    var jsonBuffer = Data()

                    for try await byte in bytes {
                        jsonBuffer.append(byte)

                        // Process complete lines (Gemini uses server-sent-events style newlines).
                        while let newlineRange = jsonBuffer.range(of: Data([0x0A])) {
                            let lineData = jsonBuffer[..<newlineRange.lowerBound]
                            jsonBuffer = jsonBuffer[newlineRange.upperBound...]

                            if let audioData = Self.extractAudio(from: lineData) {
                                continuation.yield(audioData)
                            }
                        }
                    }

                    // Handle any remaining buffered data.
                    if !jsonBuffer.isEmpty, let audioData = Self.extractAudio(from: jsonBuffer) {
                        continuation.yield(audioData)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parses a single JSON line from the Gemini stream and returns the decoded PCM bytes, if present.
    private static func extractAudio(from data: Data) -> Data? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Path: candidates[0].content.parts[0].inlineData.data
        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let firstPart = parts.first,
            let inlineData = firstPart["inlineData"] as? [String: Any],
            let base64String = inlineData["data"] as? String
        else {
            return nil
        }

        return Data(base64Encoded: base64String)
    }
}
