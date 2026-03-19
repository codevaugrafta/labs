import Foundation
import SwiftData

/// Computes plan-vs-actual accountability scores per the PRD formula.
@MainActor
final class AccountabilityEngine {
    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Core Types

    struct BlockReport {
        let block: ScheduledBlock
        let categoryName: String
        let color: String
        let plannedMinutes: Int
        let actualMinutes: Int
        let adherence: Double        // 0.0 - 1.0 (capped)
        let status: BlockStatus

        var isExceeded: Bool { actualMinutes > Int(Double(plannedMinutes) * 1.1) }
    }

    enum BlockStatus: String {
        case onTrack = "On Track"
        case partial = "Partial"
        case skipped = "Skipped"
        case lateStart = "Late Start"
        case earlyEnd = "Early End"
        case exceeded = "Exceeded"
    }

    struct DayReport {
        let date: Date
        let blocks: [BlockReport]
        let unscheduledMinutes: Int
        let score: Double?           // nil = N/A (no schedule)

        var hasSchedule: Bool { !blocks.isEmpty }

        var scoreLabel: String {
            guard let score else { return "N/A" }
            return "\(Int(score * 100))%"
        }
    }

    // MARK: - Compute Daily Report

    func dailyReport(for date: Date) -> DayReport {
        guard let modelContext else {
            return DayReport(date: date, blocks: [], unscheduledMinutes: 0, score: nil)
        }

        let scheduleEngine = ScheduleEngine()
        scheduleEngine.configure(with: modelContext)
        let weekStart = scheduleEngine.mondayOfWeek(containing: date)
        let dayOfWeek = Calendar.current.component(.weekday, from: date) - 1 // 0=Sun

        let scheduledBlocks = scheduleEngine.blocksForDay(weekStart: weekStart, dayOfWeek: dayOfWeek)

        if scheduledBlocks.isEmpty {
            return DayReport(date: date, blocks: [], unscheduledMinutes: totalTrackedMinutes(for: date), score: nil)
        }

        let entries = timeEntries(for: date)
        var blockReports: [BlockReport] = []
        var accountedMinutes = 0

        let lateThreshold = UserDefaults.standard.integer(forKey: "lateStartThreshold")
        let earlyThreshold = UserDefaults.standard.integer(forKey: "earlyEndThreshold")
        let lateMin = lateThreshold > 0 ? lateThreshold : 10
        let earlyMin = earlyThreshold > 0 ? earlyThreshold : 10

        for block in scheduledBlocks {
            guard let cat = block.category else { continue }

            let plannedMinutes = block.durationMinutes
            let (blockStart, blockEnd) = blockTimeRange(block, on: date)

            // Calculate actual minutes tracked to this category within the block window
            var actualMinutes = 0
            var firstTrackedTime: Date?
            var lastTrackedTime: Date?

            for entry in entries where entry.category?.id == cat.id {
                let entryStart = max(entry.startedAt, blockStart)
                let entryEnd = min(entry.endedAt ?? date, blockEnd)

                if entryStart < entryEnd {
                    let overlap = Int(entryEnd.timeIntervalSince(entryStart) / 60)
                    actualMinutes += overlap
                    accountedMinutes += overlap

                    if firstTrackedTime == nil || entryStart < firstTrackedTime! {
                        firstTrackedTime = entryStart
                    }
                    if lastTrackedTime == nil || entryEnd > lastTrackedTime! {
                        lastTrackedTime = entryEnd
                    }
                }
            }

            let adherence = plannedMinutes > 0 ? min(Double(actualMinutes) / Double(plannedMinutes), 1.0) : 0.0

            // Determine status
            let status: BlockStatus
            let exceeded = actualMinutes > Int(Double(plannedMinutes) * 1.1)

            if adherence < 0.1 {
                status = .skipped
            } else if exceeded {
                status = .exceeded
            } else if let first = firstTrackedTime, first.timeIntervalSince(blockStart) > Double(lateMin * 60) {
                status = .lateStart
            } else if let last = lastTrackedTime, blockEnd.timeIntervalSince(last) > Double(earlyMin * 60), adherence < 0.9 {
                status = .earlyEnd
            } else if adherence >= 0.9 {
                status = .onTrack
            } else {
                status = .partial
            }

            blockReports.append(BlockReport(
                block: block,
                categoryName: cat.name,
                color: cat.color,
                plannedMinutes: plannedMinutes,
                actualMinutes: actualMinutes,
                adherence: adherence,
                status: status
            ))
        }

        let totalTracked = totalTrackedMinutes(for: date)
        let unscheduled = max(0, totalTracked - accountedMinutes)

        let dailyScore = blockReports.isEmpty ? nil :
            blockReports.reduce(0.0) { $0 + $1.adherence } / Double(blockReports.count)

        return DayReport(
            date: date,
            blocks: blockReports,
            unscheduledMinutes: unscheduled,
            score: dailyScore
        )
    }

    // MARK: - Weekly Report

    func weeklyReport(weekStart: Date) -> [DayReport] {
        (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            return dailyReport(for: date)
        }
    }

    func weeklyScore(weekStart: Date) -> Double? {
        let reports = weeklyReport(weekStart: weekStart)
        let scored = reports.compactMap(\.score)
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / Double(scored.count)
    }

    // MARK: - Helpers

    private func timeEntries(for date: Date) -> [TimeEntry] {
        guard let modelContext else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate {
                $0.deletedAt == nil &&
                !$0.isRunning &&
                $0.startedAt < dayEnd &&
                ($0.endedAt != nil)
            },
            sortBy: [SortDescriptor(\TimeEntry.startedAt)]
        )
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []

        // Filter to entries that overlap with this day (handles midnight crossing)
        return allEntries.filter { entry in
            guard let endedAt = entry.endedAt else { return false }
            return entry.startedAt < dayEnd && endedAt > dayStart
        }
    }

    private func totalTrackedMinutes(for date: Date) -> Int {
        let entries = timeEntries(for: date)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        return entries.reduce(0) { total, entry in
            guard let endedAt = entry.endedAt else { return total }
            let clampedStart = max(entry.startedAt, dayStart)
            let clampedEnd = min(endedAt, dayEnd)
            return total + max(0, Int(clampedEnd.timeIntervalSince(clampedStart) / 60))
        }
    }

    private func blockTimeRange(_ block: ScheduledBlock, on date: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let (sh, sm) = block.startHourMinute
        let (eh, em) = block.endHourMinute
        let blockStart = calendar.date(bySettingHour: sh, minute: sm, second: 0, of: dayStart)!
        let blockEnd = calendar.date(bySettingHour: eh, minute: em, second: 0, of: dayStart)!
        return (blockStart, blockEnd)
    }
}
