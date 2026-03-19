import Foundation
import SwiftData

@Model
final class ScheduleTemplate {
    var id: UUID
    var name: String
    var isActive: Bool
    var syncStatusRaw: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ScheduledBlock.template)
    var blocks: [ScheduledBlock]

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isActive = true
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.blocks = []
    }
}
