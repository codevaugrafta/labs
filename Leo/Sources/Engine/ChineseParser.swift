import Foundation
import NaturalLanguage

/// Elite Chinese text parser with multi-layer segmentation.
///
/// Layer 1: Apple NLTagger (on-device ML word boundaries)
/// Layer 2: Dictionary-corrected segmentation (CC-CEDICT longest-match refinement)
/// Layer 3: POS tagging via NLTagger
///
/// The parser corrects NLTagger's mistakes by cross-referencing with CC-CEDICT.
/// NLTagger sometimes over-segments (splits valid words) or under-segments
/// (merges words that should be separate). Dictionary lookup resolves ambiguity.
struct ChineseParser: Sendable {

    struct Token: Sendable, Identifiable {
        let id = UUID()
        let text: String
        let range: Range<String.Index>
        let type: TokenType
        let pos: PartOfSpeech
        let isInDictionary: Bool
    }

    enum TokenType: Sendable {
        case word
        case character
        case punctuation
        case whitespace
        case number
        case other
    }

    enum PartOfSpeech: String, Sendable {
        case noun, verb, adjective, adverb, pronoun
        case preposition, conjunction, particle, classifier
        case number, determiner, interjection
        case other, unknown
    }

    // MARK: - Primary API

    /// Dictionary-corrected word segmentation.
    /// Uses NLTagger as baseline, then refines with CC-CEDICT longest-match.
    func segmentWords(_ text: String) -> [Token] {
        guard !text.isEmpty else { return [] }

        // Step 1: Get NLTagger baseline segmentation
        let rawTokens = nlTaggerSegment(text)

        // Step 2: Refine Chinese word tokens with dictionary
        return refinedSegmentation(rawTokens, in: text)
    }

    /// Segment into individual characters (for character-level mode).
    func segmentCharacters(_ text: String) -> [Token] {
        text.indices.map { index in
            let nextIndex = text.index(after: index)
            let char = text[index]
            let type: TokenType = if char.isChineseCharacter {
                .character
            } else if char.isPunctuation || char.isChinesePunctuation {
                .punctuation
            } else if char.isWhitespace || char.isNewline {
                .whitespace
            } else if char.isNumber {
                .number
            } else {
                .other
            }
            return Token(
                text: String(char),
                range: index..<nextIndex,
                type: type,
                pos: .unknown,
                isInDictionary: false
            )
        }
    }

    /// Check if a string contains Chinese characters.
    func containsChinese(_ text: String) -> Bool {
        text.contains(where: \.isChineseCharacter)
    }

    /// Resolve the word at a specific character position in context.
    /// Used for tap-to-define: given surrounding text and the clicked offset,
    /// returns the word that contains that character.
    func resolveWordAtPosition(context: String, charIndex: Int) -> String {
        let tokens = segmentWords(context)
        var offset = 0
        for token in tokens {
            let tokenLen = token.text.count
            if charIndex >= offset && charIndex < offset + tokenLen {
                if token.type == .word {
                    return token.text
                }
                break
            }
            offset += tokenLen
        }

        // Fallback: dictionary window search
        return dictionaryWindowSearch(context: context, at: charIndex)
    }

    /// Expression-first resolution: tries ExpressionDetector first (longest multi-word match),
    /// then falls back to word segmentation.
    ///
    /// This is the preferred entry point for tap-to-define. Clicking 得 in 不得不 returns
    /// 不得不 rather than 得.
    func resolveExpressionAtPosition(context: String, charIndex: Int) -> String {
        let chars = Array(context)
        guard charIndex < chars.count else {
            return resolveWordAtPosition(context: context, charIndex: charIndex)
        }

        // Run ExpressionDetector over the context window.
        // Find the longest expression whose range covers charIndex.
        let detector = ExpressionDetector()
        let expressions = detector.detect(in: context)

        // Map charIndex (code-point index) to String.Index in context.
        let targetIndex = context.index(context.startIndex, offsetBy: charIndex, limitedBy: context.endIndex)
            ?? context.endIndex

        // Among all expressions covering the target character, prefer the longest.
        var bestExpression: ExpressionDetector.Expression?
        for expr in expressions {
            guard expr.range.contains(targetIndex) || expr.range.lowerBound == targetIndex else { continue }
            // Skip single-char grammar markers (把, 被) — they add no value over word lookup
            if expr.type == .grammarPattern && expr.text.count == 1 { continue }
            if let best = bestExpression {
                if expr.text.count > best.text.count {
                    bestExpression = expr
                }
            } else {
                bestExpression = expr
            }
        }

        if let expr = bestExpression, expr.text.count >= 2 {
            return expr.text
        }

        // No multi-word expression covers this position — fall back to word segmentation.
        return resolveWordAtPosition(context: context, charIndex: charIndex)
    }

    // MARK: - Layer 1: NLTagger

