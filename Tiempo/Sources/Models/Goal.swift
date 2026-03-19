import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var targetMinutes: Int
    var period: String             // "daily", "weekly", "monthly"
    var isActive: Bool
    var syncStatusRaw: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var category: Category?

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(category: Category, targetMinutes: Int, period: String) {
        self.id = UUID()
        self.targetMinutes = targetMinutes
        self.period = period
        self.isActive = true
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.category = category
    }
}
