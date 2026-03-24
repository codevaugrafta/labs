import Foundation

enum TutorPreferences {
    /// UserDefaults keys (shared with `@AppStorage` in SwiftUI).
    enum StorageKey {
        static let agentId = "VoiceTutor.agentId"
        static let useTokenBroker = "VoiceTutor.useTokenBroker"
        static let brokerURL = "VoiceTutor.brokerURL"
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
            return s.isEmpty ? "http://127.0.0.1:8787" : s
        }
        set { UserDefaults.standard.set(newValue, forKey: StorageKey.brokerURL) }
    }

    static var brokerURL: URL? {
        URL(string: brokerURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
