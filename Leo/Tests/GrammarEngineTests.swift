import Foundation
import Testing
@testable import Leo

@Suite("GrammarEngine")
struct GrammarEngineTests {

    // MARK: - Helpers

    /// Build a minimal GrammarEngine populated from a hand-crafted JSON string
    /// so tests are hermetic and don't depend on the filesystem at test time.
    private func makeEngine(json: String) throws -> GrammarEngine {
        // GrammarEngine.shared is a singleton tied to the real file system,
        // so we exercise the Codable layer directly here.
        let data = try #require(json.data(using: .utf8))
        let patterns = try JSONDecoder().decode([GrammarEngine.GrammarPattern].self, from: data)
        return GrammarEngine._makeForTesting(patterns: patterns)
    }

    private static let sampleJSON = """
    [
      {
        "id": "TEST001",
        "title": "Expressing existence with \\"you\\"",
        "level": "A1",
        "structure": "Place + 有 + Obj.",
        "examples": [],
        "description": "The verb 有 expresses existence."
      },
      {
        "id": "TEST002",
        "title": "Negation with \\"bu\\"",
        "level": "A1",
        "structure": "Subj. + 不 + Verb",
        "examples": [],
        "description": "Use 不 to negate present and future actions."
      },
      {
        "id": "TEST003",
        "title": "Indicating excess with duo",
        "level": "B1",
        "structure": "Number + 多 + [Measure word]",
        "examples": [],
        "description": "Add 多 after a number to indicate excess."
      }
    ]
    """

    // MARK: - Codable

    @Test("GrammarPattern decodes from JSON correctly")
    func decodesPattern() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        #expect(engine.patternCount == 3)
    }

    // MARK: - lookup(word:)

    @Test("lookup returns nil for empty string")
    func lookupEmptyReturnsNil() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        #expect(engine.lookup(word: "") == nil)
    }

    @Test("lookup finds pattern by Chinese character in structure")
    func lookupByChineseChar() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        let results = engine.lookup(word: "有")

        #expect(results != nil)
        let titles = results!.map(\.title)
        #expect(titles.contains("Expressing existence with \"you\""))
    }

    @Test("lookup finds pattern for 不 which appears in structure")
    func lookupBuNegation() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        let results = engine.lookup(word: "不")

        #expect(results != nil)
        #expect(results!.map(\.id).contains("TEST002"))
    }

    @Test("lookup finds pattern for 多 excess structure")
    func lookupDuoExcess() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        let results = engine.lookup(word: "多")

        #expect(results != nil)
        #expect(results!.map(\.id).contains("TEST003"))
    }

    @Test("lookup returns nil for character not in any pattern")
    func lookupUnknownCharReturnsNil() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        #expect(engine.lookup(word: "猫") == nil)
    }

    @Test("lookup result includes correct level")
    func lookupReturnsCorrectLevel() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        let results = try #require(engine.lookup(word: "有"))
        let a1Pattern = try #require(results.first(where: { $0.id == "TEST001" }))
        #expect(a1Pattern.level == "A1")
    }

    @Test("lookup result includes structure string")
    func lookupReturnsStructure() throws {
        let engine = try makeEngine(json: Self.sampleJSON)

        let results = try #require(engine.lookup(word: "不"))
        let pattern = try #require(results.first(where: { $0.id == "TEST002" }))
        #expect(pattern.structure == "Subj. + 不 + Verb")
    }

    // MARK: - GrammarPattern properties

    @Test("GrammarPattern exposes all required fields")
    func patternFields() throws {
        let json = """
        [{
          "id": "X1",
          "title": "Test pattern",
          "level": "B2",
          "structure": "Subj. + 竟然 + Verb",
          "examples": [{"chinese": "他竟然来了", "pinyin": "tā jìngrán lái le", "english": "He actually came."}],
          "description": "Describes unexpected events."
        }]
        """
        let engine = try makeEngine(json: json)
        let results = try #require(engine.lookup(word: "竟"))
        let p = try #require(results.first)

        #expect(p.id == "X1")
        #expect(p.title == "Test pattern")
        #expect(p.level == "B2")
        #expect(p.structure.contains("竟然"))
        #expect(p.description.contains("unexpected"))
        #expect(p.examples.count == 1)
        #expect(p.examples[0].chinese == "他竟然来了")
    }
}
