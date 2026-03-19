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

    private var modelContext: ModelContext?

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

        if let running = activeEntry {
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

    func isActive(category: Category) -> Bool {
        activeEntry?.category?.id == category.id
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
