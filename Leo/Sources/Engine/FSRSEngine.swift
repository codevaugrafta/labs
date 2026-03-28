import Foundation
import SwiftData

/// FSRS v5 implementation in Swift.
/// Free Spaced Repetition Scheduler — 19 parameters controlling review intervals.
/// Reference: https://github.com/open-spaced-repetition/py-fsrs
@MainActor
final class FSRSEngine {
    private let modelContext: ModelContext

    // FSRS v5 default parameters (19 values)
    // These can be optimized per-user with enough review data
    private let p: [Double] = [
        0.40255,  // 0: initial stability for Again
        1.18385,  // 1: initial stability for Hard
        3.173,    // 2: initial stability for Good
        15.69105, // 3: initial stability for Easy
        7.1949,   // 4: difficulty weight
        0.5345,   // 5: difficulty decay
        1.4604,   // 6: stability growth after success
        0.0046,   // 7: stability revision factor
        1.54575,  // 8: recall stability factor
        0.1192,   // 9: forget stability factor
        1.01925,  // 10: hard penalty
        1.9395,   // 11: easy bonus
        0.11,     // 12: short-term stability decay
        0.29605,  // 13: short-term stability base
        2.2698,   // 14: stability after forgetting factor
        0.2315,   // 15: stability after forgetting power
        2.9898,   // 16: difficulty after forgetting
        0.51655,  // 17: difficulty revision
        0.6621,   // 18: difficulty stability factor
    ]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Schedule a review for a card based on rating.
    /// Returns the updated card with new due date, stability, and difficulty.
    func review(card: FSRSCard, rating: Rating) {
        let now = Date()

        switch card.state {
        case .new:
            // First review — use initial stability values
            let s = initialStability(rating: rating)
            let d = initialDifficulty(rating: rating)
            card.stability = s
            card.difficulty = d
            card.state = rating == .again ? .learning : .review
            card.dueDate = now.addingTimeInterval(nextInterval(stability: s) * 86400)

        case .learning, .relearning:
            if rating == .again {
                card.lapseCount += 1
                card.stability = max(0.1, card.stability * p[9])
                card.dueDate = now.addingTimeInterval(60) // 1 minute
            } else {
                card.state = .review
                let s = nextRecallStability(card: card, rating: rating)
                card.stability = s
                card.difficulty = nextDifficulty(d: card.difficulty, rating: rating)
                card.dueDate = now.addingTimeInterval(nextInterval(stability: s) * 86400)
            }

        case .review:
            if rating == .again {
                card.lapseCount += 1
                card.state = .relearning
                let s = nextForgetStability(card: card)
                card.stability = s
                card.difficulty = nextDifficulty(d: card.difficulty, rating: rating)
                card.dueDate = now.addingTimeInterval(60) // 1 minute
            } else {
                let s = nextRecallStability(card: card, rating: rating)
                card.stability = s
                card.difficulty = nextDifficulty(d: card.difficulty, rating: rating)
                card.dueDate = now.addingTimeInterval(nextInterval(stability: s) * 86400)
            }
        }

        card.reviewCount += 1
        card.lastReviewDate = now
        trySave()
    }

    /// Get all cards due for review.
    func dueCards() -> [FSRSCard] {
        let now = Date()
        let descriptor = FetchDescriptor<FSRSCard>(
            predicate: #Predicate { $0.dueDate <= now },
            sortBy: [SortDescriptor(\FSRSCard.dueDate)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Create a new card for a word.
    func createCard(for word: String) -> FSRSCard {
        let card = FSRSCard(word: word)
        modelContext.insert(card)
        trySave()
        return card
    }

    /// Get card for a word if it exists.
    func card(for word: String) -> FSRSCard? {
        let descriptor = FetchDescriptor<FSRSCard>(
            predicate: #Predicate { $0.word == word }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Count of cards due for review.
    func dueCount() -> Int {
        dueCards().count
    }

    // MARK: - FSRS v5 Core Functions

    private func initialStability(rating: Rating) -> Double {
        p[rating.rawValue - 1]
    }

    private func initialDifficulty(rating: Rating) -> Double {
        let d = p[4] - exp(Double(rating.rawValue - 1) * p[5]) + 1.0
        return clampDifficulty(d)
    }

    private func nextDifficulty(d: Double, rating: Rating) -> Double {
        let delta = d - p[4] * (Double(rating.rawValue) - 3.0)
        let newD = p[17] * initialDifficulty(rating: .easy) + (1.0 - p[17]) * delta
        return clampDifficulty(newD)
    }

    private func nextRecallStability(card: FSRSCard, rating: Rating) -> Double {
        let s = card.stability
        let d = card.difficulty
        let r = retrievability(card: card)

        let hardPenalty = rating == .hard ? p[10] : 1.0
        let easyBonus = rating == .easy ? p[11] : 1.0

        let newS = s * (1.0 + exp(p[6])
            * (11.0 - d)
            * pow(s, -p[7])
            * (exp((1.0 - r) * p[8]) - 1.0)
            * hardPenalty
            * easyBonus)

        return max(0.1, newS)
    }

    private func nextForgetStability(card: FSRSCard) -> Double {
        let s = card.stability
        let d = card.difficulty
        let r = retrievability(card: card)

        let newS = p[14]
            * pow(d, -p[15])
            * (pow(s + 1.0, p[16]) - 1.0)
            * exp((1.0 - r) * p[18])

        return max(0.1, min(newS, s))
    }

    private func retrievability(card: FSRSCard) -> Double {
        guard let lastReview = card.lastReviewDate else { return 1.0 }
        let elapsed = Date().timeIntervalSince(lastReview) / 86400.0 // days
        return pow(1.0 + elapsed / (9.0 * card.stability), -1.0)
    }

    private func nextInterval(stability: Double) -> Double {
        // Desired retention = 0.9 (90% target)
        let requestedRetention = 0.9
        let interval = 9.0 * stability * (1.0 / requestedRetention - 1.0)
        return max(1.0, min(interval, 36500.0)) // 1 day to 100 years
    }

    private func clampDifficulty(_ d: Double) -> Double {
        max(1.0, min(d, 10.0))
    }

    private func trySave() {
        try? modelContext.save()
    }
}
