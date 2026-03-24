import Foundation

enum TokenBrokerClientError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case noTokenInBody

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid broker URL"
        case let .badStatus(code): "Broker returned HTTP \(code)"
        case .noTokenInBody: "Broker response missing token"
        }
    }
}

enum TokenBrokerClient {
    private struct TokenPayload: Decodable {
        let token: String
    }

    /// Fetches a conversation token from the local broker (`GET /token?agent_id=`).
    static func fetchToken(agentId: String, brokerBase: URL) async throws -> String {
        var root = brokerBase.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") {
            root.removeLast()
        }
        guard var components = URLComponents(string: root + "/token") else {
            throw TokenBrokerClientError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "agent_id", value: agentId)]
        guard let url = components.url else { throw TokenBrokerClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenBrokerClientError.badStatus(-1)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw TokenBrokerClientError.badStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(TokenPayload.self, from: data)
        let t = decoded.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw TokenBrokerClientError.noTokenInBody }
        return t
    }
}
