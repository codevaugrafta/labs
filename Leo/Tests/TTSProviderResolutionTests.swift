import Testing
@testable import Leo

@Suite("TTS provider resolution")
struct TTSProviderResolutionTests {

    @Test("Prefer system forces macOS speech even with InWorld key")
    func preferSystem() {
        let b = TTSProviderResolution.resolveBackend(hasInWorldKey: true, preferSystem: true)
        #expect(b == .systemSpeech)
    }

    @Test("InWorld when key present and system not preferred")
    func inWorldWhenKey() {
        let b = TTSProviderResolution.resolveBackend(hasInWorldKey: true, preferSystem: false)
        #expect(b == .inWorld)
    }

    @Test("System speech when no key")
    func systemWhenNoKey() {
        let b = TTSProviderResolution.resolveBackend(hasInWorldKey: false, preferSystem: false)
        #expect(b == .systemSpeech)
    }

    @Test("No key but prefer system still system")
    func noKeyPreferSystem() {
        let b = TTSProviderResolution.resolveBackend(hasInWorldKey: false, preferSystem: true)
        #expect(b == .systemSpeech)
    }
}
