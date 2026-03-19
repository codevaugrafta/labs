import Foundation
import SwiftData

@Model
final class TimeEntry {
    var id: UUID
    var startedAt: Date
    var endedAt: Date? // nil = currently running
    var note: String?
    var isRunning: Bool
    var syncStatusRaw: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var category: Category?
    var tags: [Tag]

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    init(category: Category) {
        self.id = UUID()
        self.startedAt = Date()
        self.endedAt = nil
        self.note = nil
        self.isRunning = true
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.category = category
        self.tags = []
    }

    /// Create a retroactive (manual) time entry
    init(category: Category, startedAt: Date, endedAt: Date, note: String? = nil) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.isRunning = false
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.category = category
        self.tags = []
    }
}
