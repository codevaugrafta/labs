import Testing
@testable import Leo

@Suite("ChineseParser Tests")
struct ChineseParserTests {
    let parser = ChineseParser()

    @Test("Segments Chinese text into words")
    func segmentBasicChinese() {
        let tokens = parser.segmentWords("我喜欢吃苹果")
        let words = tokens.filter { $0.type == .word }.map(\.text)
        // NLTagger should produce word-level segments
        #expect(!words.isEmpty)
        #expect(words.joined() == "我喜欢吃苹果")
    }

    @Test("Segments mixed Chinese and English")
    func segmentMixed() {
        let tokens = parser.segmentWords("我喜欢Swift编程")
        let words = tokens.filter { $0.type == .word }.map(\.text)
        #expect(!words.isEmpty)
        #expect(words.contains("Swift") || words.joined().contains("Swift"))
    }

    @Test("Character-level segmentation")
    func characterSegmentation() {
        let tokens = parser.segmentCharacters("你好")
        let chars = tokens.filter { $0.type == .character }
        #expect(chars.count == 2)
        #expect(chars[0].text == "你")
        #expect(chars[1].text == "好")
    }

    @Test("Detects Chinese characters correctly")
    func detectChinese() {
        #expect(parser.containsChinese("你好世界"))
        #expect(!parser.containsChinese("Hello World"))
        #expect(parser.containsChinese("Hello 你好"))
    }

    @Test("Handles punctuation in text")
    func punctuationHandling() {
        let tokens = parser.segmentWords("你好！我是学生。")
        let punctuation = tokens.filter { $0.type == .punctuation }
        #expect(!punctuation.isEmpty)
    }

    @Test("Handles empty string")
    func emptyString() {
        let tokens = parser.segmentWords("")
        #expect(tokens.isEmpty)
    }

    @Test("Character isChineseCharacter extension")
    func characterExtension() {
        let chinese: Character = "中"
        let english: Character = "A"
        let number: Character = "5"

        #expect(chinese.isChineseCharacter)
        #expect(!english.isChineseCharacter)
        #expect(!number.isChineseCharacter)
    }

    // MARK: - Dictionary-Corrected Segmentation Tests

    @Test("Resolves word at clicked character position")
    func resolveWordAtPosition() {
        DictionaryEngine.shared.load()
        // Click on 欢 in 我喜欢吃苹果 → should resolve to 喜欢
        let word = parser.resolveWordAtPosition(context: "我喜欢吃苹果", charIndex: 2)
        #expect(word == "喜欢" || word == "喜欢吃" || word.contains("喜欢"),
               "Expected 喜欢, got \(word)")
    }

    @Test("Resolves multi-char expression 不得不")
    func resolveExpression() {
        DictionaryEngine.shared.load()
        let word = parser.resolveWordAtPosition(context: "我不得不去学校", charIndex: 2)
        #expect(word == "不得不", "Expected 不得不, got \(word)")
    }

    @Test("Expression-first: clicking 得 in 不得不 returns full expression")
    func resolveExpressionFirst() {
        DictionaryEngine.shared.load()
        // charIndex: 0=我, 1=不, 2=得, 3=不, 4=去
        let word = parser.resolveExpressionAtPosition(context: "我不得不去学校", charIndex: 2)
        #expect(word == "不得不", "Expected expression 不得不, got \(word)")
    }

    @Test("Expression-first: clicking first char of 不得不 returns full expression")
    func resolveExpressionFirstChar() {
        DictionaryEngine.shared.load()
        let word = parser.resolveExpressionAtPosition(context: "我不得不去学校", charIndex: 1)
        #expect(word == "不得不", "Expected expression 不得不, got \(word)")
    }

    @Test("Expression-first: single word falls back to word segmentation")
    func resolveExpressionFallback() {
        DictionaryEngine.shared.load()
        // 喜欢 is a 2-char word — expression detector should pick it up
        let word = parser.resolveExpressionAtPosition(context: "我喜欢吃苹果", charIndex: 2)
        #expect(word == "喜欢" || word.contains("喜欢"), "Expected 喜欢, got \(word)")
    }

    @Test("Resolves single character at position 0")
    func resolveFirstChar() {
        DictionaryEngine.shared.load()
        let word = parser.resolveWordAtPosition(context: "我喜欢吃苹果", charIndex: 0)
        #expect(word == "我", "Expected 我, got \(word)")
    }

    @Test("Dictionary-corrected segmentation finds multi-char words")
    func dictCorrectedSegment() {
        DictionaryEngine.shared.load()
        let tokens = parser.segmentWords("我喜欢吃苹果")
        let words = tokens.filter { $0.type == .word }.map(\.text)
        // Should contain 喜欢 and 苹果 as single tokens
        let joined = words.joined()
        #expect(joined == "我喜欢吃苹果", "Joined words: \(words)")
        #expect(words.contains("喜欢") || words.contains("苹果"),
               "Should detect multi-char words, got: \(words)")
    }

    @Test("Chinese punctuation detected")
    func chinesePunctuation() {
        let char: Character = "。"
        #expect(char.isChinesePunctuation)
        let char2: Character = "，"
        #expect(char2.isChinesePunctuation)
    }

    @Test("Tokens preserve text completeness")
    func tokenCompleteness() {
        DictionaryEngine.shared.load()
        let text = "今天天气很好，我想去公园散步。"
        let tokens = parser.segmentWords(text)
        let reconstructed = tokens.map(\.text).joined()
        #expect(reconstructed == text, "Tokens should reconstruct original text")
    }
}

@Suite("DictionaryEngine Tests")
struct DictionaryEngineTests {
    @Test("Loads dictionary successfully")
    func loadDictionary() {
        let engine = DictionaryEngine.shared
        engine.load()
        // Should find common words
        let results = engine.lookup("你好")
        #expect(!results.isEmpty)
    }

    @Test("Looks up common words")
    func lookupCommon() {
        let engine = DictionaryEngine.shared
        engine.load()

        let hello = engine.lookup("你好")
        #expect(!hello.isEmpty)
        #expect(hello.first?.pinyinDisplay.contains("hǎo") == true || hello.first?.pinyin.contains("hao3") == true)

        let eat = engine.lookup("吃")
        #expect(!eat.isEmpty)
    }

    @Test("Returns empty for nonsense")
    func lookupNonsense() {
        let engine = DictionaryEngine.shared
        engine.load()
        let results = engine.lookup("xyzabc")
        #expect(results.isEmpty)
    }

    @Test("Contains check works")
    func containsCheck() {
        let engine = DictionaryEngine.shared
        engine.load()
        #expect(engine.contains("学生"))
        #expect(!engine.contains("asdfghjkl"))
    }

    @Test("Pinyin tone marks are converted")
    func pinyinConversion() {
        let engine = DictionaryEngine.shared
        engine.load()
        let entries = engine.lookup("好")
        #expect(!entries.isEmpty)
        // Should have tone-marked pinyin
        let pinyin = entries.first?.pinyinDisplay ?? ""
        #expect(pinyin.contains("hǎo") || pinyin.contains("hào"))
    }

    @Test("Multi-character words found")
    func multiCharWords() {
        let engine = DictionaryEngine.shared
        engine.load()
        let results = engine.lookup("不得不")
        #expect(!results.isEmpty)
        let defs = results.flatMap(\.definitions).joined(separator: " ")
        #expect(defs.lowercased().contains("have") || defs.lowercased().contains("no choice"))
    }
}
