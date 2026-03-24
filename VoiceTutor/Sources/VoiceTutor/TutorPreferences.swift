import Foundation

enum TutorPreferences {
    /// UserDefaults keys (shared with `@AppStorage` in SwiftUI).
    enum StorageKey {
        static let agentId = "VoiceTutor.agentId"
        static let useTokenBroker = "VoiceTutor.useTokenBroker"
        static let brokerURL = "VoiceTutor.brokerURL"
        /// Passed to the Swift SDK as `ConversationConfig.environment` (optional regional / deployment routing).
        static let elevenLabsEnvironment = "VoiceTutor.elevenLabsEnvironment"
    }

    static var agentId: String {
        get { UserDefaults.standard.string(forKey: StorageKey.agentId) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.agentId) }
    }

    static var useTokenBroker: Bool {
        get { UserDefaults.standard.bool(forKey: StorageKey.useTokenBroker) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.useTokenBroker) }
    }

    static var brokerURLString: String {
        get {
            let s = UserDefaults.standard.string(forKey: StorageKey.brokerURL) ?? ""
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "http://127.0.0.1:8787" : trimmed
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: StorageKey.brokerURL)
        }
    }

    static var brokerURL: URL? {
        URL(string: brokerURLString)
    }

    static var elevenLabsEnvironment: String {
        get { UserDefaults.standard.string(forKey: StorageKey.elevenLabsEnvironment) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.elevenLabsEnvironment) }
    }

    /// `nil` when unset — matches SDK default (global production routing).
    static var elevenLabsEnvironmentForSDK: String? {
        let t = elevenLabsEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
