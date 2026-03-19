import Testing
import Foundation
import SwiftData
@testable import Tiempo

@Suite("TimeEntryEngine")
struct TimeEntryEngineTests {

    @MainActor
    private func makeEngine() throws -> (TimeEntryEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Category.self, TimeEntry.self, configurations: config)
        let context = ModelContext(container)
        let engine = TimeEntryEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    @Test("Starting a timer creates a running entry")
    @MainActor
    func startTimer() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.startTimer(for: category)

        #expect(engine.activeEntry != nil)
        #expect(engine.activeEntry?.isRunning == true)
        #expect(engine.activeEntry?.category?.id == category.id)
    }

    @Test("Stopping a timer sets endedAt and clears active")
    @MainActor
    func stopTimer() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.startTimer(for: category)
        let entry = engine.activeEntry!
        engine.stopTimer()

        #expect(engine.activeEntry == nil)
        #expect(entry.isRunning == false)
        #expect(entry.endedAt != nil)
    }

    @Test("Toggle starts timer when none active")
    @MainActor
    func toggleStart() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.toggleTimer(for: category)

        #expect(engine.activeEntry != nil)
        #expect(engine.activeEntry?.category?.id == category.id)
    }

    @Test("Toggle stops timer when same category is active")
    @MainActor
    func toggleStop() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.toggleTimer(for: category)
        #expect(engine.activeEntry != nil)

        engine.toggleTimer(for: category)
        #expect(engine.activeEntry == nil)
    }

    @Test("Starting a new category stops the previous timer")
    @MainActor
    func switchCategory() throws {
        let (engine, context) = try makeEngine()
        engine.allowConcurrentTimers = false  // Ensure single-timer mode
        let work = Category(name: "Work", color: "#4A90D9")
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        context.insert(work)
        context.insert(exercise)
        try context.save()

        engine.startTimer(for: work)
        let workEntry = engine.activeEntry!

        engine.startTimer(for: exercise)

        #expect(workEntry.isRunning == false)
        #expect(workEntry.endedAt != nil)
        #expect(engine.activeEntry?.category?.id == exercise.id)
    }

    @Test("isActive returns correct state for categories")
    @MainActor
    func isActiveCheck() throws {
        let (engine, context) = try makeEngine()
        let work = Category(name: "Work", color: "#4A90D9")
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        context.insert(work)
        context.insert(exercise)
        try context.save()

        engine.startTimer(for: work)

        #expect(engine.isActive(category: work))
        #expect(!engine.isActive(category: exercise))
    }
}
