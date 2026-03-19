import Foundation
import SwiftData

/// A single time-blocked segment in a weekly schedule.
/// Blocks are either generated from a template or standalone.
@Model
final class ScheduledBlock {
    var id: UUID
    var weekStart: Date            // Monday of the week this block belongs to
    var dayOfWeek: Int             // 0=Sun, 1=Mon, ..., 6=Sat
    var startTime: Date            // Time component only (stored as Date for SwiftData compat)
    var endTime: Date              // Time component only
    var objectiveType: String      // "checklist" or "description"
    var objectivesData: Data?      // JSON: [{text, completed}] or {text}
    var isException: Bool          // true = detached from template, won't be regenerated
    var isRecurring: Bool
    var syncStatusRaw: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var template: ScheduleTemplate?
    var category: Category?

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    // MARK: - Objective helpers

    struct ChecklistItem: Codable {
        var text: String
        var completed: Bool
    }

    struct DescriptionObjective: Codable {
        var text: String
    }

    var checklistItems: [ChecklistItem] {
        get {
            guard objectiveType == "checklist", let data = objectivesData else { return [] }
            return (try? JSONDecoder().decode([ChecklistItem].self, from: data)) ?? []
        }
        set {
            objectiveType = "checklist"
            objectivesData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var descriptionText: String {
        get {
            guard objectiveType == "description", let data = objectivesData else { return "" }
            return (try? JSONDecoder().decode(DescriptionObjective.self, from: data))?.text ?? ""
        }
        set {
            objectiveType = "description"
            objectivesData = try? JSONEncoder().encode(DescriptionObjective(text: newValue))
            updatedAt = Date()
        }
    }

    // MARK: - Time helpers

    /// Start time as hours and minutes (e.g., 9:30 → (9, 30))
    var startHourMinute: (hour: Int, minute: Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return (comps.hour ?? 0, comps.minute ?? 0)
    }

    /// End time as hours and minutes
    var endHourMinute: (hour: Int, minute: Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        return (comps.hour ?? 0, comps.minute ?? 0)
    }

    /// Duration in minutes
    var durationMinutes: Int {
        let start = startHourMinute
        let end = endHourMinute
        return (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute)
    }

    /// The actual calendar date this block is on
    var blockDate: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
        comps.weekday = dayOfWeek == 0 ? 1 : dayOfWeek + 1 // Convert 0-indexed to Calendar weekday
        return cal.date(from: comps) ?? weekStart
    }

    init(
        category: Category,
        weekStart: Date,
        dayOfWeek: Int,
        startTime: Date,
        endTime: Date,
        objectiveType: String = "description",
        isRecurring: Bool = false,
        template: ScheduleTemplate? = nil
    ) {
        self.id = UUID()
        self.weekStart = weekStart
        self.dayOfWeek = dayOfWeek
        self.startTime = startTime
        self.endTime = endTime
        self.objectiveType = objectiveType
        self.objectivesData = nil
        self.isException = false
        self.isRecurring = isRecurring
        self.syncStatusRaw = SyncStatus.pendingCreate.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.template = template
        self.category = category
    }
}
