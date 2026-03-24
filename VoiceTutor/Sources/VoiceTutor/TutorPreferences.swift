import Foundation

enum TutorPreferences {
    private static let agentIdKey = "VoiceTutor.agentId"
    private static let useTokenBrokerKey = "VoiceTutor.useTokenBroker"
    private static let brokerURLKey = "VoiceTutor.brokerURL"

    static var agentId: String {
        get { UserDefaults.standard.string(forKey: agentIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: agentIdKey) }
    }

    static var useTokenBroker: Bool {
        get { UserDefaults.standard.bool(forKey: useTokenBrokerKey) }
        set { UserDefaults.standard.set(newValue, forKey: useTokenBrokerKey) }
    }

    static var brokerURLString: String {
        get {
            let s = UserDefaults.standard.string(forKey: brokerURLKey) ?? ""
            return s.isEmpty ? "http://127.0.0.1:8787" : s
        }
        set { UserDefaults.standard.set(newValue, forKey: brokerURLKey) }
    }

    static var brokerURL: URL? {
        URL(string: brokerURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
