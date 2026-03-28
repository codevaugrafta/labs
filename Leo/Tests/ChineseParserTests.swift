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
