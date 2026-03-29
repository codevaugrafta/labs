import Foundation

/// Contextual Chinese→English gloss via OpenRouter chat completions.
enum OpenRouterLookupService {

    /// Short explanation of `word` in `sentence` (English). Bounded input.
    static func fetchContextualMeaning(
        word: String,
        sentence: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        let trimmedWord = String(word.prefix(64))
        let trimmedSentence = String(sentence.prefix(1800))

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let system = """
        You are a concise Chinese reading assistant. Given one target word or phrase and \
        the sentence it appears in, explain the meaning in this context in 1–2 short English \
        sentences. No preamble, no markdown, no pinyin unless essential.
        """

        let user = "Target: \(trimmedWord)\n\nSentence:\n\(trimmedSentence)"

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "max_tokens": 180,
            "temperature": 0.3,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OpenRouterError.http(http.statusCode, msg)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw OpenRouterError.parseFailed
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OpenRouterError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from OpenRouter"
        case .http(let code, let msg): "OpenRouter error (\(code)): \(msg.prefix(200))"
        case .parseFailed: "Could not parse OpenRouter response"
        }
    }
}
