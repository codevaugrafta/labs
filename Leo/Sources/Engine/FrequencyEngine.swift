import Foundation

/// Word frequency intelligence powered by HSK 3.0 corpus data.
/// Provides composite frequency scoring and tier classification.
///
/// Architecture: Layered data sources
/// - Layer 1 (active): HSK 3.0 vocabulary JSON (11,470 entries, real corpus frequency ranks)
/// - Layer 2 (future): SUBTLEX-CH (film/TV subtitle frequencies)
/// - Layer 3 (future): TUBELEX-ZH (YouTube subtitle frequencies)
/// - Layer 4 (future): BCC (15B char comprehensive corpus)
final class FrequencyEngine: @unchecked Sendable {
    static let shared = FrequencyEngine()

    struct FrequencyData: Sendable {
        let word: String
        let rank: Int           // 1 = most frequent (corpus rank from hsk_vocabulary.json)
        let tier: FrequencyTier
        let hskLevel: Int?      // HSK 3.0 level (1-7), nil if not in HSK or only legacy data
    }

    enum FrequencyTier: String, Sendable, Comparable {
        case top500 = "Top 500"
        case top2000 = "Top 2000"
        case top5000 = "Top 5000"
        case common = "Common"
        case uncommon = "Uncommon"
        case rare = "Rare"

        static func < (lhs: FrequencyTier, rhs: FrequencyTier) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }

        var sortOrder: Int {
            switch self {
            case .top500: 0
            case .top2000: 1
            case .top5000: 2
            case .common: 3
            case .uncommon: 4
            case .rare: 5
            }
        }

        var color: String {
            switch self {
            case .top500: "#22c55e"    // Green — very common
            case .top2000: "#3b82f6"   // Blue
            case .top5000: "#8b5cf6"   // Purple
            case .common: "#6b7280"    // Gray
            case .uncommon: "#f59e0b"  // Amber
            case .rare: "#ef4444"      // Red — rare
            }
        }
    }

    private var frequencyMap: [String: (rank: Int, hskLevel: Int?)] = [:]
    private var loaded = false

    private init() {}

    func load() {
        guard !loaded else { return }
        buildFrequencyMap()
        loaded = true
        NSLog("[FrequencyEngine] Loaded %d frequency entries", frequencyMap.count)
    }

    /// Look up frequency data for a word.
    func lookup(_ word: String) -> FrequencyData {
        if let data = frequencyMap[word] {
            return FrequencyData(
                word: word,
                rank: data.rank,
                tier: tierForRank(data.rank),
                hskLevel: data.hskLevel
            )
        }
        // Unknown word — check dictionary to distinguish uncommon vs rare
        let inDict = DictionaryEngine.shared.contains(word)
        return FrequencyData(
            word: word,
            rank: inDict ? 8000 : 50000,
            tier: inDict ? .uncommon : .rare,
            hskLevel: nil
        )
    }

    /// Calculate weighted comprehension score.
    /// Missing a common word hurts more than missing a rare word.
    func weightedComprehension(knownWords: Set<String>, allWords: [String]) -> Double {
        guard !allWords.isEmpty else { return 0 }
        var totalWeight = 0.0
        var knownWeight = 0.0
        for word in allWords {
            let freq = lookup(word)
            let weight = weightForTier(freq.tier)
            totalWeight += weight
            if knownWords.contains(word) {
                knownWeight += weight
            }
        }
        return totalWeight > 0 ? knownWeight / totalWeight : 0
    }

    // MARK: - Private

    private func tierForRank(_ rank: Int) -> FrequencyTier {
        switch rank {
        case 1...500: .top500
        case 501...2000: .top2000
        case 2001...5000: .top5000
        case 5001...10000: .common
        case 10001...30000: .uncommon
        default: .rare
        }
    }

    private func weightForTier(_ tier: FrequencyTier) -> Double {
        switch tier {
        case .top500: 3.0
        case .top2000: 2.5
        case .top5000: 2.0
        case .common: 1.5
        case .uncommon: 1.0
        case .rare: 0.5
        }
    }

    /// Build frequency map from hsk_vocabulary.json.
    /// Each entry carries a real corpus frequency rank and HSK 3.0 level tag.
    ///
    /// Level parsing rules:
    /// - "new-N"    → HSK 3.0 level N (primary designation)
    /// - "newest-N" → HSK 3.0 level N (newest additions to the standard)
    /// - "old-*"    → legacy HSK 2.0 designation, ignored for level assignment
    /// - When multiple qualifying levels exist, the lowest (most basic) is used.
    private func buildFrequencyMap() {
        guard let path = findVocabularyPath() else {
            NSLog("[FrequencyEngine] hsk_vocabulary.json not found — frequency data unavailable")
            return
        }

        guard let data = FileManager.default.contents(atPath: path) else {
            NSLog("[FrequencyEngine] Failed to read hsk_vocabulary.json at %@", path)
            return
        }

        // Minimal Decodable types — only the fields we need
        struct HSKEntry: Decodable {
            let simplified: String
            let level: [String]
            let frequency: Int
        }

        let entries: [HSKEntry]
        do {
            entries = try JSONDecoder().decode([HSKEntry].self, from: data)
        } catch {
            NSLog("[FrequencyEngine] JSON decode error: %@", error.localizedDescription)
            return
        }

        var map: [String: (rank: Int, hskLevel: Int?)] = [:]
        map.reserveCapacity(entries.count)

        for entry in entries {
            let hskLevel = parseHSKLevel(from: entry.level)
            map[entry.simplified] = (rank: entry.frequency, hskLevel: hskLevel)
        }

        frequencyMap = map
    }

    /// Parse HSK 3.0 level from a level tag array.
    /// Accepts "new-N" and "newest-N" prefixes; ignores "old-*".
    /// Returns the lowest (most basic) level when multiple qualify.
    private func parseHSKLevel(from levels: [String]) -> Int? {
        var lowestLevel: Int? = nil
        for tag in levels {
            let level: Int?
            if tag.hasPrefix("new-") {
                level = Int(tag.dropFirst(4))
            } else if tag.hasPrefix("newest-") {
                level = Int(tag.dropFirst(7))
            } else {
                // "old-*" — legacy HSK 2.0, skip
                continue
            }
            if let l = level {
                if lowestLevel == nil || l < lowestLevel! {
                    lowestLevel = l
                }
            }
        }
        return lowestLevel
    }

    /// Resolve path to hsk_vocabulary.json using the same multi-location
    /// fallback strategy as DictionaryEngine.
    private func findVocabularyPath() -> String? {
        // 1. SPM bundle resource (primary for app targets)
        if let url = Bundle.module_safe?.url(
            forResource: "hsk_vocabulary",
            withExtension: "json",
            subdirectory: "Dictionary"
        ) {
            return url.path
        }

        // 2. Main bundle flat resource lookup
        if let path = Bundle.main.path(forResource: "hsk_vocabulary", ofType: "json") {
            return path
        }

        // 3. App bundle relative paths + development fallbacks
        let execDir = Bundle.main.bundlePath
        let candidates = [
            "\(execDir)/../Resources/Dictionary/hsk_vocabulary.json",
            "\(execDir)/Contents/Resources/Dictionary/hsk_vocabulary.json",
            "\(execDir)/../../Sources/Resources/Dictionary/hsk_vocabulary.json",
            "Sources/Resources/Dictionary/hsk_vocabulary.json",
            "Leo/Sources/Resources/Dictionary/hsk_vocabulary.json",
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
