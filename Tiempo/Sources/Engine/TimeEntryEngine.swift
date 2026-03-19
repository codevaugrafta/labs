import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class TimeEntryEngine {
    var activeEntry: TimeEntry?

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        guard modelContext == nil else { return }
        self.modelContext = context
        self.activeEntry = findRunningEntry()
    }

    func startTimer(for category: Category) {
        guard let modelContext else { return }

        // Stop any currently running timer first
        if let running = activeEntry {
            stopTimer(running)
        }

        let entry = TimeEntry(category: category)
        modelContext.insert(entry)
        activeEntry = entry
        try? modelContext.save()
    }

    func stopTimer(_ entry: TimeEntry? = nil) {
        guard let modelContext else { return }
        let target = entry ?? activeEntry
        guard let target, target.isRunning else { return }

        target.endedAt = Date()
        target.isRunning = false
        target.updatedAt = Date()

        if target === activeEntry {
            activeEntry = nil
        }
        try? modelContext.save()
    }

    func toggleTimer(for category: Category) {
        if let active = activeEntry, active.category === category {
            stopTimer(active)
        } else {
            startTimer(for: category)
        }
    }

    private func findRunningEntry() -> TimeEntry? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.isRunning && $0.deletedAt == nil }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
