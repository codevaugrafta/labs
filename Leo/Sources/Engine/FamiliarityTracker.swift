import Foundation
import SwiftData

/// Tracks word familiarity across the 5-state progression.
/// "Moneyball" principle: precise, data-driven transitions. No flickering.
/// States only move UP unless the user explicitly overrides.
@MainActor
final class FamiliarityTracker {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Query

    /// Get the familiarity state for a word. Returns .unknown if not tracked.
    func state(for word: String) -> FamiliarityState {
        guard let entry = fetchEntry(for: word) else { return .unknown }
        return entry.state
    }

    /// Get familiarity states for multiple words at once (batch lookup).
    func states(for words: [String]) -> [String: FamiliarityState] {
        let unique = Set(words)
        var result: [String: FamiliarityState] = [:]

        let descriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { unique.contains($0.text) }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []

        for entry in entries {
            result[entry.text] = entry.state
        }

        // Words not in DB are unknown
        for word in unique where result[word] == nil {
            result[word] = .unknown
        }

        return result
    }

    // MARK: - Transition Events

    /// Record that a word was encountered while reading.
    /// Transitions: Unknown → Seen (first encounter)
    func recordEncounter(_ word: String, pinyin: String = "", definition: String = "") {
        let entry = fetchOrCreateEntry(for: word, pinyin: pinyin, definition: definition)
        entry.encounterCount += 1
        entry.lastSeenAt = Date()

        // Only promote Unknown → Seen on encounter
        if entry.state == .unknown {
            entry.state = .seen
        }

        trySave()
    }

    /// Record multiple word encounters in batch (efficient for page-level processing).
    func recordEncounters(_ words: [(text: String, pinyin: String, definition: String)]) {
        for word in words {
            recordEncounter(word.text, pinyin: word.pinyin, definition: word.definition)
        }
    }

    /// User manually marks a word as known.
    /// This is an explicit override — jumps straight to .known regardless of current state.
    func markAsKnown(_ word: String) {
        let entry = fetchOrCreateEntry(for: word)
        entry.state = .known
        entry.manuallyMarkedAt = Date()
        trySave()
    }

    /// User adds word to SRS (learning).
    /// Transitions: any state → .learning (or stays if already learning/familiar/known)
    func markAsLearning(_ word: String) {
        let entry = fetchOrCreateEntry(for: word)
        if entry.state < .learning {
            entry.state = .learning
        }
        trySave()
    }

    /// FSRS-driven promotion: learning → familiar based on stability threshold.
    func promoteToFamiliar(_ word: String) {
        guard let entry = fetchEntry(for: word) else { return }
        if entry.state == .learning {
            entry.state = .familiar
        }
        trySave()
    }

    /// FSRS-driven promotion: familiar → known based on maturity threshold.
    func promoteToKnown(_ word: String) {
        guard let entry = fetchEntry(for: word) else { return }
        if entry.state == .familiar {
            entry.state = .known
            entry.manuallyMarkedAt = nil // Not manual — earned through review
        }
        trySave()
    }

    /// Apply bulk word states (e.g. Anki import). Promotes each word to the higher of current vs imported.
    func applyImportedStates(_ pairs: [(word: String, state: FamiliarityState)]) {
        for pair in pairs {
            let entry = fetchOrCreateEntry(for: pair.word)
            if pair.state.rawValue > entry.state.rawValue {
                entry.state = pair.state
            }
        }
        trySave()
    }

    /// Explicit user reset — the ONLY way a state moves backward.
    func resetState(_ word: String, to newState: FamiliarityState) {
        guard let entry = fetchEntry(for: word) else { return }
        entry.state = newState
        if newState == .known {
            entry.manuallyMarkedAt = Date()
        }
        trySave()
    }

    // MARK: - Comprehension

    /// Calculate comprehension percentage for a list of words.
    /// Returns the ratio of known+familiar words to total words.
    func comprehensionScore(for words: [String]) -> Double {
        guard !words.isEmpty else { return 0 }
        let stateMap = states(for: words)
        let comprehended = words.filter { word in
            let state = stateMap[word] ?? .unknown
            return state >= .familiar
        }.count
        return Double(comprehended) / Double(words.count)
    }

    // MARK: - Private

    private func fetchEntry(for word: String) -> VocabularyEntry? {
        let descriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { $0.text == word }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateEntry(
        for word: String,
        pinyin: String = "",
        definition: String = ""
    ) -> VocabularyEntry {
        if let existing = fetchEntry(for: word) {
            // Update pinyin/definition if provided and currently empty
            if !pinyin.isEmpty && existing.pinyin.isEmpty {
                existing.pinyin = pinyin
            }
            if !definition.isEmpty && existing.definition.isEmpty {
                existing.definition = definition
            }
            return existing
        }

        let entry = VocabularyEntry(
            text: word,
            pinyin: pinyin,
            definition: definition
        )
        modelContext.insert(entry)
        return entry
    }

    private func trySave() {
        try? modelContext.save()
    }
}
