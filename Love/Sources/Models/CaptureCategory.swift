import Foundation
import SwiftData

@Model
final class CaptureCategory {
    var id: UUID
    var name: String
    var sortOrder: Double
    @Relationship(deleteRule: .nullify, inverse: \LaterCapture.category)
    var captures: [LaterCapture]

    init(name: String, sortOrder: Double) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.captures = []
    }
}
