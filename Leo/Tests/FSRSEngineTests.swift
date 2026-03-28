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
}
