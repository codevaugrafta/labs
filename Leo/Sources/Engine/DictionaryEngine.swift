import Foundation

extension Bundle {
    /// Safe accessor for Bundle.module that returns nil instead of crashing
    /// when resources aren't available (e.g. in test targets without resources).
    static var module_safe: Bundle? {
        let bundleName = "Leo_Leo"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: BundleFinder.self).resourceURL,
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let path = bundlePath, let bundle = Bundle(url: path) {
                return bundle
            }
        }
        return nil
    }

    private class BundleFinder {}
}

/// Offline Chinese-English dictionary powered by CC-CEDICT.
/// Loads 124K+ entries into memory for instant lookup.
final class DictionaryEngine: @unchecked Sendable {
    static let shared = DictionaryEngine()

    struct Entry: Sendable {
        let traditional: String
        let simplified: String
        let pinyin: String
        let pinyinDisplay: String
        let definitions: [String]
    }

    private var simplifiedIndex: [String: [Entry]] = [:]
    private var traditionalIndex: [String: [Entry]] = [:]
    private var loaded = false

    private init() {}

    /// Load dictionary from embedded cedict.txt
    func load(forceReload: Bool = false) {
        guard !loaded || forceReload else { return }
        loaded = false

        guard let path = findDictionaryPath() else {
            print("[DictionaryEngine] cedict.txt not found")
            return
        }

        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            print("[DictionaryEngine] Failed to read cedict.txt")
            return
        }

        var sIndex: [String: [Entry]] = [:]
        var tIndex: [String: [Entry]] = [:]
        sIndex.reserveCapacity(130_000)
        tIndex.reserveCapacity(130_000)

        // CC-CEDICT uses CRLF line endings — normalize before parsing
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n") where !line.hasPrefix("#") && !line.isEmpty {
            guard let entry = parseLine(String(line)) else { continue }
            sIndex[entry.simplified, default: []].append(entry)
            if entry.traditional != entry.simplified {
                tIndex[entry.traditional, default: []].append(entry)
            }
        }

        simplifiedIndex = sIndex
        traditionalIndex = tIndex
        loaded = true
        print("[DictionaryEngine] Loaded \(sIndex.count) simplified entries")
    }

    /// Look up a word (tries simplified first, then traditional)
    func lookup(_ word: String) -> [Entry] {
        if let entries = simplifiedIndex[word], !entries.isEmpty {
            return entries
        }
        if let entries = traditionalIndex[word], !entries.isEmpty {
            return entries
        }
        return []
    }

    /// Check if a word exists in the dictionary
    func contains(_ word: String) -> Bool {
        simplifiedIndex[word] != nil || traditionalIndex[word] != nil
    }

    // MARK: - Private

    private func findDictionaryPath() -> String? {
        // Check SPM bundle resource first
        if let bundleURL = Bundle.module_safe?.url(forResource: "cedict", withExtension: "txt", subdirectory: "Dictionary") {
            return bundleURL.path
        }
        // Check main bundle resources
        if let bundlePath = Bundle.main.path(forResource: "cedict", ofType: "txt") {
            return bundlePath
        }
        // Check app bundle Resources/Dictionary
        let execDir = Bundle.main.bundlePath
        let candidates = [
            "\(execDir)/../Resources/Dictionary/cedict.txt",
            "\(execDir)/Contents/Resources/Dictionary/cedict.txt",
            "\(execDir)/../../Sources/Resources/Dictionary/cedict.txt",
            // Development / test fallback — walk up from working directory
            "Sources/Resources/Dictionary/cedict.txt",
            "Leo/Sources/Resources/Dictionary/cedict.txt",
        ]
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }

    private func parseLine(_ line: String) -> Entry? {
        // Format: Traditional Simplified [pinyin] /def1/def2/
        guard let bracketOpen = line.firstIndex(of: "["),
              let bracketClose = line.firstIndex(of: "]"),
              let slashStart = line.firstIndex(of: "/") else {
            return nil
        }

        let beforeBracket = line[line.startIndex..<bracketOpen]
        let parts = beforeBracket.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let traditional = String(parts[0])
        let simplified = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let pinyinRaw = String(line[line.index(after: bracketOpen)..<bracketClose])
        let pinyinDisplay = convertPinyinNumbers(pinyinRaw)

        let defsString = String(line[slashStart...])
        let definitions = defsString
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Entry(
            traditional: traditional,
            simplified: simplified,
            pinyin: pinyinRaw,
            pinyinDisplay: pinyinDisplay,
            definitions: definitions
        )
    }

    /// Convert numbered pinyin (hao3) to tone-marked pinyin (hǎo)
    private func convertPinyinNumbers(_ input: String) -> String {
        let syllables = input.split(separator: " ")
        return syllables.map { convertSyllable(String($0)) }.joined(separator: " ")
    }

    private func convertSyllable(_ s: String) -> String {
        guard let last = s.last, last.isNumber, let tone = Int(String(last)) else { return s }
        let base = String(s.dropLast())
        return applyToneMark(to: base, tone: tone)
    }

    private func applyToneMark(to syllable: String, tone: Int) -> String {
        guard tone >= 1 && tone <= 4 else { return syllable }

        let toneMarks: [Character: [Character]] = [
            "a": ["ā", "á", "ǎ", "à"],
            "e": ["ē", "é", "ě", "è"],
            "i": ["ī", "í", "ǐ", "ì"],
            "o": ["ō", "ó", "ǒ", "ò"],
            "u": ["ū", "ú", "ǔ", "ù"],
            "ü": ["ǖ", "ǘ", "ǚ", "ǜ"],
        ]

        let lower = syllable.lowercased()
        var chars = Array(lower)

        // Find the vowel to mark (standard rules: a/e always get it, ou marks o, otherwise last vowel)
        if let idx = chars.firstIndex(of: "a") ?? chars.firstIndex(of: "e") {
            if let marks = toneMarks[chars[idx]] {
                chars[idx] = marks[tone - 1]
            }
        } else if let idx = chars.lastIndex(where: { "iouü".contains($0) }) {
            let c = chars[idx] == "v" ? Character("ü") : chars[idx]
            if let marks = toneMarks[c] {
                chars[idx] = marks[tone - 1]
            }
        }

        return String(chars)
    }
}
