import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class TimeEntryEngine {
    var activeEntry: TimeEntry?
    var lastError: String?
    var showCrashRecovery = false
    var recoveredEntry: TimeEntry?

    /// When true, starting a new timer does NOT stop the current one.
    var allowConcurrentTimers: Bool {
        get { UserDefaults.standard.bool(forKey: "allowConcurrentTimers") }
        set { UserDefaults.standard.set(newValue, forKey: "allowConcurrentTimers") }
    }

    private(set) var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = context
        let found = findRunningEntry()
        if let found {
            // Check if this is a zombie timer from a previous session
            let timeSinceStart = Date().timeIntervalSince(found.startedAt)
            let fiveMinutes: TimeInterval = 300
            if timeSinceStart > fiveMinutes && found.endedAt == nil {
                // Likely a crash recovery — prompt the user
                recoveredEntry = found
                showCrashRecovery = true
            } else {
                activeEntry = found
            }
        }
    }

    func keepRecoveredTimer() {
        activeEntry = recoveredEntry
        recoveredEntry = nil
        showCrashRecovery = false
    }

    func trimRecoveredTimer(to date: Date) {
        guard let entry = recoveredEntry else { return }
        entry.endedAt = date
        entry.isRunning = false
        entry.updatedAt = Date()
        save()
        recoveredEntry = nil
        showCrashRecovery = false
    }

    func discardRecoveredTimer() {
        guard let entry = recoveredEntry else { return }
        entry.deletedAt = Date()
        entry.isRunning = false
        entry.updatedAt = Date()
        save()
        recoveredEntry = nil
        showCrashRecovery = false
    }

    func startTimer(for category: Category) {
        guard let modelContext else { return }

        if !allowConcurrentTimers, let running = activeEntry {
            stopTimer(running)
        }

        let entry = TimeEntry(category: category)
        modelContext.insert(entry)
        activeEntry = entry
        save()
    }

    func stopTimer(_ entry: TimeEntry? = nil) {
        let target = entry ?? activeEntry
        guard let target, target.isRunning else { return }

        target.endedAt = Date()
        target.isRunning = false
        target.updatedAt = Date()

        if target.id == activeEntry?.id {
            activeEntry = nil
        }
        save()
    }

    func toggleTimer(for category: Category) {
        if let running = findRunningEntry(for: category) {
            stopTimer(running)
        } else {
            startTimer(for: category)
        }
    }

    /// Toggle the currently active timer (stop if running, no-op if nothing running).
    /// Used by global hotkey.
    func toggleCurrentTimer() {
        if let active = activeEntry {
            stopTimer(active)
        }
    }

    func isActive(category: Category) -> Bool {
        findRunningEntry(for: category) != nil
    }

    /// All currently running entries (supports concurrent timers).
    var runningEntries: [TimeEntry] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.isRunning && $0.deletedAt == nil }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Retroactive & Edit

    @discardableResult
    func addRetroactiveEntry(category: Category, startedAt: Date, endedAt: Date, note: String? = nil) -> TimeEntry? {
        guard let modelContext else { return nil }
        let entry = TimeEntry(category: category, startedAt: startedAt, endedAt: endedAt, note: note)
        modelContext.insert(entry)
        save()
        return entry
    }

    /// Update a time entry. Pass `updateNote: true` with `note: nil` to explicitly clear the note.
    func updateEntry(
        _ entry: TimeEntry,
        category: Category? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        note: String? = nil,
        updateNote: Bool = false
    ) {
        if let category { entry.category = category }
        if let startedAt { entry.startedAt = startedAt }
        if let endedAt { entry.endedAt = endedAt }
        if let note {
            entry.note = note.isEmpty ? nil : note
        } else if updateNote {
            entry.note = nil
        }
        entry.updatedAt = Date()
        save()
    }

    func softDeleteEntry(_ entry: TimeEntry) {
        entry.deletedAt = Date()
        entry.updatedAt = Date()
        if entry.isRunning {
            entry.isRunning = false
            entry.endedAt = Date()
            if entry.id == activeEntry?.id {
                activeEntry = nil
            }
        }
        save()
    }

    // MARK: - Tag Management

    func addTag(name: String) -> Tag? {
        guard let modelContext else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Return existing tag if duplicate (case-insensitive)
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let lowered = trimmed.lowercased()
        if let match = existing.first(where: { $0.name.lowercased() == lowered }) {
            return match
        }

        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        save()
        return tag
    }

    func updateTag(_ tag: Tag, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tag.name = trimmed
        tag.updatedAt = Date()
        save()
    }

    func deleteTag(_ tag: Tag) {
        tag.deletedAt = Date()
        tag.updatedAt = Date()
        save()
    }

    func assignTag(_ tag: Tag, to entry: TimeEntry) {
        guard !entry.tags.contains(where: { $0.id == tag.id }) else { return }
        entry.tags.append(tag)
        entry.updatedAt = Date()
        save()
    }

    func removeTag(_ tag: Tag, from entry: TimeEntry) {
        entry.tags.removeAll { $0.id == tag.id }
        entry.updatedAt = Date()
        save()
    }

    // MARK: - Favorites

    func toggleFavorite(_ category: Category) {
        category.isFavorite.toggle()
        category.updatedAt = Date()
        save()
    }

    var favoriteCategories: [Category] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived && $0.isFavorite },
            sortBy: [SortDescriptor(\Category.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Category Management

    func archiveCategory(_ category: Category) {
        category.isArchived = true
        category.updatedAt = Date()
        save()
    }

    func canDeleteCategory(_ category: Category) -> Bool {
        guard let modelContext else { return category.timeEntries.isEmpty }
        if !category.timeEntries.isEmpty { return false }

        let catId = category.id
        let blockDescriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let blocks = (try? modelContext.fetch(blockDescriptor)) ?? []
        if blocks.contains(where: { $0.category?.id == catId }) { return false }

        let goalDescriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let goals = (try? modelContext.fetch(goalDescriptor)) ?? []
        if goals.contains(where: { $0.category?.id == catId }) { return false }

        return true
    }

    /// Returns nil if valid; returns error message if invalid.
    func validateSubcategory(parentId: UUID?, allCategories: [Category]) -> String? {
        guard let parentId else { return nil } // no parent = top-level, always valid
        // Enforce 1-level max: parent must not itself have a parent
        guard let parent = allCategories.first(where: { $0.id == parentId }) else {
            return "Parent category not found."
        }
        if parent.parentId != nil {
            return "Subcategories cannot be nested more than one level."
        }
        return nil
    }

    func updateCategorySortOrders(_ categories: [Category]) {
        for (index, category) in categories.enumerated() {
            category.sortOrder = index
            category.updatedAt = Date()
        }
        save()
    }

    private func findRunningEntry() -> TimeEntry? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.isRunning && $0.deletedAt == nil }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func findRunningEntry(for category: Category) -> TimeEntry? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.isRunning && $0.deletedAt == nil }
        )
        let catId = category.id
        return (try? modelContext.fetch(descriptor))?.first { $0.category?.id == catId }
    }

    private func save() {
        do {
            try modelContext?.save()
            lastError = nil
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }
}
