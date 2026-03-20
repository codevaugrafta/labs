import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ScheduleEngine {
    private var modelContext: ModelContext?

    private(set) var lastError: String?

    func clearLastError() {
        lastError = nil
    }

    func configure(with context: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = context
    }

    /// Call explicitly when the schedule view appears — not on every configure.
    func materializeIfNeeded() {
        materializeUpcomingWeeks()
    }

    // MARK: - Block CRUD

    func createBlock(
        category: Category,
        weekStart: Date,
        dayOfWeek: Int,
        startTime: Date,
        endTime: Date,
        template: ScheduleTemplate? = nil
    ) -> ScheduledBlock? {
        guard let modelContext else {
            lastError = "Schedule is not ready."
            return nil
        }
        lastError = nil

        // Validate no overlap
        let existing = blocksForDay(weekStart: weekStart, dayOfWeek: dayOfWeek)
        let newStart = timeToMinutes(startTime)
        let newEnd = timeToMinutes(endTime)

        for block in existing {
            let existStart = timeToMinutes(block.startTime)
            let existEnd = timeToMinutes(block.endTime)
            if newStart < existEnd && newEnd > existStart {
                lastError = "This time overlaps another scheduled block."
                return nil
            }
        }

        let block = ScheduledBlock(
            category: category,
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            template: template
        )
        modelContext.insert(block)
        save()
        return block
    }

    @discardableResult
    func updateBlock(_ block: ScheduledBlock, startTime: Date? = nil, endTime: Date? = nil, category: Category? = nil) -> Bool {
        guard modelContext != nil else {
            lastError = "Schedule is not ready."
            return false
        }

        let newStart = startTime ?? block.startTime
        let newEnd = endTime ?? block.endTime
        let newA = timeToMinutes(newStart)
        let newB = timeToMinutes(newEnd)

        let others = blocksForDay(weekStart: block.weekStart, dayOfWeek: block.dayOfWeek)
            .filter { $0.id != block.id }
        for other in others {
            let oa = timeToMinutes(other.startTime)
            let ob = timeToMinutes(other.endTime)
            if newA < ob && newB > oa {
                lastError = "This time overlaps another scheduled block."
                return false
            }
        }

        lastError = nil
        if let startTime { block.startTime = startTime }
        if let endTime { block.endTime = endTime }
        if let category { block.category = category }

        // If this block came from a template, detach it as an exception
        if block.template != nil {
            block.isException = true
        }

        block.updatedAt = Date()
        save()
        return true
    }

    func deleteBlock(_ block: ScheduledBlock) {
        block.deletedAt = Date()
        block.updatedAt = Date()
        save()
    }

    // MARK: - Query

    func blocksForDay(weekStart: Date, dayOfWeek: Int) -> [ScheduledBlock] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate {
                $0.deletedAt == nil &&
                $0.weekStart == weekStart &&
                $0.dayOfWeek == dayOfWeek
            },
            sortBy: [SortDescriptor(\ScheduledBlock.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func blocksForWeek(weekStart: Date) -> [ScheduledBlock] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate {
                $0.deletedAt == nil &&
                $0.weekStart == weekStart
            },
            sortBy: [SortDescriptor(\ScheduledBlock.dayOfWeek), SortDescriptor(\ScheduledBlock.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Templates & Recurrence

    func createTemplate(name: String) -> ScheduleTemplate? {
        guard let modelContext else {
            lastError = "Schedule is not ready."
            return nil
        }
        lastError = nil
        let template = ScheduleTemplate(name: name)
        modelContext.insert(template)
        save()
        return template
    }

    /// Materialize blocks from active templates for the next 4 weeks
    func materializeUpcomingWeeks() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<ScheduleTemplate>(
            predicate: #Predicate { $0.isActive && $0.deletedAt == nil }
        )
        guard let templates = try? modelContext.fetch(descriptor) else { return }

        let today = Date()
        let calendar = Calendar.current

        for weekOffset in 0..<4 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: mondayOfWeek(containing: today)) else { continue }

            for template in templates {
                materializeWeek(template: template, weekStart: weekStart)
            }
        }
    }

    private func materializeWeek(template: ScheduleTemplate, weekStart: Date) {
        guard let modelContext else { return }

        // Check if this week already has blocks from this template
        let templateId = template.id
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate {
                $0.weekStart == weekStart && $0.deletedAt == nil
            }
        )
        let existingBlocks = (try? modelContext.fetch(descriptor)) ?? []
        let hasTemplateBlocks = existingBlocks.contains { $0.template?.id == templateId }

        if hasTemplateBlocks { return } // Already materialized

        // Get the template's blocks from the most recent materialized week
        for block in template.blocks where block.deletedAt == nil && !block.isException {
            guard let blockCategory = block.category else { continue }
            let newBlock = ScheduledBlock(
                category: blockCategory,
                weekStart: weekStart,
                dayOfWeek: block.dayOfWeek,
                startTime: block.startTime,
                endTime: block.endTime,
                objectiveType: block.objectiveType,
                isRecurring: true,
                template: template
            )
            newBlock.objectivesData = block.objectivesData
            modelContext.insert(newBlock)
        }
        save()
    }

    // MARK: - Helpers

    func mondayOfWeek(containing date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }

    private func timeToMinutes(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func save() {
        do {
            try modelContext?.save()
            lastError = nil
        } catch {
            lastError = "Schedule save failed: \(error.localizedDescription)"
        }
    }
}
