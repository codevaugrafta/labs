import Foundation
import SwiftData

@Model
final class MustDoItem {
    var id: UUID
    var title: String
    var notes: String?
    /// Ordering within the section (lower = higher in list).
    var sortOrder: Double
    var planningBucketRaw: Int
    var completedAt: Date?
    /// When set, the item is hidden from actionable lists until this calendar day starts.
    var snoozeUntil: Date?
    var createdAt: Date
    var updatedAt: Date

    var section: TaskSection?

    var planningBucket: PlanningBucket {
        get { PlanningBucket(rawValue: planningBucketRaw) ?? .backlog }
        set { planningBucketRaw = newValue.rawValue }
    }

    init(
        title: String,
        sortOrder: Double,
        section: TaskSection?,
        planningBucket: PlanningBucket = .backlog
    ) {
        self.id = UUID()
        self.title = title
        self.notes = nil
        self.sortOrder = sortOrder
        self.planningBucketRaw = planningBucket.rawValue
        self.completedAt = nil
        self.snoozeUntil = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.section = section
    }

    func isSnoozed(calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard let s = snoozeUntil else { return false }
        return calendar.startOfDay(for: now) < calendar.startOfDay(for: s)
    }

    func matches(listFilter: MainListFilter) -> Bool {
        switch listFilter {
        case .all:
            true
        case .today:
            planningBucket == .today
        case .thisWeek:
            planningBucket == .today || planningBucket == .thisWeek
        case .backlog:
            planningBucket == .backlog
        }
    }
}
