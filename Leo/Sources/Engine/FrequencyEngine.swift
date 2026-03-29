import Foundation

/// Word frequency intelligence powered by multi-corpus data.
/// Provides composite frequency scoring and tier classification.
///
/// Architecture: Layered data sources, merged into a composite rank
/// - Primary (composite): composite_frequency.json — weighted blend of three corpora:
///     • TUBELEX-ZH (weight 0.45) — 414K words from YouTube subtitles (modern spoken Chinese)
///     • SUBTLEX-CH (weight 0.30) — 99K words from film/TV subtitles (media Chinese)
///     • BCC/BLCU   (weight 0.25) — 1.8M words from 15B-char balanced corpus (comprehensive)
///   Combined into 80K composite-ranked entries.
/// - Supplementary: hsk_vocabulary.json — provides HSK 3.0 level tags and fills gaps
///   for educational vocabulary not well-represented in media corpora.
///
/// Composite rank takes priority for tier assignment; HSK rank used as fallback.
final class FrequencyEngine: @unchecked Sendable {
    static let shared = FrequencyEngine()

    struct FrequencyData: Sendable {
        let word: String
        let rank: Int           // 1 = most frequent (composite corpus rank)
        let tier: FrequencyTier
        let hskLevel: Int?      // HSK 3.0 level (1-7), nil if not in HSK
        let sources: CorpusSources  // which corpora contain this word
    }

    /// Which corpora contributed data for a word.
    struct CorpusSources: OptionSet, Sendable {
        let rawValue: UInt8
        static let tubelex = CorpusSources(rawValue: 1 << 0)
        static let subtlex = CorpusSources(rawValue: 1 << 1)
        static let bcc     = CorpusSources(rawValue: 1 << 2)
        static let hsk     = CorpusSources(rawValue: 1 << 3)
        static let none    = CorpusSources([])
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

    // MARK: - Internal state

    private struct CompositeEntry {
        let rank: Int
        let sources: CorpusSources
    }

    private var compositeMap: [String: CompositeEntry] = [:]
    private var hskMap: [String: (rank: Int, hskLevel: Int?)] = [:]
    private var loaded = false

    private init() {}

    // MARK: - Public API

    func load() {
        guard !loaded else { return }
        loadHSKData()
        loadCompositeData()
        loaded = true
        NSLog("[FrequencyEngine] Loaded %d composite + %d HSK entries", compositeMap.count, hskMap.count)
    }

    /// Look up frequency data for a word.
    func lookup(_ word: String) -> FrequencyData {
        let hskEntry = hskMap[word]
        let hskLevel = hskEntry?.hskLevel

        if let composite = compositeMap[word] {
            var sources = composite.sources
            if hskEntry != nil { sources.insert(.hsk) }
            return FrequencyData(
                word: word,
                rank: composite.rank,
                tier: tierForRank(composite.rank),
                hskLevel: hskLevel,
                sources: sources
            )
        }

        // Fall back to HSK rank for educational vocabulary absent from media corpora
        if let hsk = hskEntry {
            return FrequencyData(
                word: word,
                rank: hsk.rank,
                tier: tierForRank(hsk.rank),
                hskLevel: hskLevel,
                sources: .hsk
            )
        }

        // Unknown word — check dictionary to distinguish uncommon vs rare
        let inDict = DictionaryEngine.shared.contains(word)
        return FrequencyData(
            word: word,
            rank: inDict ? 8000 : 50000,
            tier: inDict ? .uncommon : .rare,
            hskLevel: nil,
            sources: .none
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

    // MARK: - Private: loading

    /// Load composite_frequency.json — the primary multi-corpus frequency source.
    /// Format: [{"word":"...","rank":N,"tubelex":N?,"subtlex":N?,"bcc":N?}]
    private func loadCompositeData() {
        guard let path = findResourcePath(name: "composite_frequency", ext: "json") else {
            NSLog("[FrequencyEngine] composite_frequency.json not found — using HSK only")
            return
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            NSLog("[FrequencyEngine] Failed to read composite_frequency.json at %@", path)
            return
        }

        struct CompositeRecord: Decodable {
            let word: String
            let rank: Int
            let tubelex: Int?
            let subtlex: Int?
            let bcc: Int?
        }

        let records: [CompositeRecord]
        do {
            records = try JSONDecoder().decode([CompositeRecord].self, from: data)
        } catch {
            NSLog("[FrequencyEngine] composite_frequency.json decode error: %@", error.localizedDescription)
            return
        }

        var map: [String: CompositeEntry] = [:]
        map.reserveCapacity(records.count)

        for record in records {
            var sources = CorpusSources.none
            if record.tubelex != nil { sources.insert(.tubelex) }
            if record.subtlex != nil { sources.insert(.subtlex) }
            if record.bcc     != nil { sources.insert(.bcc) }
            map[record.word] = CompositeEntry(rank: record.rank, sources: sources)
        }

        compositeMap = map
    }

    /// Load hsk_vocabulary.json for HSK level tags and educational vocabulary fallback.
    /// Each entry carries a real corpus frequency rank and HSK 3.0 level tag.
    ///
    /// Level parsing rules:
    /// - "new-N"    → HSK 3.0 level N (primary designation)
    /// - "newest-N" → HSK 3.0 level N (newest additions to the standard)
    /// - "old-*"    → legacy HSK 2.0 designation, ignored for level assignment
    /// - When multiple qualifying levels exist, the lowest (most basic) is used.
    private func loadHSKData() {
        guard let path = findResourcePath(name: "hsk_vocabulary", ext: "json") else {
            NSLog("[FrequencyEngine] hsk_vocabulary.json not found — HSK level data unavailable")
            return
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            NSLog("[FrequencyEngine] Failed to read hsk_vocabulary.json at %@", path)
            return
        }

        struct HSKEntry: Decodable {
            let simplified: String
            let level: [String]
            let frequency: Int
        }

        let entries: [HSKEntry]
        do {
            entries = try JSONDecoder().decode([HSKEntry].self, from: data)
        } catch {
            NSLog("[FrequencyEngine] hsk_vocabulary.json decode error: %@", error.localizedDescription)
            return
        }

        var map: [String: (rank: Int, hskLevel: Int?)] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries {
            map[entry.simplified] = (rank: entry.frequency, hskLevel: parseHSKLevel(from: entry.level))
        }
        hskMap = map
    }

    // MARK: - Private: helpers

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

    /// Resolve a resource path using the same multi-location fallback as DictionaryEngine.
    private func findResourcePath(name: String, ext: String) -> String? {
        // 1. SPM bundle resource (primary for app targets)
        if let url = Bundle.module_safe?.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Dictionary"
        ) {
            return url.path
        }

        // 2. Main bundle flat resource lookup
        if let path = Bundle.main.path(forResource: name, ofType: ext) {
            return path
        }

        // 3. App bundle relative paths + development fallbacks
        let execDir = Bundle.main.bundlePath
        let candidates = [
            "\(execDir)/../Resources/Dictionary/\(name).\(ext)",
            "\(execDir)/Contents/Resources/Dictionary/\(name).\(ext)",
            "\(execDir)/../../Sources/Resources/Dictionary/\(name).\(ext)",
            "Sources/Resources/Dictionary/\(name).\(ext)",
            "Leo/Sources/Resources/Dictionary/\(name).\(ext)",
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
