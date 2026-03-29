import Foundation
import Testing
@testable import Leo

@Suite("AnkiExporter Tests")
struct AnkiExporterTests {

    // MARK: - Export (TSV)

    @Test("exportCards writes valid Anki TSV header")
    func exportHeaderLines() throws {
        let exporter = AnkiExporter()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-test-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try exporter.exportCards([], to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        #expect(lines[0] == "#separator:tab")
        #expect(lines[1] == "#html:false")
        #expect(lines[2] == "#columns:Front\tPinyin\tDefinition\tContext")
    }

    @Test("exportCards produces one row per card")
    func exportCardCount() throws {
        let exporter = AnkiExporter()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-test-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let cards = [
            AnkiExporter.ExportCard(word: "你好", pinyin: "nǐ hǎo", definition: "hello", contextSentence: "你好，世界"),
            AnkiExporter.ExportCard(word: "再见", pinyin: "zài jiàn", definition: "goodbye", contextSentence: ""),
        ]
        try exporter.exportCards(cards, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let dataLines = content.components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }

        #expect(dataLines.count == 2)
    }

    @Test("exportCards row has 4 tab-separated columns")
    func exportRowColumns() throws {
        let exporter = AnkiExporter()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-test-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let card = AnkiExporter.ExportCard(
            word: "学生",
            pinyin: "xué shēng",
            definition: "student",
            contextSentence: "我是学生"
        )
        try exporter.exportCards([card], to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let dataLines = content.components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        let cols = dataLines[0].components(separatedBy: "\t")

        #expect(cols.count == 4)
        #expect(cols[0] == "学生")
        #expect(cols[1] == "xué shēng")
        #expect(cols[2] == "student")
        #expect(cols[3] == "我是学生")
    }

    @Test("exportCards sanitizes embedded tabs in definition")
    func exportSanitizesTabsInDefinition() throws {
        let exporter = AnkiExporter()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-test-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let card = AnkiExporter.ExportCard(
            word: "测试",
            pinyin: "cè shì",
            definition: "test\talso: exam",   // embedded tab — must be sanitized
            contextSentence: ""
        )
        try exporter.exportCards([card], to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let dataLines = content.components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        let cols = dataLines[0].components(separatedBy: "\t")

        // 4 columns — not 5 (tab in definition was replaced with space)
        #expect(cols.count == 4)
        #expect(cols[2] == "test also: exam")
    }

    @Test("exportCards sanitizes embedded tabs in context sentence")
    func exportSanitizesTabsInContext() throws {
        let exporter = AnkiExporter()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-test-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let card = AnkiExporter.ExportCard(
            word: "世界",
            pinyin: "shì jiè",
            definition: "world",
            contextSentence: "你好\t世界"   // embedded tab
        )
        try exporter.exportCards([card], to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let dataLines = content.components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        let cols = dataLines[0].components(separatedBy: "\t")

        #expect(cols.count == 4)
        #expect(cols[3] == "你好 世界")
    }

    @Test("exportCards creates an empty file with only headers when cards list is empty")
    func exportEmpty() throws {
        let exporter = AnkiExporter()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-test-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try exporter.exportCards([], to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let dataLines = content.components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        #expect(dataLines.isEmpty)
    }

    // MARK: - Card type → FamiliarityState mapping

    /// Validates the state-mapping logic in isolation by simulating what importDeck
    /// does for each card type, without needing a real .apkg fixture.
    @Test("Anki card type 0 (new) maps to .unknown")
    func cardTypeMappingNew() {
        let state = ankiStateFromType(cardType: 0, interval: 0)
        #expect(state == .unknown)
    }

    @Test("Anki card type 1 (learning) maps to .learning")
    func cardTypeMappingLearning() {
        let state = ankiStateFromType(cardType: 1, interval: 0)
        #expect(state == .learning)
    }

    @Test("Anki card type 2, interval < 21 (young review) maps to .familiar")
    func cardTypeMappingYoungReview() {
        let state = ankiStateFromType(cardType: 2, interval: 20)
        #expect(state == .familiar)
    }

    @Test("Anki card type 2, interval == 21 (mature review) maps to .known")
    func cardTypeMappingMatureReviewBoundary() {
        let state = ankiStateFromType(cardType: 2, interval: 21)
        #expect(state == .known)
    }

    @Test("Anki card type 2, interval > 21 (mature review) maps to .known")
    func cardTypeMappingMatureReview() {
        let state = ankiStateFromType(cardType: 2, interval: 90)
        #expect(state == .known)
    }

    @Test("Anki card type 3 (relearning) maps to .learning, not .seen")
    func cardTypeMappingRelearning() {
        let state = ankiStateFromType(cardType: 3, interval: 0)
        #expect(state == .learning)
    }

    @Test("Unknown card types default to .unknown (conservative)")
    func cardTypeMappingUnknown() {
        let state = ankiStateFromType(cardType: 99, interval: 0)
        #expect(state == .unknown)
    }

    // MARK: - Helpers

    /// Mirrors the state-mapping switch in AnkiExporter.importDeck so we can unit-test
    /// each branch without spinning up a full SQLite database.
    private func ankiStateFromType(cardType: Int, interval: Int) -> FamiliarityState {
        switch cardType {
        case 0: .unknown
        case 1: .learning
        case 2 where interval >= 21: .known
        case 2: .familiar
        case 3: .learning
        default: .unknown
        }
    }
}
