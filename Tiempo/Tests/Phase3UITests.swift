import Testing
import Foundation
import SwiftData
@testable import Tiempo

/// Tests for Phase 3 new engine behavior: tags, subcategories, concurrent timers,
/// archive visibility, and category sort ordering.
@Suite("Phase 3 — New Behavior")
struct Phase3UITests {

    @MainActor
    private func makeEngine() throws -> (TimeEntryEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            configurations: config
        )
        let context = ModelContext(container)
        let engine = TimeEntryEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    // MARK: - Tag Assignment and Removal

    @Test("Assigning a tag to an entry adds it once")
    @MainActor
    func assignTagOnce() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        let tag = Tag(name: "focus")
        context.insert(category)
        context.insert(tag)
        try context.save()

        let entry = TimeEntry(
            category: category,
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date()
        )
        context.insert(entry)
        try context.save()

        engine.assignTag(tag, to: entry)
        engine.assignTag(tag, to: entry) // duplicate call should be idempotent

        #expect(entry.tags.count == 1)
        #expect(entry.tags[0].name == "focus")
    }

    @Test("Removing a tag from an entry leaves entry with no tags")
    @MainActor
    func removeTag() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        let tag = Tag(name: "deep-work")
        context.insert(category)
        context.insert(tag)
        try context.save()

        let entry = TimeEntry(
            category: category,
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date()
        )
        context.insert(entry)
        entry.tags.append(tag)
        try context.save()

        engine.removeTag(tag, from: entry)

        #expect(entry.tags.isEmpty)
    }

    @Test("Multiple tags can be assigned to one entry")
    @MainActor
    func multipleTagsOnEntry() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        let tagA = Tag(name: "alpha")
        let tagB = Tag(name: "beta")
        context.insert(category)
        context.insert(tagA)
        context.insert(tagB)
        try context.save()

        let entry = TimeEntry(
            category: category,
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date()
        )
        context.insert(entry)
        try context.save()

        engine.assignTag(tagA, to: entry)
        engine.assignTag(tagB, to: entry)

        #expect(entry.tags.count == 2)
    }

    @Test("addTag engine method creates and persists a tag")
    @MainActor
    func addTagViaEngine() throws {
        let (engine, context) = try makeEngine()

        let tag = engine.addTag(name: "  sprint  ")

        #expect(tag != nil)
        #expect(tag?.name == "sprint")

        let all = try context.fetch(FetchDescriptor<Tag>())
        #expect(all.count == 1)
    }

    @Test("addTag with empty name returns nil")
    @MainActor
    func addTagEmptyName() throws {
        let (engine, _) = try makeEngine()
        let tag = engine.addTag(name: "  ")
        #expect(tag == nil)
    }

    @Test("updateTag renames the tag")
    @MainActor
    func updateTag() throws {
        let (engine, context) = try makeEngine()
        let tag = Tag(name: "old-name")
        context.insert(tag)
        try context.save()

        engine.updateTag(tag, name: "new-name")

        #expect(tag.name == "new-name")
    }

    @Test("deleteTag sets deletedAt")
    @MainActor
    func softDeleteTag() throws {
        let (engine, context) = try makeEngine()
        let tag = Tag(name: "obsolete")
        context.insert(tag)
        try context.save()

        engine.deleteTag(tag)

        #expect(tag.deletedAt != nil)
    }

    // MARK: - Subcategory Creation and 1-Level Limit

    @Test("Subcategory creation with valid parent passes validation")
    @MainActor
    func subcategoryValidParent() throws {
        let (engine, context) = try makeEngine()
        let parent = Category(name: "Work", color: "#4A90D9")
        context.insert(parent)
        try context.save()

        let error = engine.validateSubcategory(
            parentId: parent.id,
            allCategories: [parent]
        )
        #expect(error == nil)
    }

    @Test("Subcategory of a subcategory fails validation (1-level max)")
    @MainActor
    func subcategoryNestingBlocked() throws {
        let (engine, context) = try makeEngine()
        let grandparent = Category(name: "Work", color: "#4A90D9")
        context.insert(grandparent)
        try context.save()

        let parent = Category(name: "Design", color: "#E74C3C", parentId: grandparent.id)
        context.insert(parent)
        try context.save()

        let error = engine.validateSubcategory(
            parentId: parent.id,
            allCategories: [grandparent, parent]
        )
        #expect(error != nil)
    }

    @Test("Top-level category (no parent) always passes validation")
    @MainActor
    func topLevelCategoryValid() throws {
        let (engine, _) = try makeEngine()
        let error = engine.validateSubcategory(parentId: nil, allCategories: [])
        #expect(error == nil)
    }

    // MARK: - Concurrent Timer Behavior

    @Test("When allowConcurrentTimers is off, starting new timer stops previous")
    @MainActor
    func concurrentTimersOff() throws {
        let (engine, context) = try makeEngine()
        engine.allowConcurrentTimers = false
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

    @Test("When allowConcurrentTimers is on, previous timer keeps running")
    @MainActor
    func concurrentTimersOn() throws {
        let (engine, context) = try makeEngine()
        engine.allowConcurrentTimers = true
        let work = Category(name: "Work", color: "#4A90D9")
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        context.insert(work)
        context.insert(exercise)
        try context.save()

        engine.startTimer(for: work)
        let workEntry = engine.activeEntry!
        engine.startTimer(for: exercise)

        // Work entry should still be running
        #expect(workEntry.isRunning == true)
        // Active entry pointer moves to the newly started one
        #expect(engine.activeEntry?.category?.id == exercise.id)
    }

    // MARK: - Archive Hides from Tracking Grid

    @Test("Archived category is hidden from non-archived fetch")
    @MainActor
    func archivedCategoryHidden() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Old Project", color: "#9B59B6")
        context.insert(category)
        try context.save()

        engine.archiveCategory(category)

        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { !$0.isArchived && $0.deletedAt == nil }
        )
        let visible = try context.fetch(descriptor)
        #expect(visible.isEmpty)
    }

    @Test("Non-archived category is visible in fetch")
    @MainActor
    func nonArchivedCategoryVisible() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Active Project", color: "#4A90D9")
        context.insert(category)
        try context.save()

        // Do NOT archive
        _ = engine

        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { !$0.isArchived && $0.deletedAt == nil }
        )
        let visible = try context.fetch(descriptor)
        #expect(visible.count == 1)
    }

    // MARK: - Category Sort Order

    @Test("updateCategorySortOrders assigns sequential indices")
    @MainActor
    func sortOrderUpdate() throws {
        let (engine, context) = try makeEngine()
        let a = Category(name: "A", color: "#4A90D9")
        let b = Category(name: "B", color: "#E74C3C")
        let c = Category(name: "C", color: "#2ECC71")
        context.insert(a)
        context.insert(b)
        context.insert(c)
        try context.save()

        engine.updateCategorySortOrders([c, a, b])

        #expect(c.sortOrder == 0)
        #expect(a.sortOrder == 1)
        #expect(b.sortOrder == 2)
    }
}