    private func nlTaggerSegment(_ text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.tokenType, .lexicalClass])
        tagger.string = text

        var tokens: [Token] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .tokenType
        ) { tag, range in
            let substring = String(text[range])
            let type: TokenType = switch tag {
            case .word: .word
            case .punctuation: .punctuation
            case .whitespace: .whitespace
            case .number: .number
            default: .other
            }

            // Get POS from lexicalClass scheme
            let posTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            let pos = mapPOS(posTag)

            tokens.append(Token(
                text: substring,
                range: range,
                type: type,
                pos: pos,
                isInDictionary: false
            ))
            return true
        }

        return tokens
    }

    // MARK: - Layer 2: Dictionary Refinement

    /// Refine NLTagger output using CC-CEDICT dictionary.
    /// - Merge adjacent tokens that form a dictionary entry (fix over-segmentation)
    /// - Split tokens that contain multiple dictionary entries (fix under-segmentation)
    private func refinedSegmentation(_ tokens: [Token], in text: String) -> [Token] {
        let dict = DictionaryEngine.shared
        var refined: [Token] = []
        var i = 0

        while i < tokens.count {
            let token = tokens[i]

            // Only refine Chinese word tokens
            guard token.type == .word, containsChinese(token.text) else {
                refined.append(token)
                i += 1
                continue
            }

                // For the Chinese segment, do dictionary-based longest match
            // Collect consecutive Chinese tokens into a single string
            var chineseRun = token.text
            var runEnd = i + 1
            while runEnd < tokens.count && tokens[runEnd].type == .word && containsChinese(tokens[runEnd].text) {
                chineseRun += tokens[runEnd].text
                runEnd += 1
            }

            if chineseRun.count > 1 {
                // Re-segment the Chinese run using dictionary longest-match
                let dictTokens = dictionarySegment(chineseRun, startRange: token.range, in: text)
                refined.append(contentsOf: dictTokens)
                i = runEnd
            } else {
                // Single character — check if it's in dictionary
                var t = token
                t = Token(
                    text: token.text,
                    range: token.range,
                    type: token.type,
                    pos: token.pos,
                    isInDictionary: dict.contains(token.text)
                )
                refined.append(t)
                i += 1
            }
        }

        return refined
    }

    /// Dictionary-based longest-match segmentation for a Chinese string.
    /// This is the core algorithm that makes the parser better than NLTagger alone.
    private func dictionarySegment(_ text: String, startRange: Range<String.Index>, in fullText: String) -> [Token] {
        let dict = DictionaryEngine.shared
        let chars = Array(text)
        var tokens: [Token] = []
        var pos = 0

        while pos < chars.count {
            var bestLen = 1 // Default: single character

            // Try longest match first (up to 6 characters — covers most Chinese words)
            for len in stride(from: min(6, chars.count - pos), through: 2, by: -1) {
                let candidate = String(chars[pos..<pos + len])
                if dict.contains(candidate) {
                    bestLen = len
                    break
                }
            }

            // Also check NLTagger's opinion for this segment
            let wordText = String(chars[pos..<pos + bestLen])

            // Calculate range in full text
            let startOffset = text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: pos))
            let tokenStart = fullText.index(startRange.lowerBound, offsetBy: startOffset, limitedBy: fullText.endIndex) ?? fullText.endIndex
            let tokenEnd = fullText.index(tokenStart, offsetBy: bestLen, limitedBy: fullText.endIndex) ?? fullText.endIndex

            tokens.append(Token(
                text: wordText,
                range: tokenStart..<tokenEnd,
                type: .word,
                pos: .unknown,
                isInDictionary: dict.contains(wordText)
            ))

            pos += bestLen
        }

        return tokens
    }

    /// Fallback word search: try dictionary windows around the clicked position.
    private func dictionaryWindowSearch(context: String, at charIndex: Int) -> String {
        let chars = Array(context)
        guard charIndex < chars.count else { return String(chars.last ?? Character(" ")) }
        let dict = DictionaryEngine.shared

        // Try windows centered on the clicked character
        // Priority: longer matches that START at or before the click position
        for start in stride(from: max(0, charIndex - 3), through: charIndex, by: 1) {
            for len in stride(from: min(6, chars.count - start), through: 2, by: -1) {
                let end = start + len
                guard end <= chars.count else { continue }
                guard end > charIndex else { continue } // Must include clicked char
                let candidate = String(chars[start..<end])
                if dict.contains(candidate) {
                    return candidate
                }
            }
        }

        // Single character fallback
        return String(chars[charIndex])
    }

    // MARK: - POS Mapping

    private func mapPOS(_ tag: NLTag?) -> PartOfSpeech {
        guard let tag else { return .unknown }
        return switch tag {
        case .noun: .noun
        case .verb: .verb
        case .adjective: .adjective
        case .adverb: .adverb
        case .pronoun: .pronoun
        case .preposition: .preposition
        case .conjunction: .conjunction
        case .particle: .particle
        case .classifier: .classifier
        case .number: .number
        case .determiner: .determiner
        case .interjection: .interjection
        default: .other
        }
    }
}

// MARK: - Character Extensions

extension Character {
    /// CJK Unified Ideographs (comprehensive check)
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)     // CJK Unified
            || (0x3400...0x4DBF).contains(v)     // Extension A
            || (0x20000...0x2A6DF).contains(v)   // Extension B
            || (0xF900...0xFAFF).contains(v)     // Compatibility
            || (0x2F800...0x2FA1F).contains(v)   // Compatibility Supplement
            || (0x2A700...0x2B73F).contains(v)   // Extension C
            || (0x2B740...0x2B81F).contains(v)   // Extension D
    }

    /// Chinese-specific punctuation marks
    var isChinesePunctuation: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x3000...0x303F).contains(v)     // CJK Symbols
            || (0xFF00...0xFF60).contains(v)     // Fullwidth Forms
            || (0xFE30...0xFE4F).contains(v)     // CJK Compatibility Forms
    }
}
