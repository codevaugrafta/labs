import Foundation
import SwiftData

@Model
final class FSRSCard {
    var id: UUID
    var word: String
    var stability: Double
    var difficulty: Double
    var dueDate: Date
    var lastReviewDate: Date?
    var reviewCount: Int
    var lapseCount: Int
    var state: CardState
    var createdAt: Date
    /// Per-card trainable decay (FSRS v6 w[20]). Nil means use global param default.
    var decay: Double?
    /// The sentence in which the word was encountered. Nil for cards created without context.
    var contextSentence: String?
    /// AI-generated contextual gloss for the word in context. Nil when not yet computed or unavailable.
    var contextualDefinition: String?

    init(word: String) {
        self.id = UUID()
        self.word = word
        self.stability = 0
        self.difficulty = 0
        self.dueDate = Date()
        self.lastReviewDate = nil
        self.reviewCount = 0
        self.lapseCount = 0
        self.state = .new
        self.createdAt = Date()
        self.decay = nil
        self.contextSentence = nil
        self.contextualDefinition = nil
    }
}

enum CardState: Int, Codable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

enum Rating: Int, Codable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}
