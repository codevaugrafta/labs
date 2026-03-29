import Testing
@testable import Leo

@Suite("FrequencyEngine Tests")
struct FrequencyEngineTests {

    init() {
        DictionaryEngine.shared.load()
        FrequencyEngine.shared.load()
    }

    @Test("Loads frequency data")
    func loadData() {
        let freq = FrequencyEngine.shared.lookup("我")
        #expect(freq.tier == .top500)
        #expect(freq.hskLevel == 1)
    }

    @Test("HSK 1 words are top 500")
    func hsk1Words() {
        let common = ["你", "他", "是", "有", "不", "吃", "看", "说"]
        for word in common {
            let freq = FrequencyEngine.shared.lookup(word)
            #expect(freq.tier == .top500, "Expected \(word) to be top 500, got \(freq.tier)")
        }
    }

    @Test("HSK 2 words are top 2000")
    func hsk2Words() {
        let words = ["觉得", "认为", "已经", "必须", "比较"]
        for word in words {
            let freq = FrequencyEngine.shared.lookup(word)
            #expect(freq.tier <= .top2000, "Expected \(word) to be top 2000, got \(freq.tier)")
        }
    }

    @Test("Unknown words are rare or uncommon")
    func unknownWords() {
        let freq = FrequencyEngine.shared.lookup("xyzabc不存在的词")
        #expect(freq.tier == .rare)
        #expect(freq.hskLevel == nil)
    }

    @Test("Frequency tiers are ordered correctly")
    func tierOrdering() {
        #expect(FrequencyEngine.FrequencyTier.top500 < .top2000)
        #expect(FrequencyEngine.FrequencyTier.top2000 < .top5000)
        #expect(FrequencyEngine.FrequencyTier.top5000 < .common)
        #expect(FrequencyEngine.FrequencyTier.common < .uncommon)
        #expect(FrequencyEngine.FrequencyTier.uncommon < .rare)
    }

    @Test("Weighted comprehension favors common words")
    func weightedComprehension() {
        // Knowing common words should give higher score
        // than knowing rare words
        let common = Set(["我", "是", "你", "他"])  // All HSK 1
        let allWords = ["我", "是", "你", "他", "抽象"] // 4 common + 1 advanced

        let score = FrequencyEngine.shared.weightedComprehension(
            knownWords: common,
            allWords: allWords
        )
        // Should be >= 0.8 because the known words are high-weight
        #expect(score >= 0.8)
    }

    // MARK: - Multi-corpus tests

    @Test("Common words have multi-corpus coverage")
    func multiCorpusCoverage() {
        // Core vocabulary should appear in multiple corpora
        let word = "我"
        let freq = FrequencyEngine.shared.lookup(word)
        // 我 is in TUBELEX, SUBTLEX, and BCC
        #expect(freq.sources.contains(.tubelex), "我 should be in TUBELEX")
        #expect(freq.sources.contains(.subtlex), "我 should be in SUBTLEX")
        #expect(freq.sources.contains(.bcc),     "我 should be in BCC")
        #expect(freq.sources.contains(.hsk),     "我 should be in HSK")
    }

    @Test("Composite rank beats HSK-only rank for spoken vocabulary")
    func compositeRankForSpokenWords() {
        // 呢 (sentence-final particle) — very common in speech, HSK rank may be high
        // Composite should rank it higher (lower rank number) because TUBELEX captures spoken usage
        let freq = FrequencyEngine.shared.lookup("呢")
        #expect(freq.tier <= .top500, "呢 is very common in speech and should be top 500")
    }

    @Test("HSK level is preserved from HSK corpus")
    func hskLevelPreservation() {
        // These words are in the composite AND in HSK — level should come through
        let hsk1Words = ["你", "我", "是", "有", "不", "大", "小"]
        for word in hsk1Words {
            let freq = FrequencyEngine.shared.lookup(word)
            #expect(freq.hskLevel == 1, "\(word) should be HSK level 1, got \(String(describing: freq.hskLevel))")
        }
    }

    @Test("Sources struct OptionSet works correctly")
    func sourcesOptionSet() {
        var sources = FrequencyEngine.CorpusSources.none
        #expect(!sources.contains(.tubelex))
        sources.insert(.tubelex)
        #expect(sources.contains(.tubelex))
        #expect(!sources.contains(.subtlex))
        sources.insert([.subtlex, .bcc])
        #expect(sources.contains(.subtlex))
        #expect(sources.contains(.bcc))
    }
}
