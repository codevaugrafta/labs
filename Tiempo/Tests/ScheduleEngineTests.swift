import Testing
import Foundation
import SwiftData
@testable import Tiempo

@Suite("Schedule Engine")
struct ScheduleEngineTests {

    @MainActor
    private func makeEngine() throws -> (ScheduleEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let engine = ScheduleEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    @Test("Can create a scheduled block")
    @MainActor
    func createBlock() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let block = engine.createBlock(
            category: category,
            weekStart: weekStart,
            dayOfWeek: 1, // Monday
            startTime: start,
            endTime: end
        )

        #expect(block != nil)
        #expect(block?.durationMinutes == 180)
        #expect(block?.category?.id == category.id)
    }

    @Test("Overlapping blocks are rejected")
    @MainActor
    func overlapRejection() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start1 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end1 = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let start2 = cal.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!
        let end2 = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!

        let block1 = engine.createBlock(category: category, weekStart: weekStart, dayOfWeek: 1, startTime: start1, endTime: end1)
        let block2 = engine.createBlock(category: category, weekStart: weekStart, dayOfWeek: 1, startTime: start2, endTime: end2)

        #expect(block1 != nil)
        #expect(block2 == nil) // Overlap rejected
    }

    @Test("Non-overlapping blocks on same day are allowed")
    @MainActor
    func nonOverlapping() throws {
        let (engine, context) = try makeEngine()
        let work = Category(name: "Work", color: "#4A90D9")
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        context.insert(work)
        context.insert(exercise)
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start1 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end1 = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let start2 = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let end2 = cal.date(bySettingHour: 16, minute: 0, second: 0, of: Date())!

        let block1 = engine.createBlock(category: work, weekStart: weekStart, dayOfWeek: 1, startTime: start1, endTime: end1)
        let block2 = engine.createBlock(category: exercise, weekStart: weekStart, dayOfWeek: 1, startTime: start2, endTime: end2)

        #expect(block1 != nil)
        #expect(block2 != nil)
    }

    @Test("Editing a templated block detaches it as exception")
    @MainActor
    func editDetachesException() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        let template = engine.createTemplate(name: "Weekly Routine")!
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let block = engine.createBlock(
            category: category, weekStart: weekStart, dayOfWeek: 1,
            startTime: start, endTime: end, template: template
        )!

        #expect(!block.isException)

        let newEnd = cal.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!
        engine.updateBlock(block, endTime: newEnd)

        #expect(block.isException)
    }

    @Test("Deleting a block soft-deletes it")
    @MainActor
    func softDeleteBlock() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let block = engine.createBlock(category: category, weekStart: weekStart, dayOfWeek: 1, startTime: start, endTime: end)!
        engine.deleteBlock(block)

        #expect(block.deletedAt != nil)

        let remaining = engine.blocksForDay(weekStart: weekStart, dayOfWeek: 1)
        #expect(remaining.isEmpty)
    }

    @Test("Checklist objectives round-trip through JSON")
    @MainActor
    func checklistRoundTrip() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let block = engine.createBlock(category: category, weekStart: weekStart, dayOfWeek: 1, startTime: start, endTime: end)!
        block.checklistItems = [
            .init(text: "Design schema", completed: false),
            .init(text: "Write migration", completed: true)
        ]

        let items = block.checklistItems
        #expect(items.count == 2)
        #expect(items[0].text == "Design schema")
        #expect(items[0].completed == false)
        #expect(items[1].completed == true)
    }

    @Test("Description objective round-trips")
    @MainActor
    func descriptionRoundTrip() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Study", color: "#F39C12")
        context.insert(category)
        try context.save()

        let weekStart = engine.mondayOfWeek(containing: Date())
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let end = cal.date(bySettingHour: 16, minute: 0, second: 0, of: Date())!

        let block = engine.createBlock(category: category, weekStart: weekStart, dayOfWeek: 2, startTime: start, endTime: end)!
        block.descriptionText = "Deep focus on algorithms"

        #expect(block.descriptionText == "Deep focus on algorithms")
        #expect(block.objectiveType == "description")
    }
}
