import Foundation
import Testing
import SwiftData
@testable import Leo

@Suite("FSRSEngine Tests")
struct FSRSEngineTests {

    @MainActor
    private func makeEngine() throws -> (FSRSEngine, ModelContext) {
        let schema = Schema([FSRSCard.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let engine = FSRSEngine(modelContext: context)
        return (engine, context)
    }

    @Test("Creates a new card")
    @MainActor
    func createCard() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")
        #expect(card.word == "你好")
        #expect(card.state == .new)
        #expect(card.reviewCount == 0)
        #expect(card.stability == 0)
    }

    @Test("First review with Good rating sets stability")
    @MainActor
    func firstReviewGood() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")
        engine.review(card: card, rating: .good)

        #expect(card.stability > 0)
        #expect(card.difficulty > 0)
        #expect(card.state == .review)
        #expect(card.reviewCount == 1)
        #expect(card.dueDate > Date())
    }

    @Test("First review with Again keeps card in learning")
    @MainActor
    func firstReviewAgain() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")
        engine.review(card: card, rating: .again)

        #expect(card.state == .learning)
        #expect(card.reviewCount == 1)
    }

    @Test("Easy rating gives longer interval than Good")
    @MainActor
    func easyVsGood() throws {
        let (engine1, _) = try makeEngine()
        let (engine2, _) = try makeEngine()

        let cardGood = engine1.createCard(for: "你好")
        engine1.review(card: cardGood, rating: .good)

        let cardEasy = engine2.createCard(for: "你好")
        engine2.review(card: cardEasy, rating: .easy)

        #expect(cardEasy.stability > cardGood.stability)
        #expect(cardEasy.dueDate > cardGood.dueDate)
    }

    @Test("Again on review card causes lapse")
    @MainActor
    func lapseTracking() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")

        // First review — Good
        engine.review(card: card, rating: .good)
        #expect(card.lapseCount == 0)

        // Second review — Again (lapse)
        engine.review(card: card, rating: .again)
        #expect(card.lapseCount == 1)
        #expect(card.state == .relearning)
    }

    @Test("Stability increases with successful reviews")
    @MainActor
    func stabilityGrowth() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")

        engine.review(card: card, rating: .good)
        let s1 = card.stability

        // Simulate time passing
        card.lastReviewDate = Date().addingTimeInterval(-86400 * 3) // 3 days ago
        card.dueDate = Date().addingTimeInterval(-86400) // overdue

        engine.review(card: card, rating: .good)
        let s2 = card.stability

        #expect(s2 > s1, "Stability should increase after successful review")
    }

    @Test("Due cards query works")
    @MainActor
    func dueCardsQuery() throws {
        let (engine, _) = try makeEngine()

        // Create a card that's due now
        let card = engine.createCard(for: "你好")
        card.dueDate = Date().addingTimeInterval(-3600) // 1 hour ago

        // Create a card that's not due
        let futureCard = engine.createCard(for: "世界")
        futureCard.dueDate = Date().addingTimeInterval(86400 * 30) // 30 days from now

        let due = engine.dueCards()
        #expect(due.count == 1)
        #expect(due.first?.word == "你好")
    }

    @Test("Difficulty stays within bounds")
    @MainActor
    func difficultyBounds() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")

        // Many Again reviews should increase difficulty but keep it bounded
        for _ in 0..<20 {
            engine.review(card: card, rating: .again)
            card.dueDate = Date().addingTimeInterval(-60) // make it due again
        }
        #expect(card.difficulty >= 1.0)
        #expect(card.difficulty <= 10.0)
    }

    @Test("Interval is at least 1 day for review cards")
    @MainActor
    func minimumInterval() throws {
        let (engine, _) = try makeEngine()
        let card = engine.createCard(for: "你好")
        engine.review(card: card, rating: .good)

        let interval = card.dueDate.timeIntervalSince(Date()) / 86400.0
        #expect(interval >= 0.9) // At least ~1 day (with some time tolerance)
    }

    @Test("Trainable decay affects interval length")
    @MainActor
    func trainableDecayAffectsInterval() throws {
        // A steeper (more negative) decay makes retrievability drop faster,
        // so the engine should schedule a shorter interval to hit 90% retention.
        let (engine1, _) = try makeEngine()
        let (engine2, _) = try makeEngine()

        let cardDefault = engine1.createCard(for: "苹果")
        let cardSteep   = engine2.createCard(for: "苹果")

        // First review to establish stability
        engine1.review(card: cardDefault, rating: .good)
        engine2.review(card: cardSteep, rating: .good)

        // Sanity: both cards should now be in .review state with equal stability
        // (first-review stability is independent of decay)
        #expect(cardDefault.state == .review)
        #expect(cardSteep.state == .review)
        #expect(abs(cardDefault.stability - cardSteep.stability) < 1e-9)

        // Assign a steeper decay to cardSteep (-0.7 < -0.5 in absolute terms)
        cardSteep.decay = -0.7

        // Simulate being overdue so a second review triggers nextRecallStability
        let threeDaysAgo = Date().addingTimeInterval(-86400 * 3)
        cardDefault.lastReviewDate = threeDaysAgo
        cardDefault.dueDate = Date().addingTimeInterval(-86400)
        cardSteep.lastReviewDate = threeDaysAgo
        cardSteep.dueDate = Date().addingTimeInterval(-86400)

        engine1.review(card: cardDefault, rating: .good)
        engine2.review(card: cardSteep,   rating: .good)

        // With a steeper decay the interval to reach 90% retention is shorter
        let intervalDefault = cardDefault.dueDate.timeIntervalSinceNow
        let intervalSteep   = cardSteep.dueDate.timeIntervalSinceNow
        #expect(intervalSteep < intervalDefault,
                "Steeper decay should produce a shorter next interval")
    }

    @Test("Same-day review uses short-term formula")
    @MainActor
    func sameDayReviewUsesShortTermFormula() throws {
        // A review performed seconds after the last review is same-day.
        // The same-day formula multiplies by S^(-w19); with w19 = 0 this equals
        // the exponential factor alone, so stability differs from long-term recall.
        let (engineSameDay, _) = try makeEngine()
        let (engineLongTerm, _) = try makeEngine()

        let cardSameDay  = engineSameDay.createCard(for:  "香蕉")
        let cardLongTerm = engineLongTerm.createCard(for: "香蕉")

        // First review to set initial state
        engineSameDay.review(card: cardSameDay, rating: .good)
        engineLongTerm.review(card: cardLongTerm, rating: .good)

        #expect(abs(cardSameDay.stability - cardLongTerm.stability) < 1e-9,
                "Stability should be equal after first review")

        // For long-term: simulate review 5 days later
        cardLongTerm.lastReviewDate = Date().addingTimeInterval(-86400 * 5)
        cardLongTerm.dueDate = Date().addingTimeInterval(-86400)

        // For same-day: lastReviewDate is just now (seconds ago) — default after review()
        // Both get a Good rating on the second review
        engineSameDay.review(card:  cardSameDay,  rating: .good)
        engineLongTerm.review(card: cardLongTerm, rating: .good)

        // The two paths produce different stability values
        #expect(cardSameDay.stability != cardLongTerm.stability,
                "Same-day and long-term review paths should produce different stability")

        // Same-day stability should still be positive and reasonable
        #expect(cardSameDay.stability > 0)
        #expect(cardLongTerm.stability > cardSameDay.stability,
                "Long-term recall raises stability more than same-day review")
    }
}
