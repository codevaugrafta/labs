import Foundation
import SwiftData
import Observation
import OSLog

private extension Logger {
    static let love = Logger(subsystem: "com.franciscodilussor.love", category: "engine")
}

@MainActor
@Observable
final class LoveEngine {
    private static let focusIDKey = "Love.focusedMustDoItemID"
    private static let legacyFocusIDKey = "FocusPath.focusedMustDoItemID"

    var modelContext: ModelContext?
    var lastError: String?

    var focusedItemID: UUID? {
        get {
            if UserDefaults.standard.string(forKey: Self.focusIDKey) == nil,
               let legacy = UserDefaults.standard.string(forKey: Self.legacyFocusIDKey) {
                UserDefaults.standard.set(legacy, forKey: Self.focusIDKey)
                UserDefaults.standard.removeObject(forKey: Self.legacyFocusIDKey)
            }
            guard let str = UserDefaults.standard.string(forKey: Self.focusIDKey),
                  let id = UUID(uuidString: str)
            else { return nil }
            return id
        }
        set {
            UserDefaults.standard.removeObject(forKey: Self.legacyFocusIDKey)
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: Self.focusIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.focusIDKey)
            }
        }
    }

    func configure(with context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        seedIfNeeded()
        validateFocusPointer()
    }

    // MARK: - Seed

    func seedIfNeeded() {
        guard let modelContext else { return }
        let sectionDesc = FetchDescriptor<TaskSection>()
        let count = (try? modelContext.fetchCount(sectionDesc)) ?? 0
        guard count == 0 else { return }

        let general = TaskSection(name: "General", sortOrder: 0)
        modelContext.insert(general)

        let inbox = CaptureCategory(name: "Inbox", sortOrder: 0)
        modelContext.insert(inbox)

        save()
    }

    // MARK: - Focus

    func focusedItem() -> MustDoItem? {
        guard let modelContext, let id = focusedItemID else { return nil }
        let pred = #Predicate<MustDoItem> { $0.id == id && $0.completedAt == nil }
        var d = FetchDescriptor<MustDoItem>(predicate: pred)
        d.fetchLimit = 1
        return try? modelContext.fetch(d).first
    }

    func validateFocusPointer() {
        guard focusedItemID != nil else { return }
        if focusedItem() == nil {
            focusedItemID = nil
        }
    }

    func setFocus(_ item: MustDoItem) {
        guard item.completedAt == nil else { return }
        focusedItemID = item.id
        FeedbackPolicy.playFocusSet()
        save()
    }

    func clearFocus() {
        focusedItemID = nil
        save()
    }

    /// Complete focus; optionally advance to next incomplete in same section (wraps to top).
    func completeFocused(advanceToNext: Bool = true) {
        guard let item = focusedItem() else { return }
        let section = item.section
        let sort = item.sortOrder
        focusedItemID = nil
        item.completedAt = Date()
        item.updatedAt = Date()
        FeedbackPolicy.playTaskCompleted()
        if advanceToNext, let section, let next = nextIncomplete(afterSortOrder: sort, in: section) {
            focusedItemID = next.id
        }
        save()
    }

    /// Next incomplete task in section after `sortOrder`, or first incomplete if none after (wrap).
    private func nextIncomplete(afterSortOrder sort: Double, in section: TaskSection) -> MustDoItem? {
        guard let modelContext else { return nil }
        let sid = section.id
        let greater = #Predicate<MustDoItem> { m in
            m.completedAt == nil && m.section?.id == sid && m.sortOrder > sort
        }
        var d = FetchDescriptor<MustDoItem>(predicate: greater, sortBy: [SortDescriptor(\.sortOrder)])
        d.fetchLimit = 1
        if let found = try? modelContext.fetch(d).first { return found }
        let any = #Predicate<MustDoItem> { m in m.completedAt == nil && m.section?.id == sid }
        var d2 = FetchDescriptor<MustDoItem>(predicate: any, sortBy: [SortDescriptor(\.sortOrder)])
        d2.fetchLimit = 1
        return try? modelContext.fetch(d2).first
    }

    func complete(_ item: MustDoItem) {
        guard modelContext != nil else { return }
        let wasFocus = item.id == focusedItemID
        let section = item.section
        let sort = item.sortOrder
        if wasFocus { focusedItemID = nil }
        item.completedAt = Date()
        item.updatedAt = Date()
        FeedbackPolicy.playTaskCompleted()
        if wasFocus, let section, let next = nextIncomplete(afterSortOrder: sort, in: section) {
            focusedItemID = next.id
        }
        save()
    }

    // MARK: - Sections

    func addSection(named name: String) {
        guard let modelContext else { return }
        let maxOrder = (try? modelContext.fetch(FetchDescriptor<TaskSection>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])))?.first?.sortOrder ?? -1
        let s = TaskSection(name: name, sortOrder: maxOrder + 1)
        modelContext.insert(s)
        save()
    }

    func deleteSection(_ section: TaskSection, moveItemsTo target: TaskSection) {
        guard let modelContext else { return }
        for item in section.items {
            item.section = target
            item.updatedAt = Date()
        }
        modelContext.delete(section)
        validateFocusPointer()
        save()
    }

    // MARK: - Must-do CRUD

    func addMustDo(title: String, section: TaskSection, bucket: PlanningBucket = .backlog) {
        guard let modelContext else { return }
        let maxSort = section.items.map(\.sortOrder).max() ?? -1
        let item = MustDoItem(title: title, sortOrder: maxSort + 1, section: section, planningBucket: bucket)
        modelContext.insert(item)
        save()
    }

    func deleteMustDo(_ item: MustDoItem) {
        guard let modelContext else { return }
        if item.id == focusedItemID { focusedItemID = nil }
        modelContext.delete(item)
        save()
    }

    func deferToTomorrow(_ item: MustDoItem, calendar: Calendar = .current) {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        item.snoozeUntil = tomorrow
        item.updatedAt = Date()
        save()
    }

    func clearSnooze(_ item: MustDoItem) {
        item.snoozeUntil = nil
        item.updatedAt = Date()
        save()
    }

    func setPlanningBucket(_ item: MustDoItem, bucket: PlanningBucket) {
        item.planningBucket = bucket
        item.updatedAt = Date()
        save()
    }

    /// Move within section: `source` indices relative to sorted active items in that section.
    func moveItems(in section: TaskSection, activeOrdered: [MustDoItem], fromOffsets: IndexSet, toOffset: Int) {
        var ordered = activeOrdered
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (idx, item) in ordered.enumerated() {
            item.sortOrder = Double(idx)
            item.updatedAt = Date()
        }
        save()
    }

    // MARK: - Captures

    func addCapture(body: String, category: CaptureCategory?) {
        guard let modelContext else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cap = LaterCapture(body: trimmed, category: category)
        modelContext.insert(cap)
        FeedbackPolicy.playCaptureLanded()
        save()
    }

    func archiveCapture(_ capture: LaterCapture) {
        capture.archivedAt = Date()
        save()
    }

    func unarchiveCapture(_ capture: LaterCapture) {
        capture.archivedAt = nil
        save()
    }

    func promoteCapture(_ capture: LaterCapture, to section: TaskSection) {
        guard modelContext != nil else { return }
        let title = capture.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? capture.body
        let trimmed = String(title.prefix(500))
        addMustDo(title: trimmed, section: section, bucket: .backlog)
        archiveCapture(capture)
        save()
    }

    func addCaptureCategory(named name: String) {
        guard let modelContext else { return }
        let maxOrder = (try? modelContext.fetch(FetchDescriptor<CaptureCategory>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])))?.first?.sortOrder ?? -1
        let c = CaptureCategory(name: name, sortOrder: maxOrder + 1)
        modelContext.insert(c)
        save()
    }

    // MARK: - Save

    func save() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
            lastError = nil
            NotificationCenter.default.post(name: .loveDataDidChange, object: nil)
        } catch {
            Logger.love.error("save failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }
}
