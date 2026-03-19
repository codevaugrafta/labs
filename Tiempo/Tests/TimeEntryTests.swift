import Testing
import Foundation
@testable import Tiempo

@Suite("TimeEntry Model")
struct TimeEntryTests {

    @Test("TimeEntry initializes as running")
    func entryStartsRunning() {
        let category = Category(name: "Work", color: "#4A90D9")
        let entry = TimeEntry(category: category)

        #expect(entry.isRunning)
        #expect(entry.endedAt == nil)
        #expect(entry.category === category)
        #expect(entry.syncStatus == .pendingCreate)
    }

    @Test("TimeEntry duration calculates correctly for completed entry")
    func completedDuration() {
        let category = Category(name: "Work", color: "#4A90D9")
        let entry = TimeEntry(category: category)
        entry.startedAt = Date().addingTimeInterval(-3600) // 1 hour ago
        entry.endedAt = Date()
        entry.isRunning = false

        let duration = entry.duration
        #expect(duration >= 3599 && duration <= 3601)
    }

    @Test("TimeEntry formats duration as H:MM:SS")
    func durationFormatting() {
        let category = Category(name: "Work", color: "#4A90D9")
        let entry = TimeEntry(category: category)
        entry.startedAt = Date().addingTimeInterval(-3661) // 1 hour, 1 minute, 1 second ago
        entry.endedAt = Date()
        entry.isRunning = false

        #expect(entry.formattedDuration == "1:01:01")
    }

    @Test("TimeEntry formats short duration as M:SS")
    func shortDurationFormatting() {
        let category = Category(name: "Work", color: "#4A90D9")
        let entry = TimeEntry(category: category)
        entry.startedAt = Date().addingTimeInterval(-125) // 2 minutes 5 seconds ago
        entry.endedAt = Date()
        entry.isRunning = false

        #expect(entry.formattedDuration == "2:05")
    }
}
