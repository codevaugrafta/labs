import Foundation
import NaturalLanguage

/// Multi-level Chinese text segmentation.
/// Layer 1 (this file): Apple NLTagger for on-device word boundary detection.
/// Layer 2 (future): Dictionary-based MWE detection.
/// Layer 3 (future): LLM contextual chunking via OpenRouter.
struct ChineseParser: Sendable {

    struct Token: Sendable, Identifiable {
        let id = UUID()
        let text: String
        let range: Range<String.Index>
        let type: TokenType
    }

    enum TokenType: Sendable {
        case word
        case character
        case punctuation
        case whitespace
        case other
    }

    /// Segment Chinese text into word-level tokens using NLTagger.
    func segmentWords(_ text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.tokenType])
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
            default: .other
            }
            tokens.append(Token(text: substring, range: range, type: type))
            return true
        }

        return tokens
    }

    /// Segment text into individual characters (for character-level mode).
    func segmentCharacters(_ text: String) -> [Token] {
        text.indices.map { index in
            let nextIndex = text.index(after: index)
            let char = text[index]
            let type: TokenType = if char.isChineseCharacter {
                .character
            } else if char.isPunctuation {
                .punctuation
            } else if char.isWhitespace {
                .whitespace
            } else {
                .other
            }
            return Token(
                text: String(char),
                range: index..<nextIndex,
                type: type
            )
        }
    }

    /// Check if a string contains Chinese characters.
    func containsChinese(_ text: String) -> Bool {
        text.contains(where: \.isChineseCharacter)
    }
}

extension Character {
    /// Returns true if this character is in the CJK Unified Ideographs range.
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)    // CJK Unified Ideographs
            || (0x3400...0x4DBF).contains(value)    // CJK Extension A
            || (0x20000...0x2A6DF).contains(value)  // CJK Extension B
            || (0xF900...0xFAFF).contains(value)    // CJK Compatibility Ideographs
            || (0x2F800...0x2FA1F).contains(value)  // CJK Compatibility Supplement
    }
}
