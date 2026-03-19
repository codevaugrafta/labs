import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var color: String // hex color e.g. "#FF5733"
    var icon: String? // emoji or SF Symbol name
    var parentId: UUID? // subcategory support (max 1 level)
    var isArchived: Bool
    var sortOrder: Int
    var syncStatusRaw: Int // backing storage for SyncStatus
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.category)
    var timeEntries: [TimeEntry]

    init(
        name: String,
        color: String,
        icon: String? = nil,
        parentId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.icon = icon
        self.parentId = parentId
        self.isArchived = false
        self.sortOrder = sortOrder
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.timeEntries = []
    }
}
