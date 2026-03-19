import Foundation
import SwiftData

@MainActor
final class GoalsEngine {
    private var modelContext: ModelContext?
    var lastError: String?

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    private func save() {
        do {
            try modelContext?.save()
            lastError = nil
        } catch {
            lastError = "Goals save failed: \(error.localizedDescription)"
        }
    }

    struct GoalProgress {
        let goal: Goal
        let categoryName: String
        let color: String
        let trackedMinutes: Int
        let targetMinutes: Int
        let percentage: Double      // 0.0 - unbounded
        let isMet: Bool
    }

    func createGoal(category: Category, targetMinutes: Int, period: String) -> Goal? {
        guard let modelContext else { return nil }
        let goal = Goal(category: category, targetMinutes: targetMinutes, period: period)
        modelContext.insert(goal)
        save()
        return goal
    }

    func deleteGoal(_ goal: Goal) {
        goal.deletedAt = Date()
        goal.updatedAt = Date()
        save()
    }

    func progress(for goal: Goal, referenceDate: Date = Date()) -> GoalProgress {
        let tracked = trackedMinutes(for: goal, referenceDate: referenceDate)
        let pct = goal.targetMinutes > 0 ? Double(tracked) / Double(goal.targetMinutes) : 0
        return GoalProgress(
            goal: goal,
            categoryName: goal.category?.name ?? "Unknown",
            color: goal.category?.color ?? "#888",
            trackedMinutes: tracked,
            targetMinutes: goal.targetMinutes,
            percentage: pct,
            isMet: tracked >= goal.targetMinutes
        )
    }

    func allProgress(referenceDate: Date = Date()) -> [GoalProgress] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.isActive && $0.deletedAt == nil }
        )
        let goals = (try? modelContext.fetch(descriptor)) ?? []
        return goals.map { progress(for: $0, referenceDate: referenceDate) }
    }

    private func trackedMinutes(for goal: Goal, referenceDate: Date) -> Int {
        guard let modelContext, let category = goal.category else { return 0 }
        let (start, end) = periodBounds(goal.period, referenceDate: referenceDate)
        let catId = category.id

        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate {
                $0.deletedAt == nil && !$0.isRunning && $0.endedAt != nil
            }
        )
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []

        // Filter by category (including subcategories) and date range
        let matching = allEntries.filter { entry in
            guard let entryCat = entry.category, let endedAt = entry.endedAt else { return false }
            let catMatch = entryCat.id == catId || entryCat.parentId == catId
            let timeMatch = entry.startedAt < end && endedAt > start
            return catMatch && timeMatch
        }

        return matching.reduce(0) { total, entry in
            guard let endedAt = entry.endedAt else { return total }
            let clampedStart = max(entry.startedAt, start)
            let clampedEnd = min(endedAt, end)
            return total + max(0, Int(clampedEnd.timeIntervalSince(clampedStart) / 60))
        }
    }

    private func periodBounds(_ period: String, referenceDate: Date) -> (Date, Date) {
        let cal = Calendar.current
        switch period {
        case "daily":
            let start = cal.startOfDay(for: referenceDate)
            return (start, cal.date(byAdding: .day, value: 1, to: start)!)
        case "weekly":
            let firstWeekday = UserDefaults.standard.integer(forKey: "firstDayOfWeek")
            var weekCal = cal
            weekCal.firstWeekday = firstWeekday > 0 ? firstWeekday : 2 // Default Monday
            let comps = weekCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            let start = weekCal.date(from: comps)!
            return (start, weekCal.date(byAdding: .weekOfYear, value: 1, to: start)!)
        case "monthly":
            let comps = cal.dateComponents([.year, .month], from: referenceDate)
            let start = cal.date(from: comps)!
            return (start, cal.date(byAdding: .month, value: 1, to: start)!)
        default:
            let start = cal.startOfDay(for: referenceDate)
            return (start, cal.date(byAdding: .day, value: 1, to: start)!)
        }
    }
}
