import Foundation
import SwiftData

@Model
final class VocabularyEntry {
    var id: UUID
    var text: String
    var pinyin: String
    var definition: String
    var state: FamiliarityState
    var encounterCount: Int
    var firstSeenAt: Date
    var lastSeenAt: Date
    var manuallyMarkedAt: Date?

    init(
        text: String,
        pinyin: String = "",
        definition: String = "",
        state: FamiliarityState = .unknown
    ) {
        self.id = UUID()
        self.text = text
        self.pinyin = pinyin
        self.definition = definition
        self.state = state
        self.encounterCount = 0
        self.firstSeenAt = Date()
        self.lastSeenAt = Date()
        self.manuallyMarkedAt = nil
    }
}

/// 5-state familiarity progression.
/// States can only move UP (toward .known) unless explicitly overridden by the user.
enum FamiliarityState: Int, Codable, CaseIterable, Comparable {
    case unknown = 0
    case seen = 1
    case learning = 2
    case familiar = 3
    case known = 4

    static func < (lhs: FamiliarityState, rhs: FamiliarityState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .seen: "Seen"
        case .learning: "Learning"
        case .familiar: "Familiar"
        case .known: "Known"
        }
    }

    /// CSS color for highlight overlay in the reader
    var highlightColor: String {
        switch self {
        case .unknown: "rgba(239, 68, 68, 0.25)"    // Red
        case .seen: "rgba(249, 115, 22, 0.20)"       // Orange
        case .learning: "rgba(234, 179, 8, 0.18)"    // Yellow
        case .familiar: "rgba(156, 163, 175, 0.10)"  // Light gray
        case .known: "transparent"                     // Invisible
        }
    }
}
