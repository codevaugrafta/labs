import Foundation
import SwiftData
import Testing
@testable import Love

@Suite("LoveEngine")
struct LoveEngineTests {

    @MainActor
    private func makeEngine() throws -> (LoveEngine, ModelContext) {
        let schema = Schema([TaskSection.self, MustDoItem.self, CaptureCategory.self, LaterCapture.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let engine = LoveEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    @Test("Seed creates General section and Inbox category")
    @MainActor
    func seedCreatesDefaults() throws {
        let (_, context) = try makeEngine()
        let sections = try context.fetch(FetchDescriptor<TaskSection>())
        let cats = try context.fetch(FetchDescriptor<CaptureCategory>())
        #expect(sections.contains { $0.name == "General" })
        #expect(cats.contains { $0.name == "Inbox" })
    }

    @Test("Set and read focus")
    @MainActor
    func focusRoundTrip() throws {
        let (engine, context) = try makeEngine()
        let section = try #require(try context.fetch(FetchDescriptor<TaskSection>()).first)
        engine.addMustDo(title: "Deep work", section: section, bucket: .today)
        let items = try context.fetch(FetchDescriptor<MustDoItem>())
        let item = try #require(items.first)
        engine.setFocus(item)
        #expect(engine.focusedItemID == item.id)
        #expect(engine.focusedItem()?.title == "Deep work")
    }

    @Test("Deleting focus target clears pointer")
    @MainActor
    func focusClearedOnDelete() throws {
        let (engine, context) = try makeEngine()
        let section = try #require(try context.fetch(FetchDescriptor<TaskSection>()).first)
        engine.addMustDo(title: "A", section: section)
        let item = try #require(try context.fetch(FetchDescriptor<MustDoItem>()).first)
        engine.setFocus(item)
        engine.deleteMustDo(item)
        #expect(engine.focusedItemID == nil)
    }

    @Test("Complete focus advances to next incomplete in section")
    @MainActor
    func completeAdvances() throws {
        let (engine, context) = try makeEngine()
        let section = try #require(try context.fetch(FetchDescriptor<TaskSection>()).first)
        engine.addMustDo(title: "First", section: section)
        engine.addMustDo(title: "Second", section: section)
        let items = try context.fetch(FetchDescriptor<MustDoItem>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(items.count == 2)
        engine.setFocus(items[0])
        engine.completeFocused(advanceToNext: true)
        #expect(items[0].completedAt != nil)
        #expect(engine.focusedItem()?.title == "Second")
    }

    @Test("Planning bucket filter match")
    @MainActor
    func bucketMatch() throws {
        let (_, context) = try makeEngine()
        let section = try #require(try context.fetch(FetchDescriptor<TaskSection>()).first)
        let item = MustDoItem(title: "T", sortOrder: 0, section: section, planningBucket: .today)
        context.insert(item)
        try context.save()
        #expect(item.matches(listFilter: .today))
        #expect(item.matches(listFilter: .thisWeek))
        #expect(!item.matches(listFilter: .backlog))
    }

    @Test("Promote capture creates must-do and archives capture")
    @MainActor
    func promoteCapture() throws {
        let (engine, context) = try makeEngine()
        let section = try #require(try context.fetch(FetchDescriptor<TaskSection>()).first)
        let cat = try #require(try context.fetch(FetchDescriptor<CaptureCategory>()).first)
        let cap = LaterCapture(body: "Read https://example.com", category: cat)
        context.insert(cap)
        try context.save()
        engine.promoteCapture(cap, to: section)
        #expect(cap.isArchived)
        let items = try context.fetch(FetchDescriptor<MustDoItem>())
        #expect(items.contains { $0.title.contains("Read") })
    }

    @Test("Snooze hides from actionable until day")
    @MainActor
    func snooze() throws {
        let (_, context) = try makeEngine()
        let section = try #require(try context.fetch(FetchDescriptor<TaskSection>()).first)
        let item = MustDoItem(title: "Later", sortOrder: 0, section: section)
        let cal = Calendar.current
        let start = try #require(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())))
        item.snoozeUntil = start
        #expect(item.isSnoozed())
    }

    @Test("clearLastError clears save error banner state")
    @MainActor
    func clearLastErrorClears() throws {
        let (engine, _) = try makeEngine()
        engine.lastError = "Could not save"
        engine.clearLastError()
        #expect(engine.lastError == nil)
    }
}

@Suite("LoveDataMigration")
struct LoveDataMigrationTests {
    @Test("consumePendingUserFacingFailure returns once and clears UserDefaults")
    func consumeClearsKey() {
        let key = LoveDataMigration.pendingFailureUserDefaultsKey
        UserDefaults.standard.set("migration test message", forKey: key)
        let first = LoveDataMigration.consumePendingUserFacingFailure()
        #expect(first == "migration test message")
        #expect(UserDefaults.standard.string(forKey: key) == nil)
        #expect(LoveDataMigration.consumePendingUserFacingFailure() == nil)
    }
}
