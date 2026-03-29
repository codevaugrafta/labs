import Foundation

/// AllSet Grammar pattern database for Chinese grammar points.
/// Loads 506 patterns from asg_grammar.json and matches them by word
/// appearing in the pattern's structure or title.
final class GrammarEngine: @unchecked Sendable {
    static let shared = GrammarEngine()

    struct GrammarPattern: Sendable, Codable {
        let id: String
        let title: String
        let level: String       // A1/A2/B1/B2/C1
        let structure: String
        let examples: [Example]
        let description: String

        struct Example: Sendable, Codable {
            let chinese: String
            let pinyin: String
            let english: String
        }
    }

    private var patterns: [GrammarPattern] = []
    private var wordIndex: [String: [GrammarPattern]] = [:]
    private var loaded = false

    private init() {}

    /// Load grammar patterns from the embedded asg_grammar.json.
    func load(forceReload: Bool = false) {
        guard !loaded || forceReload else { return }
        loaded = false

        guard let path = findGrammarPath() else {
            print("[GrammarEngine] asg_grammar.json not found")
            return
        }

        guard let data = FileManager.default.contents(atPath: path) else {
            print("[GrammarEngine] Failed to read asg_grammar.json")
            return
        }

        do {
            let decoded = try JSONDecoder().decode([GrammarPattern].self, from: data)
            patterns = decoded
            buildIndex()
            loaded = true
            print("[GrammarEngine] Loaded \(patterns.count) grammar patterns")
        } catch {
            print("[GrammarEngine] JSON decode error: \(error)")
        }
    }

    /// Return grammar patterns where the given word appears in the structure or title.
    /// Returns nil if no match found (nil signals "nothing to show" to callers).
    func lookup(word: String) -> [GrammarPattern]? {
        guard !word.isEmpty else { return nil }

        // First check the pre-built Chinese word index
        if let indexed = wordIndex[word], !indexed.isEmpty {
            return indexed
        }

        // Fallback: substring search in title (handles multi-char English words like "you")
        let lower = word.lowercased()
        let matched = patterns.filter { p in
            p.title.lowercased().contains(lower) || p.structure.contains(word)
        }
        return matched.isEmpty ? nil : matched
    }

    var patternCount: Int { patterns.count }

    // MARK: - Testing

    /// Create a pre-populated instance for unit tests without touching the filesystem.
    /// Not intended for production use.
    static func _makeForTesting(patterns: [GrammarPattern]) -> GrammarEngine {
        let engine = GrammarEngine()
        engine.patterns = patterns
        engine.buildIndex()
        engine.loaded = true
        return engine
    }

    // MARK: - Private

    /// Build an index from individual Chinese characters found in each pattern's structure.
    /// Patterns often look like: "Place + 有 + Obj." — we extract the hanzi tokens.
    private func buildIndex() {
        var index: [String: [GrammarPattern]] = [:]
        index.reserveCapacity(patterns.count * 3)

        for pattern in patterns {
            let tokens = extractChineseTokens(from: pattern.structure)
            for token in tokens {
                index[token, default: []].append(pattern)
            }
        }
        wordIndex = index
    }

    /// Extract individual Chinese characters and short Chinese words (1–3 chars)
    /// from a structure string like "Number + 多 + [Measure word] (+ Noun)".
    private func extractChineseTokens(from structure: String) -> [String] {
        var tokens: [String] = []
        var currentRun = ""

        for char in structure {
            if isChinese(char) {
                currentRun.append(char)
            } else {
                if !currentRun.isEmpty {
                    // Emit individual characters and also the whole run if <= 4 chars
                    for c in currentRun {
                        tokens.append(String(c))
                    }
                    if currentRun.count > 1 && currentRun.count <= 4 {
                        tokens.append(currentRun)
                    }
                    currentRun = ""
                }
            }
        }
        if !currentRun.isEmpty {
            for c in currentRun { tokens.append(String(c)) }
            if currentRun.count > 1 && currentRun.count <= 4 {
                tokens.append(currentRun)
            }
        }

        return Array(Set(tokens)) // deduplicate
    }

    private func isChinese(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF)
            || (v >= 0x3400 && v <= 0x4DBF)
            || (v >= 0x20000 && v <= 0x2A6DF)
            || (v >= 0xF900 && v <= 0xFAFF)
    }

    private func findGrammarPath() -> String? {
        // SPM bundle
        if let url = Bundle.module_safe?.url(
            forResource: "asg_grammar",
            withExtension: "json",
            subdirectory: "Dictionary"
        ) {
            return url.path
        }
        // Main bundle
        if let path = Bundle.main.path(forResource: "asg_grammar", ofType: "json") {
            return path
        }
        // App bundle candidates
        let base = Bundle.main.bundlePath
        let candidates = [
            "\(base)/../Resources/Dictionary/asg_grammar.json",
            "\(base)/Contents/Resources/Dictionary/asg_grammar.json",
            "\(base)/../../Sources/Resources/Dictionary/asg_grammar.json",
            "Sources/Resources/Dictionary/asg_grammar.json",
            "Leo/Sources/Resources/Dictionary/asg_grammar.json",
        ]
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }
}
