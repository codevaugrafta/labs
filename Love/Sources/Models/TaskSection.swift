import Foundation
import SwiftData

@Model
final class TaskSection {
    var id: UUID
    var name: String
    var sortOrder: Double
    @Relationship(deleteRule: .cascade, inverse: \MustDoItem.section)
    var items: [MustDoItem]

    init(name: String, sortOrder: Double) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.items = []
    }
}
