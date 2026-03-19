import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var syncStatusRaw: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    @Relationship(inverse: \TimeEntry.tags)
    var timeEntries: [TimeEntry]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.timeEntries = []
    }
}
