import Testing
import Foundation
import SwiftData
@testable import Tiempo

@Suite("Phase 3 — Full Tracking")
struct Phase3Tests {

    @MainActor
    private func makeEngine() throws -> (TimeEntryEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Category.self, TimeEntry.self, Tag.self, configurations: config)
        let context = ModelContext(container)
        let engine = TimeEntryEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    // MARK: - Retroactive Entries (Criterion 1)

    @Test("Can add retroactive entry with manual start/end time")
    @MainActor
    func retroactiveEntry() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Exercise", color: "#2ECC71")
        context.insert(category)
        try context.save()

        let start = Date().addingTimeInterval(-7200) // 2 hours ago
        let end = Date().addingTimeInterval(-3600) // 1 hour ago
        engine.addRetroactiveEntry(category: category, startedAt: start, endedAt: end, note: "Morning run")

        let entries = try context.fetch(FetchDescriptor<TimeEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].isRunning == false)
        #expect(entries[0].note == "Morning run")
        #expect(entries[0].category?.id == category.id)
    }

    // MARK: - Edit Entries (Criterion 2)

    @Test("Can edit past entry times and notes")
    @MainActor
    func editEntry() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.startTimer(for: category)
        engine.stopTimer()

        let entries = try context.fetch(FetchDescriptor<TimeEntry>())
        let entry = entries[0]
        let newStart = Date().addingTimeInterval(-3600)

        engine.updateEntry(entry, startedAt: newStart, note: "Updated note")

        #expect(entry.startedAt == newStart)
        #expect(entry.note == "Updated note")
    }

    // MARK: - Soft Delete (Criterion 3)

    @Test("Soft delete sets deletedAt and hides from active queries")
    @MainActor
    func softDelete() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.startTimer(for: category)
        engine.stopTimer()

        let entries = try context.fetch(FetchDescriptor<TimeEntry>())
        let entry = entries[0]
        engine.softDeleteEntry(entry)

        #expect(entry.deletedAt != nil)

        // Verify soft-deleted entries are hidden
        let visibleDescriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let visible = try context.fetch(visibleDescriptor)
        #expect(visible.isEmpty)
    }

    @Test("Soft deleting a running timer stops it first")
    @MainActor
    func softDeleteRunningTimer() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.startTimer(for: category)
        let entry = engine.activeEntry!

        engine.softDeleteEntry(entry)

        #expect(engine.activeEntry == nil)
        #expect(entry.isRunning == false)
        #expect(entry.deletedAt != nil)
    }

    // MARK: - Tags (Criterion 5)

    @Test("Can create tags and assign to entries")
    @MainActor
    func tagsOnEntries() throws {
        let (_, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        let tag = Tag(name: "deep-work")
        context.insert(category)
        context.insert(tag)
        try context.save()

        let entry = TimeEntry(category: category, startedAt: Date().addingTimeInterval(-3600), endedAt: Date())
        entry.tags.append(tag)
        context.insert(entry)
        try context.save()

        #expect(entry.tags.count == 1)
        #expect(entry.tags[0].name == "deep-work")
    }

    // MARK: - Subcategories (Criterion 6)

    @Test("Subcategory has parent reference")
    @MainActor
    func subcategory() throws {
        let (_, context) = try makeEngine()
        let parent = Category(name: "Work", color: "#4A90D9")
        context.insert(parent)
        try context.save()

        let child = Category(name: "Deep Focus", color: "#4A90D9", parentId: parent.id)
        context.insert(child)
        try context.save()

        #expect(child.parentId == parent.id)
    }

    // MARK: - Archive Category (Criterion 8)

    @Test("Archived categories are hidden from active queries")
    @MainActor
    func archiveCategory() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Old Hobby", color: "#E74C3C")
        context.insert(category)
        try context.save()

        engine.archiveCategory(category)

        #expect(category.isArchived == true)

        let activeDescriptor = FetchDescriptor<Tiempo.Category>(
            predicate: #Predicate<Tiempo.Category> { !$0.isArchived && $0.deletedAt == nil }
        )
        let active: [Tiempo.Category] = try context.fetch(activeDescriptor)
        #expect(active.isEmpty)
    }

    // MARK: - Block Category Delete (Criterion 13)

    @Test("Cannot delete category with existing entries")
    @MainActor
    func blockDeleteWithEntries() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        engine.startTimer(for: category)
        engine.stopTimer()

        #expect(!engine.canDeleteCategory(category))
    }

    @Test("Can delete category with no entries")
    @MainActor
    func allowDeleteEmpty() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Empty", color: "#4A90D9")
        context.insert(category)
        try context.save()

        #expect(engine.canDeleteCategory(category))
    }

    // MARK: - Concurrent Timer Toggle (Criterion 11)

    @Test("Default behavior: starting new timer stops previous")
    @MainActor
    func defaultSingleTimer() throws {
        UserDefaults.standard.set(false, forKey: "allowConcurrentTimers")
        let (engine, context) = try makeEngine()
        let work = Category(name: "Work", color: "#4A90D9")
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        context.insert(work)
        context.insert(exercise)
        try context.save()

        engine.startTimer(for: work)
        let workEntry = engine.activeEntry!
        engine.startTimer(for: exercise)

        #expect(workEntry.isRunning == false)
        #expect(engine.activeEntry?.category?.id == exercise.id)
    }
}
