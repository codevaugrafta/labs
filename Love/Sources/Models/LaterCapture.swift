import Foundation
import SwiftData

@Model
final class LaterCapture {
    var id: UUID
    var body: String
    var createdAt: Date
    var archivedAt: Date?
    var category: CaptureCategory?

    init(body: String, category: CaptureCategory?) {
        self.id = UUID()
        self.body = body
        self.createdAt = Date()
        self.archivedAt = nil
        self.category = category
    }

    var isArchived: Bool { archivedAt != nil }
}
