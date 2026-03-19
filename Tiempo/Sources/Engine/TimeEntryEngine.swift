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
        if let active = activeEntry, active.category?.id == category.id {
            stopTimer(active)
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
        activeEntry?.category?.id == category.id
    }

    // MARK: - Retroactive & Edit

    func addRetroactiveEntry(category: Category, startedAt: Date, endedAt: Date, note: String? = nil) {
        guard let modelContext else { return }
        let entry = TimeEntry(category: category, startedAt: startedAt, endedAt: endedAt, note: note)
        modelContext.insert(entry)
        save()
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

    // MARK: - Category Management

    func archiveCategory(_ category: Category) {
        category.isArchived = true
        category.updatedAt = Date()
        save()
    }

    func canDeleteCategory(_ category: Category) -> Bool {
        // Block deletion if category has entries, scheduled blocks, or goals
        return category.timeEntries.isEmpty
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

    private func save() {
        do {
            try modelContext?.save()
            lastError = nil
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }
}
