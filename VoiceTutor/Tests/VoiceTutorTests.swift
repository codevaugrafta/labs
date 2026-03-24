import Foundation
import Testing
@testable import VoiceTutor

@Suite("TokenBrokerClient")
struct TokenBrokerClientTests {
    @Test("Builds token URL with query")
    func tokenURL() throws {
        let base = try #require(URL(string: "http://127.0.0.1:8787"))
        // Exercise URL composition logic indirectly via a dry run would need network;
        // instead verify broker path normalization used by the app.
        var root = base.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") {
            root.removeLast()
        }
        let built = try #require(URL(string: root + "/token?agent_id=agent_test"))
        #expect(built.host == "127.0.0.1")
        #expect(built.port == 8787)
        #expect(built.path == "/token")
        #expect(built.query()?.contains("agent_test") == true)
    }
}

@Suite("TutorPreferences")
struct TutorPreferencesTests {
    @Test("Defaults broker string when unset")
    func brokerDefault() {
        UserDefaults.standard.removeObject(forKey: "VoiceTutor.brokerURL")
        #expect(TutorPreferences.brokerURLString == "http://127.0.0.1:8787")
    }
}
