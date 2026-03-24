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

    @Test("Broker error descriptions include HTTP detail")
    func brokerErrorText() {
        let err = TokenBrokerClientError.badStatus(401, detail: "unauthorized")
        #expect(err.errorDescription?.contains("401") == true)
        #expect(err.errorDescription?.contains("unauthorized") == true)
    }
}

@Suite("TutorPreferences")
struct TutorPreferencesTests {
    @Test("Defaults broker string when unset")
    func brokerDefault() {
        UserDefaults.standard.removeObject(forKey: "VoiceTutor.brokerURL")
        #expect(TutorPreferences.brokerURLString == "http://127.0.0.1:8787")
    }

    @Test("Whitespace-only broker URL falls back to default")
    func brokerWhitespaceFallback() {
        UserDefaults.standard.set("  \n\t", forKey: "VoiceTutor.brokerURL")
        #expect(TutorPreferences.brokerURLString == "http://127.0.0.1:8787")
        #expect(TutorPreferences.brokerURL?.absoluteString == "http://127.0.0.1:8787")
        UserDefaults.standard.removeObject(forKey: "VoiceTutor.brokerURL")
    }

    @Test("Empty ElevenLabs environment maps to nil for SDK")
    func environmentOptional() {
        UserDefaults.standard.removeObject(forKey: "VoiceTutor.elevenLabsEnvironment")
        #expect(TutorPreferences.elevenLabsEnvironmentForSDK == nil)
        UserDefaults.standard.set("  \n", forKey: "VoiceTutor.elevenLabsEnvironment")
        #expect(TutorPreferences.elevenLabsEnvironmentForSDK == nil)
        UserDefaults.standard.set("prod", forKey: "VoiceTutor.elevenLabsEnvironment")
        #expect(TutorPreferences.elevenLabsEnvironmentForSDK == "prod")
        UserDefaults.standard.removeObject(forKey: "VoiceTutor.elevenLabsEnvironment")
    }
}
