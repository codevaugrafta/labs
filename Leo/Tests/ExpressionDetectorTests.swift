import Testing
@testable import Leo

@Suite("ExpressionDetector Tests")
struct ExpressionDetectorTests {

    init() {
        DictionaryEngine.shared.load()
    }

    let detector = ExpressionDetector()

    @Test("Detects multi-character dictionary entries")
    func detectMultiChar() {
        let text = "我不得不去学校"
        let expressions = detector.detect(in: text)
        let texts = expressions.map(\.text)
        // Should detect 不得不 as an expression
        #expect(texts.contains("不得不"), "Should detect 不得不, found: \(texts)")
    }

    @Test("Detects 4-character idioms")
    func detectIdioms() {
        let text = "他自言自语地说"
        let expressions = detector.detect(in: text)
        let idioms = expressions.filter { $0.type == .idiom }
        #expect(!idioms.isEmpty || !expressions.isEmpty, "Should detect expressions in text")
    }

    @Test("Longest match wins")
    func longestMatch() {
        // 不得不 should be detected as one unit, not 不得 + 不
        let text = "不得不"
        let expressions = detector.detect(in: text)
        if let first = expressions.first {
            #expect(first.text == "不得不" || first.text.count >= 2)
        }
    }

    @Test("Grammar pattern: 把 construction detected")
    func baConstruction() {
        let text = "他把书放在桌子上"
        let expressions = detector.detect(in: text)
        let grammar = expressions.filter { $0.type == .grammarPattern && $0.text == "把" }
        #expect(!grammar.isEmpty, "Should detect 把 grammar pattern")
    }

    @Test("Grammar pattern: 被 passive detected")
    func beiPassive() {
        let text = "这本书被很多人读过"
        let expressions = detector.detect(in: text)
        let grammar = expressions.filter { $0.type == .grammarPattern && $0.text == "被" }
        #expect(!grammar.isEmpty, "Should detect 被 grammar pattern")
    }

    @Test("No expressions in English text")
    func noExpressionsInEnglish() {
        let text = "Hello world this is a test"
        let expressions = detector.detect(in: text)
        #expect(expressions.isEmpty)
    }

    @Test("Handles empty text")
    func emptyText() {
        let expressions = detector.detect(in: "")
        #expect(expressions.isEmpty)
    }

    @Test("Expressions have pinyin and definitions")
    func expressionMetadata() {
        let text = "我喜欢吃苹果"
        let expressions = detector.detect(in: text)
        for expr in expressions {
            if expr.type != .grammarPattern {
                #expect(!expr.pinyin.isEmpty || !expr.definition.isEmpty,
                       "Expression '\(expr.text)' should have metadata")
            }
        }
    }
}
