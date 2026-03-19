import Testing
import Foundation
import SwiftData
@testable import Tiempo

/// Tests for all adversarial review fixes (2026-03-19).
/// Covers: configure guard, concurrent timer toggle, canDeleteCategory with blocks/goals,
/// addRetroactiveEntry return value, duplicate tag prevention, and durationMinutes safety.
@Suite("Adversarial Review Fixes")
struct AdversarialFixTests {

    @MainActor
    private func makeFullEngine() throws -> (TimeEntryEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let engine = TimeEntryEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    // MARK: - Fix #1: Configure guard (prevents crash recovery re-trigger)

    @Test("configure is idempotent — second call is a no-op")
    @MainActor
    func configureGuard() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let engine = TimeEntryEngine()

        // First configure
        engine.configure(with: context)
        #expect(engine.modelContext != nil)

        // Start a timer so there's a running entry
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()
        engine.startTimer(for: category)
        #expect(engine.activeEntry != nil)
        #expect(engine.showCrashRecovery == false)

        // Second configure should be a no-op — should NOT trigger crash recovery
        engine.configure(with: context)
        #expect(engine.showCrashRecovery == false)
        #expect(engine.activeEntry != nil)
    }

    // MARK: - Fix #2: canDeleteCategory checks blocks and goals

    @Test("canDeleteCategory blocks deletion when category has scheduled blocks")
    @MainActor
    func cannotDeleteCategoryWithBlocks() throws {
        let (engine, context) = try makeFullEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let block = ScheduledBlock(
            category: category,
            weekStart: Date(),
            dayOfWeek: 1,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        context.insert(block)
        try context.save()

        #expect(!engine.canDeleteCategory(category))
    }

    @Test("canDeleteCategory blocks deletion when category has goals")
    @MainActor
    func cannotDeleteCategoryWithGoals() throws {
        let (engine, context) = try makeFullEngine()
        let category = Category(name: "Exercise", color: "#2ECC71")
        context.insert(category)
        try context.save()

        let goal = Goal(category: category, targetMinutes: 30, period: "daily")
        context.insert(goal)
        try context.save()

        #expect(!engine.canDeleteCategory(category))
    }

    @Test("canDeleteCategory allows deletion when category has no entries, blocks, or goals")
    @MainActor
    func canDeleteEmptyCategory() throws {
        let (engine, context) = try makeFullEngine()
        let category = Category(name: "Empty", color: "#4A90D9")
        context.insert(category)
        try context.save()

        #expect(engine.canDeleteCategory(category))
    }

    @Test("canDeleteCategory ignores soft-deleted blocks and goals")
    @MainActor
    func deletedBlocksAndGoalsDontBlock() throws {
        let (engine, context) = try makeFullEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let block = ScheduledBlock(
            category: category,
            weekStart: Date(),
            dayOfWeek: 1,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        block.deletedAt = Date()
        context.insert(block)

        let goal = Goal(category: category, targetMinutes: 60, period: "weekly")
        goal.deletedAt = Date()
        context.insert(goal)
        try context.save()

        #expect(engine.canDeleteCategory(category))
    }

    // MARK: - Fix #3: Concurrent timers — toggle works for non-activeEntry timers

    @Test("toggleTimer stops a concurrent running timer that is not activeEntry")
    @MainActor
    func toggleStopsConcurrentTimer() throws {
        let (engine, context) = try makeFullEngine()
        engine.allowConcurrentTimers = true

        let work = Category(name: "Work", color: "#4A90D9")
        let study = Category(name: "Study", color: "#9B59B6")
        context.insert(work)
        context.insert(study)
        try context.save()

        // Start Work, then Study (activeEntry moves to Study)
        engine.startTimer(for: work)
        let workEntry = engine.activeEntry!
        engine.startTimer(for: study)
        #expect(engine.activeEntry?.category?.id == study.id)
        #expect(workEntry.isRunning == true) // Still running (concurrent)

        // Toggle Work — should stop it even though activeEntry points to Study
        engine.toggleTimer(for: work)
        #expect(workEntry.isRunning == false)

        // Restore
        engine.allowConcurrentTimers = false
    }

    @Test("isActive correctly reports concurrent running timers")
    @MainActor
    func isActiveWithConcurrentTimers() throws {
        let (engine, context) = try makeFullEngine()
        engine.allowConcurrentTimers = true

        let work = Category(name: "Work", color: "#4A90D9")
        let study = Category(name: "Study", color: "#9B59B6")
        context.insert(work)
        context.insert(study)
        try context.save()

        engine.startTimer(for: work)
        engine.startTimer(for: study)

        // Both should report as active
        #expect(engine.isActive(category: work))
        #expect(engine.isActive(category: study))

        // Restore
        engine.allowConcurrentTimers = false
    }

    @Test("runningEntries returns all concurrent running entries")
    @MainActor
    func runningEntriesMultiple() throws {
        let (engine, context) = try makeFullEngine()
        engine.allowConcurrentTimers = true

        let work = Category(name: "Work", color: "#4A90D9")
        let study = Category(name: "Study", color: "#9B59B6")
        context.insert(work)
        context.insert(study)
        try context.save()

        engine.startTimer(for: work)
        engine.startTimer(for: study)

        #expect(engine.runningEntries.count == 2)

        // Restore
        engine.allowConcurrentTimers = false
    }

    // MARK: - Fix #4: addRetroactiveEntry returns the created entry

    @Test("addRetroactiveEntry returns the created entry for tag assignment")
    @MainActor
    func retroactiveEntryReturnsEntry() throws {
        let (engine, context) = try makeFullEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        let tag = Tag(name: "deep-work")
        context.insert(category)
        context.insert(tag)
        try context.save()

        let entry = engine.addRetroactiveEntry(
            category: category,
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            note: "Focus session"
        )

        #expect(entry != nil)
        #expect(entry?.note == "Focus session")
        #expect(entry?.category?.id == category.id)

        // Can assign tags directly to returned entry
        engine.assignTag(tag, to: entry!)
        #expect(entry?.tags.count == 1)
    }

    // MARK: - Fix #5: Duplicate tag prevention

    @Test("addTag returns existing tag for case-insensitive duplicate")
    @MainActor
    func duplicateTagPrevention() throws {
        let (engine, context) = try makeFullEngine()

        let tag1 = engine.addTag(name: "Deep Work")
        #expect(tag1 != nil)

        let tag2 = engine.addTag(name: "deep work")
        #expect(tag2 != nil)
        #expect(tag2?.id == tag1?.id) // Same tag returned

        let tag3 = engine.addTag(name: "DEEP WORK")
        #expect(tag3?.id == tag1?.id) // Still same tag

        // Only one tag in database
        let allTags = try context.fetch(FetchDescriptor<Tiempo.Tag>())
        #expect(allTags.count == 1)
    }

    @Test("addTag creates new tag when name is genuinely different")
    @MainActor
    func nonDuplicateTagCreated() throws {
        let (engine, context) = try makeFullEngine()

        let tag1 = engine.addTag(name: "work")
        let tag2 = engine.addTag(name: "exercise")

        #expect(tag1?.id != tag2?.id)

        let allTags = try context.fetch(FetchDescriptor<Tiempo.Tag>())
        #expect(allTags.count == 2)
    }

    // MARK: - Fix #6: ScheduledBlock.durationMinutes safety

    @Test("durationMinutes returns 0 for inverted times (not negative)")
    @MainActor
    func durationMinutesClamped() throws {
        let cal = Calendar.current
        // End time BEFORE start time
        let startTime = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let endTime = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!

        let (_, context) = try makeFullEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)

        let block = ScheduledBlock(
            category: category,
            weekStart: Date(),
            dayOfWeek: 1,
            startTime: startTime,
            endTime: endTime
        )
        context.insert(block)

        #expect(block.durationMinutes == 0) // Clamped, not -240
    }

    @Test("durationMinutes calculates correctly for valid times")
    @MainActor
    func durationMinutesValid() throws {
        let cal = Calendar.current
        let startTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let endTime = cal.date(bySettingHour: 10, minute: 30, second: 0, of: Date())!

        let (_, context) = try makeFullEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)

        let block = ScheduledBlock(
            category: category,
            weekStart: Date(),
            dayOfWeek: 1,
            startTime: startTime,
            endTime: endTime
        )
        context.insert(block)

        #expect(block.durationMinutes == 90)
    }

    // MARK: - Fix #7: ScheduleEngine configure guard

    @Test("ScheduleEngine.configure is idempotent")
    @MainActor
    func scheduleEngineConfigureGuard() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let engine = ScheduleEngine()

        engine.configure(with: context)
        // Second call should be no-op (no crash, no double-materialization)
        engine.configure(with: context)

        // Engine should still function
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let block = engine.createBlock(
            category: category,
            weekStart: Date(),
            dayOfWeek: 1,
            startTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!,
            endTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        )
        #expect(block != nil)
    }

    // MARK: - Fix #8: AccountabilityEngine reuses ScheduleEngine

    @Test("AccountabilityEngine accepts injected ScheduleEngine")
    @MainActor
    func accountabilityEngineInjection() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)

        let scheduleEngine = ScheduleEngine()
        scheduleEngine.configure(with: context)

        let engine = AccountabilityEngine()
        engine.configure(with: context, scheduleEngine: scheduleEngine)

        // Should produce a valid report (empty schedule = N/A score)
        let report = engine.dailyReport(for: Date())
        #expect(report.score == nil) // No schedule = N/A
    }
}
