import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var filePath: String
    var format: BookFormat
    var lastLocator: Data?
    var addedAt: Date
    var lastOpenedAt: Date?

    init(
        title: String,
        author: String,
        filePath: String,
        format: BookFormat
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.filePath = filePath
        self.format = format
        self.lastLocator = nil
        self.addedAt = Date()
        self.lastOpenedAt = nil
    }
}

enum BookFormat: String, Codable {
    case epub
    case pdf
}
