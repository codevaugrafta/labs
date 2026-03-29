import Foundation
import SwiftData

struct BookLocator: Codable, Equatable {
    let cfi: String
    let fraction: Double
    let updatedAt: Date
}

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
    /// When set, this book was reflow-converted from a PDF at this path; `filePath` then points to the derived EPUB.
    var originalPDFPath: String?

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
        self.originalPDFPath = nil
    }
}

enum BookFormat: String, Codable {
    case epub
    case pdf
}

extension Book {
    var locator: BookLocator? {
        get {
            guard let lastLocator else { return nil }
            do {
                return try JSONDecoder().decode(BookLocator.self, from: lastLocator)
            } catch {
                NSLog("[Leo Book] Failed to decode BookLocator for '\(title)': \(error)")
                return nil
            }
        }
        set {
            do {
                lastLocator = try newValue.map { try JSONEncoder().encode($0) }
            } catch {
                NSLog("[Leo Book] Failed to encode BookLocator for '\(title)': \(error)")
                // lastLocator is left unchanged — prefer stale position over silent data loss
            }
        }
    }
}
