import Foundation
import SwiftData

/// FSRS v6 implementation in Swift.
/// Free Spaced Repetition Scheduler — 21 parameters controlling review intervals.
/// v6 adds trainable decay (w[20]) and same-day S power (w[19]).
/// Reference: https://github.com/open-spaced-repetition/py-fsrs
@MainActor
final class FSRSEngine {
    private let modelContext: ModelContext

    // FSRS v6 default parameters (21 values, w[0]..w[20])
    // These can be optimized per-user with enough review data.
    // w[20] = -0.5 matches FSRS v5 fixed decay exactly (backwards compatible).
    private let w: [Double] = [
        0.40255,   // w0:  S0(Again) — initial stability for Again
        1.18385,   // w1:  S0(Hard)  — initial stability for Hard
        3.173,     // w2:  S0(Good)  — initial stability for Good
        15.69105,  // w3:  S0(Easy)  — initial stability for Easy
        7.1949,    // w4:  D0 weight
        0.5345,    // w5:  D0 exp decay
        1.4604,    // w6:  difficulty delta weight
        0.0046,    // w7:  mean reversion weight
        1.54575,   // w8:  recall stability exponent
        0.1192,    // w9:  recall stability S power
        1.01925,   // w10: recall stability R term
        1.9395,    // w11: forget stability factor
        0.11,      // w12: forget stability D power
        0.29605,   // w13: forget stability S power
        2.2698,    // w14: forget stability R term
        0.2315,    // w15: hard penalty
        2.9898,    // w16: easy bonus
        0.51655,   // w17: same-day exp weight
        0.6621,    // w18: same-day grade offset
        0.0,       // w19: same-day S power (NEW in v6)
        -0.5,      // w20: trainable decay (NEW in v6; default -0.5 matches v5)
    ]

    /// Threshold in days below which a review is considered same-day / short-term.
    private static let sameDayThreshold: Double = 1.0

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
            card.dueDate = now.addingTimeInterval(nextInterval(stability: s, card: card) * 86400)

        case .learning, .relearning:
            if rating == .again {
                card.lapseCount += 1
                card.stability = max(0.1, card.stability * 0.2)
                card.dueDate = now.addingTimeInterval(60) // 1 minute
            } else {
                card.state = .review
                let s = nextStability(card: card, rating: rating, now: now)
                card.stability = s
                card.difficulty = nextDifficulty(d: card.difficulty, rating: rating)
                card.dueDate = now.addingTimeInterval(nextInterval(stability: s, card: card) * 86400)
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
                let s = nextStability(card: card, rating: rating, now: now)
                card.stability = s
                card.difficulty = nextDifficulty(d: card.difficulty, rating: rating)
                card.dueDate = now.addingTimeInterval(nextInterval(stability: s, card: card) * 86400)
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

    /// Create a new card for a word, optionally storing the sentence context and AI-generated definition.
    func createCard(for word: String, context: String? = nil, definition: String? = nil) -> FSRSCard {
        let card = FSRSCard(word: word)
        card.contextSentence = context
        card.contextualDefinition = definition
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

    // MARK: - FSRS v6 Core Functions

    private func initialStability(rating: Rating) -> Double {
        w[rating.rawValue - 1]
    }

    private func initialDifficulty(rating: Rating) -> Double {
        let d = w[4] - exp(Double(rating.rawValue - 1) * w[5]) + 1.0
        return clampDifficulty(d)
    }

    private func nextDifficulty(d: Double, rating: Rating) -> Double {
        let delta = d - w[6] * (Double(rating.rawValue) - 3.0)
        let newD = w[7] * initialDifficulty(rating: .easy) + (1.0 - w[7]) * delta
        return clampDifficulty(newD)
    }

    /// Route to same-day or long-term stability formula based on elapsed time.
    private func nextStability(card: FSRSCard, rating: Rating, now: Date) -> Double {
        let elapsed = elapsedDays(card: card, now: now)
        if elapsed < Self.sameDayThreshold {
            return nextSameDayStability(card: card, rating: rating)
        } else {
            return nextRecallStability(card: card, rating: rating)
        }
    }

    /// v6 same-day (short-term) stability formula:
    /// S'(S,G) = S * e^(w[17] * (G - 3 + w[18])) * S^(-w[19])
    private func nextSameDayStability(card: FSRSCard, rating: Rating) -> Double {
        let s = card.stability
        let g = Double(rating.rawValue)
        let newS = s
            * exp(w[17] * (g - 3.0 + w[18]))
            * pow(s, -w[19])
        return max(0.1, newS)
    }

    /// v6 long-term recall stability formula (unchanged from v5 structure):
    /// S'r(D,S,R,G) = S * (e^w[8] * (11-D) * S^(-w[9]) * (e^((1-R)*w[10]) - 1) * hardPenalty * easyBonus + 1)
    private func nextRecallStability(card: FSRSCard, rating: Rating) -> Double {
        let s = card.stability
        let d = card.difficulty
        let r = retrievability(card: card)

        let hardPenalty = rating == .hard ? w[15] : 1.0
        let easyBonus   = rating == .easy  ? w[16] : 1.0

        let newS = s * (1.0 + exp(w[8])
            * (11.0 - d)
            * pow(s, -w[9])
            * (exp((1.0 - r) * w[10]) - 1.0)
            * hardPenalty
            * easyBonus)

        return max(0.1, newS)
    }

    /// v6 forget stability formula (unchanged from v5 structure):
    /// S'f(D,S,R) = w[11] * D^(-w[12]) * ((S+1)^w[13] - 1) * e^((1-R)*w[14])
    private func nextForgetStability(card: FSRSCard) -> Double {
        let s = card.stability
        let d = card.difficulty
        let r = retrievability(card: card)

        let newS = w[11]
            * pow(d, -w[12])
            * (pow(s + 1.0, w[13]) - 1.0)
            * exp((1.0 - r) * w[14])

        return max(0.1, min(newS, s))
    }

    /// v6 retrievability with trainable decay.
    /// R(t, S) = (1 + factor * t/S)^decay
    /// factor = 0.9^(1/decay) - 1  (ensures R(S,S) = 0.9)
    /// decay  = card.decay ?? w[20]  (per-card or global)
    private func retrievability(card: FSRSCard) -> Double {
        guard let lastReview = card.lastReviewDate else { return 1.0 }
        let elapsed = Date().timeIntervalSince(lastReview) / 86400.0
        let decay = card.decay ?? w[20]
        let factor = pow(0.9, 1.0 / decay) - 1.0
        return pow(1.0 + factor * elapsed / card.stability, decay)
    }

    /// v6 next interval formula:
    /// I(r, S) = S / factor * (r^(1/decay) - 1)
    /// where r = desired retention = 0.9
    private func nextInterval(stability: Double, card: FSRSCard) -> Double {
        let requestedRetention = 0.9
        let decay = card.decay ?? w[20]
        let factor = pow(0.9, 1.0 / decay) - 1.0
        let interval = stability / factor * (pow(requestedRetention, 1.0 / decay) - 1.0)
        return max(1.0, min(interval, 36500.0)) // 1 day to 100 years
    }

    private func elapsedDays(card: FSRSCard, now: Date) -> Double {
        guard let lastReview = card.lastReviewDate else { return Double.infinity }
        return now.timeIntervalSince(lastReview) / 86400.0
    }

    private func clampDifficulty(_ d: Double) -> Double {
        max(1.0, min(d, 10.0))
    }

    private func trySave() {
        try? modelContext.save()
    }
}
