import Testing
import Foundation
import SwiftData
@testable import Tiempo

@Suite("Accountability Engine")
struct AccountabilityTests {

    @MainActor
    private func makeEngines() throws -> (AccountabilityEngine, ScheduleEngine, TimeEntryEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let accountability = AccountabilityEngine()
        accountability.configure(with: context)
        let schedule = ScheduleEngine()
        schedule.configure(with: context)
        let timer = TimeEntryEngine()
        timer.configure(with: context)
        return (accountability, schedule, timer, context)
    }

    @Test("Day with no schedule returns score N/A")
    @MainActor
    func noSchedule() throws {
        let (engine, _, _, _) = try makeEngines()
        let report = engine.dailyReport(for: Date())
        #expect(report.score == nil)
        #expect(!report.hasSchedule)
    }

    @Test("Fully completed block scores 1.0 (On Track)")
    @MainActor
    func fullAdherence() throws {
        let (accountability, schedule, _, context) = try makeEngines()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let today = Date()
        let cal = Calendar.current
        let weekStart = schedule.mondayOfWeek(containing: today)
        let dayOfWeek = cal.component(.weekday, from: today) - 1

        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        _ = schedule.createBlock(category: category, weekStart: weekStart, dayOfWeek: dayOfWeek, startTime: start, endTime: end)

        // Create a matching time entry
        let entry = TimeEntry(category: category, startedAt: start, endedAt: end)
        context.insert(entry)
        try context.save()

        let report = accountability.dailyReport(for: today)
        #expect(report.hasSchedule)
        #expect(report.blocks.count == 1)
        #expect(report.blocks[0].adherence >= 0.99)
        #expect(report.blocks[0].status == .onTrack)
        #expect(report.score != nil)
        #expect(report.score! >= 0.99)
    }

    @Test("Skipped block scores 0.0")
    @MainActor
    func skippedBlock() throws {
        let (accountability, schedule, _, context) = try makeEngines()
        let category = Category(name: "Exercise", color: "#2ECC71")
        context.insert(category)
        try context.save()

        let today = Date()
        let cal = Calendar.current
        let weekStart = schedule.mondayOfWeek(containing: today)
        let dayOfWeek = cal.component(.weekday, from: today) - 1

        let start = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        let end = cal.date(bySettingHour: 8, minute: 0, second: 0, of: today)!
        _ = schedule.createBlock(category: category, weekStart: weekStart, dayOfWeek: dayOfWeek, startTime: start, endTime: end)

        // No time entries at all
        let report = accountability.dailyReport(for: today)
        #expect(report.blocks[0].adherence == 0.0)
        #expect(report.blocks[0].status == .skipped)
    }

    @Test("Partial adherence calculated correctly")
    @MainActor
    func partialAdherence() throws {
        let (accountability, schedule, _, context) = try makeEngines()
        let category = Category(name: "Study", color: "#F39C12")
        context.insert(category)
        try context.save()

        let today = Date()
        let cal = Calendar.current
        let weekStart = schedule.mondayOfWeek(containing: today)
        let dayOfWeek = cal.component(.weekday, from: today) - 1

        let blockStart = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        let blockEnd = cal.date(bySettingHour: 16, minute: 0, second: 0, of: today)! // 120 min planned
        _ = schedule.createBlock(category: category, weekStart: weekStart, dayOfWeek: dayOfWeek, startTime: blockStart, endTime: blockEnd)

        // Only tracked 60 of 120 min
        let entryStart = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        let entryEnd = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)!
        let entry = TimeEntry(category: category, startedAt: entryStart, endedAt: entryEnd)
        context.insert(entry)
        try context.save()

        let report = accountability.dailyReport(for: today)
        #expect(report.blocks[0].adherence >= 0.49 && report.blocks[0].adherence <= 0.51)
        // Ends 60 min early (>10 min threshold) → Early End, not just Partial
        #expect(report.blocks[0].status == .earlyEnd)
    }

    @Test("Adherence capped at 1.0 even when entry extends beyond block")
    @MainActor
    func cappedAtOne() throws {
        let (accountability, schedule, _, context) = try makeEngines()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let today = Date()
        let cal = Calendar.current
        let weekStart = schedule.mondayOfWeek(containing: today)
        let dayOfWeek = cal.component(.weekday, from: today) - 1

        let blockStart = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let blockEnd = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)! // 60 min planned
        _ = schedule.createBlock(category: category, weekStart: weekStart, dayOfWeek: dayOfWeek, startTime: blockStart, endTime: blockEnd)

        // Entry covers the full block window — the overlap is exactly 60 min (clamped to block window)
        // Since actual (60) == planned (60), adherence = 1.0 and status = onTrack (not exceeded)
        // This is correct: "exceeded" requires actual > 110% of planned WITHIN the window
        let entryEnd = cal.date(bySettingHour: 10, minute: 30, second: 0, of: today)!
        let entry = TimeEntry(category: category, startedAt: blockStart, endedAt: entryEnd)
        context.insert(entry)
        try context.save()

        let report = accountability.dailyReport(for: today)
        #expect(report.blocks[0].adherence == 1.0) // Capped at 1.0
        #expect(report.blocks[0].status == .onTrack) // Not exceeded — clamped actual matches planned
    }

    @Test("Daily score averages multiple blocks")
    @MainActor
    func multiBlockAverage() throws {
        let (accountability, schedule, _, context) = try makeEngines()
        let work = Category(name: "Work", color: "#4A90D9")
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        context.insert(work)
        context.insert(exercise)
        try context.save()

        let today = Date()
        let cal = Calendar.current
        let weekStart = schedule.mondayOfWeek(containing: today)
        let dayOfWeek = cal.component(.weekday, from: today) - 1

        // Block 1: Work 9-12 (180 min) — fully completed
        let ws = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let we = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        _ = schedule.createBlock(category: work, weekStart: weekStart, dayOfWeek: dayOfWeek, startTime: ws, endTime: we)
        context.insert(TimeEntry(category: work, startedAt: ws, endedAt: we))

        // Block 2: Exercise 17-18 (60 min) — skipped
        let es = cal.date(bySettingHour: 17, minute: 0, second: 0, of: today)!
        let ee = cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
        _ = schedule.createBlock(category: exercise, weekStart: weekStart, dayOfWeek: dayOfWeek, startTime: es, endTime: ee)

        try context.save()

        let report = accountability.dailyReport(for: today)
        #expect(report.blocks.count == 2)
        // Average: (1.0 + 0.0) / 2 = 0.5
        #expect(report.score! >= 0.49 && report.score! <= 0.51)
    }

    @Test("Running timer counts toward planned block actual minutes")
    @MainActor
    func runningTimerCountsTowardBlock() throws {
        let (accountability, schedule, _, context) = try makeEngines()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        let today = Date()
        let cal = Calendar.current
        let weekStart = schedule.mondayOfWeek(containing: today)
        let dayOfWeek = cal.component(.weekday, from: today) - 1

        let blockStart = cal.date(bySettingHour: 0, minute: 0, second: 0, of: today)!
        let blockEnd = cal.date(bySettingHour: 23, minute: 59, second: 0, of: today)!
        _ = schedule.createBlock(
            category: category, weekStart: weekStart, dayOfWeek: dayOfWeek,
            startTime: blockStart, endTime: blockEnd
        )

        let entry = TimeEntry(category: category)
        entry.startedAt = cal.date(byAdding: .minute, value: -30, to: Date())!
        context.insert(entry)
        try context.save()

        let report = accountability.dailyReport(for: today)
        #expect(report.blocks.count == 1)
        #expect(report.blocks[0].actualMinutes >= 25)
    }
}
