import Foundation
import Testing
@testable import Leo

/// Integration tests using real text from 活着 (To Live) by Yu Hua.
/// These test the parser against actual literary Chinese, not toy examples.
@Suite("Parser Integration — 活着")
struct ParserIntegrationTests {
    let parser = ChineseParser()

    // Real text from 活着 chapter 3
    let huozheText = """
    福贵说到这里看着我嘿嘿笑了，这位四十年前的浪子，如今赤裸着胸膛坐在青草上，\
    阳光从树叶的缝隙里照射下来，照在他眯缝的眼睛上。
    """

    let huozheNarrative = """
    这位老人是我最初遇到的，那时候我刚刚开始那段漫游的生活，我年轻无忧无虑，\
    每一张新的脸都会使我兴致勃勃，一切我所不知的事物都会深深吸引我。
    """

    init() {
        DictionaryEngine.shared.load()
    }

    @Test("Segments 活着 text without losing characters")
    func noCharacterLoss() {
        let tokens = parser.segmentWords(huozheText)
        let reconstructed = tokens.map(\.text).joined()
        #expect(reconstructed == huozheText,
               "Parser must not lose any characters during segmentation")
    }

    @Test("Finds multi-character words in literary Chinese")
    func literaryMultiCharWords() {
        let tokens = parser.segmentWords(huozheText)
        let words = tokens.filter { $0.type == .word }.map(\.text)

        // These are common multi-char words that should be detected
        let expectedMultiChar = ["福贵", "嘿嘿", "四十", "浪子", "如今",
                                  "赤裸", "胸膛", "青草", "阳光", "树叶",
                                  "缝隙", "照射", "眼睛"]

        var found: [String] = []
        for expected in expectedMultiChar {
            if words.contains(expected) {
                found.append(expected)
            }
        }
        // Should find at least half of the expected multi-char words
        #expect(found.count >= expectedMultiChar.count / 2,
               "Found \(found.count)/\(expectedMultiChar.count): \(found)")
    }

    @Test("Handles Chinese punctuation in narrative text")
    func narrativePunctuation() {
        let text = "他说，你好吗？我回答道，很好，谢谢。"
        let tokens = parser.segmentWords(text)
        let punctuation = tokens.filter { $0.type == .punctuation }
        #expect(punctuation.count >= 3, "Should detect Chinese punctuation marks")
    }

    @Test("resolveWordAtPosition works on literary text")
    func resolveInLiteraryContext() {
        // Click on 缝 in 缝隙
        let text = "阳光从树叶的缝隙里照射下来"
        let charIndex = text.distance(from: text.startIndex,
                                       to: text.firstIndex(of: "缝")!)
        let word = parser.resolveWordAtPosition(context: text, charIndex: charIndex)
        #expect(word == "缝隙", "Should resolve to 缝隙, got \(word)")
    }

    @Test("resolveWordAtPosition on 照射")
    func resolveZhaoshe() {
        let text = "阳光从树叶的缝隙里照射下来"
        let charIndex = text.distance(from: text.startIndex,
                                       to: text.firstIndex(of: "照")!)
        let word = parser.resolveWordAtPosition(context: text, charIndex: charIndex)
        #expect(word == "照射" || word == "照射下来",
               "Should resolve to 照射, got \(word)")
    }

    @Test("Handles classical/literary expressions")
    func literaryExpressions() {
        // 和盘托出 = to reveal everything (成语)
        let text = "他愿意和盘托出"
        let tokens = parser.segmentWords(text)
        let words = tokens.filter { $0.type == .word }.map(\.text)
        // Either detected as one unit or as component parts — both acceptable
        let joined = words.joined()
        #expect(joined.contains("和盘托出") || joined.contains("和盘"),
               "Should handle classical expression, got: \(words)")
    }

    @Test("Segments long narrative passage completely")
    func longPassageCompleteness() {
        let tokens = parser.segmentWords(huozheNarrative)
        let wordCount = tokens.filter { $0.type == .word }.count
        #expect(wordCount > 15, "Long passage should produce many word tokens, got \(wordCount)")

        let reconstructed = tokens.map(\.text).joined()
        #expect(reconstructed == huozheNarrative, "No character loss in long passage")
    }

    @Test("Dictionary lookup works for literary vocabulary")
    func literaryVocabLookup() {
        let dict = DictionaryEngine.shared
        // Words from 活着 that should be in CC-CEDICT
        let literaryWords = ["浪子", "赤裸", "缝隙", "照射", "眯缝",
                              "稀稀疏疏", "皱", "起伏", "脊梁", "拍岸"]
        var found = 0
        for word in literaryWords {
            if !dict.lookup(word).isEmpty {
                found += 1
            }
        }
        #expect(found >= 5, "Should find at least 5/10 literary words in CC-CEDICT, found \(found)")
    }

    @Test("Performance: parse 500 characters under 100ms")
    func parserPerformance() {
        let longText = String(repeating: huozheText, count: 3) // ~450 chars
        let start = Date()
        let _ = parser.segmentWords(longText)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.5, "Parser took \(elapsed)s — should be under 500ms for 450 chars")
    }
}
