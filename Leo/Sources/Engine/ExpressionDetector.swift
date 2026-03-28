import Foundation

/// Layer 2 of the Chinese Parser: Dictionary-based multi-word expression detection.
/// Detects: 成语 (chéngyǔ), 惯用语 (guànyòngyǔ), collocations, grammar patterns.
///
/// Architecture:
/// - Uses CC-CEDICT multi-character entries as expression database
/// - Longest-match-first greedy algorithm for expression boundary detection
/// - Grammar pattern templates for structural patterns (把, 被, 越...越)
struct ExpressionDetector: Sendable {

    struct Expression: Sendable, Identifiable {
        let id = UUID()
        let text: String
        let range: Range<String.Index>
        let type: ExpressionType
        let pinyin: String
        let definition: String
    }

    enum ExpressionType: Sendable {
        case idiom          // 成语 (4-char fixed expressions)
        case collocation    // Multi-word collocations (不得不, 来不及)
        case grammarPattern // Structural patterns (把...V, 被...V)
        case compound       // Compound words from dictionary
    }

    /// Detect multi-word expressions in text.
    /// Uses longest-match-first: tries longest possible expressions first,
    /// falls back to shorter ones.
    func detect(in text: String) -> [Expression] {
        let dict = DictionaryEngine.shared
        var expressions: [Expression] = []
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            guard char.isChineseCharacter else {
                index = text.index(after: index)
                continue
            }

            // Try longest match first (up to 8 characters — covers most expressions)
            var bestMatch: Expression?
            let maxLen = 8

            for length in stride(from: min(maxLen, text.distance(from: index, to: text.endIndex)), through: 2, by: -1) {
                let endIdx = text.index(index, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
                let candidate = String(text[index..<endIdx])

                let entries = dict.lookup(candidate)
                if !entries.isEmpty {
                    let entry = entries[0]
                    let type = classifyExpression(candidate, definition: entry.definitions.joined(separator: "; "))
                    bestMatch = Expression(
                        text: candidate,
                        range: index..<endIdx,
                        type: type,
                        pinyin: entry.pinyinDisplay,
                        definition: entry.definitions.first ?? ""
                    )
                    break // Longest match found
                }
            }

            if let match = bestMatch, match.text.count >= 2 {
                expressions.append(match)
                index = match.range.upperBound
            } else {
                index = text.index(after: index)
            }
        }

        // Also detect grammar patterns (these span non-contiguous elements)
        let patterns = detectGrammarPatterns(in: text)
        expressions.append(contentsOf: patterns)

        return expressions
    }

    /// Classify an expression based on its characteristics.
    private func classifyExpression(_ text: String, definition: String) -> ExpressionType {
        // 成语 are typically exactly 4 characters
        if text.count == 4 && text.allSatisfy(\.isChineseCharacter) {
            // Check if it's a known idiom pattern
            let idiomMarkers = ["CL:", "idiom", "proverb", "saying", "fig."]
            if idiomMarkers.contains(where: { definition.contains($0) }) {
                return .idiom
            }
            return .idiom // Most 4-char all-Chinese are 成语
        }

        // Grammar-related expressions
        let grammarMarkers = ["particle", "conjunction", "preposition", "auxiliary"]
        if grammarMarkers.contains(where: { definition.lowercased().contains($0) }) {
            return .grammarPattern
        }

        // Default to collocation for 2-3 char, compound for longer
        return text.count <= 3 ? .collocation : .compound
    }

    /// Detect structural grammar patterns that span across words.
    /// E.g.: 把...V, 被...V, 越...越..., 一边...一边...
    private func detectGrammarPatterns(in text: String) -> [Expression] {
        var patterns: [Expression] = []

        // 把 construction: 把 + object + verb
        let baPattern = detectBaPattern(in: text)
        patterns.append(contentsOf: baPattern)

        // 被 passive: 被 + (agent) + verb
        let beiPattern = detectBeiPattern(in: text)
        patterns.append(contentsOf: beiPattern)

        return patterns
    }

    private func detectBaPattern(in text: String) -> [Expression] {
        var results: [Expression] = []
        var searchStart = text.startIndex

        while let range = text.range(of: "把", range: searchStart..<text.endIndex) {
            // 把 construction: mark just the 把 as a grammar marker
            results.append(Expression(
                text: "把",
                range: range,
                type: .grammarPattern,
                pinyin: "bǎ",
                definition: "把 construction — disposal/resultative pattern"
            ))
            searchStart = range.upperBound
        }
        return results
    }

    private func detectBeiPattern(in text: String) -> [Expression] {
        var results: [Expression] = []
        var searchStart = text.startIndex

        while let range = text.range(of: "被", range: searchStart..<text.endIndex) {
            results.append(Expression(
                text: "被",
                range: range,
                type: .grammarPattern,
                pinyin: "bèi",
                definition: "被 passive — the subject receives the action"
            ))
            searchStart = range.upperBound
        }
        return results
    }
}
