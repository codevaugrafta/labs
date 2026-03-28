import Foundation
import SwiftData

@Model
final class ReadingSessionRecord {
    var id: UUID
    var bookTitle: String
    var startedAt: Date
    var endedAt: Date?
    var wordsRead: Int
    var charsRead: Int
    var pagesRead: Int
    var newWordsEncountered: Int
    var comprehensionPct: Double

    init(bookTitle: String) {
        self.id = UUID()
        self.bookTitle = bookTitle
        self.startedAt = Date()
        self.endedAt = nil
        self.wordsRead = 0
        self.charsRead = 0
        self.pagesRead = 0
        self.newWordsEncountered = 0
        self.comprehensionPct = 0
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var charsPerMinute: Double {
        let minutes = duration / 60.0
        guard minutes > 0 else { return 0 }
        return Double(charsRead) / minutes
    }
}
