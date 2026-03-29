import SwiftUI
import SwiftData

/// Reading statistics sheet — totals, weekly summary, and a 7-day bar chart.
struct ReadingStatsView: View {
    @Query(sort: \ReadingSessionRecord.startedAt, order: .reverse) private var sessions: [ReadingSessionRecord]
    @Query private var vocabulary: [VocabularyEntry]

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading Stats")
                            .font(.headline)
                        Text("\(completedSessions.count) sessions recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if completedSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        statsGrid
                        Divider().padding(.horizontal)
                        weeklyChart
                        vocabularySection
                    }
                    .padding(16)
                }
            }
        }
        .accessibilityIdentifier("leo.stats.root")
        .frame(minWidth: 460, minHeight: 400)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No sessions yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start a reading session to see your stats here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Total Reading Time", value: formatDuration(totalTime), icon: "clock.fill", color: .blue)
            statCard(title: "This Week", value: "\(sessionsThisWeek.count) sessions", icon: "calendar", color: .purple)
            statCard(title: "Average Session", value: formatDuration(averageSession), icon: "chart.line.uptrend.xyaxis", color: .orange)
            statCard(title: "Longest Session", value: formatDuration(longestSession), icon: "trophy.fill", color: .yellow)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Weekly bar chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 7 Days")
                .font(.subheadline.weight(.medium))

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(last7Days, id: \.date) { day in
                    VStack(spacing: 4) {
                        // Bar
                        GeometryReader { geo in
                            let maxMinutes = maxDailyMinutes
                            let barHeight = maxMinutes > 0
                                ? CGFloat(day.minutes / maxMinutes) * geo.size.height
                                : 0
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day.minutes > 0 ? Color.accentColor : Color.secondary.opacity(0.2))
                                    .frame(height: max(barHeight, day.minutes > 0 ? 3 : 2))
                            }
                        }
                        .frame(height: 60)

                        // Day label
                        Text(day.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)

                        // Duration label
                        if day.minutes > 0 {
                            Text(shortDuration(minutes: day.minutes))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("–")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vocabulary section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Vocabulary")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 16) {
                vocabStat(label: "Encountered", value: vocabulary.count, color: .primary)
                vocabStat(label: "Known", value: vocabulary.filter { $0.state == .known }.count, color: .green)
                vocabStat(label: "Learning", value: vocabulary.filter { $0.state == .learning || $0.state == .familiar }.count, color: .yellow)
                vocabStat(label: "New", value: vocabulary.filter { $0.state == .unknown }.count, color: .red)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func vocabStat(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computed properties

    private var completedSessions: [ReadingSessionRecord] {
        sessions.filter { $0.endedAt != nil }
    }

    private var totalTime: TimeInterval {
        completedSessions.reduce(0) { $0 + $1.duration }
    }

    private var sessionsThisWeek: [ReadingSessionRecord] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return completedSessions.filter { $0.startedAt >= weekAgo }
    }

    private var averageSession: TimeInterval {
        guard !completedSessions.isEmpty else { return 0 }
        return totalTime / Double(completedSessions.count)
    }

    private var longestSession: TimeInterval {
        completedSessions.map(\.duration).max() ?? 0
    }

    // MARK: - 7-day chart data

    private struct DayData {
        let date: Date
        let label: String
        let minutes: Double
    }

    private var last7Days: [DayData] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let nextDay = cal.date(byAdding: .day, value: 1, to: day)!
            let dayMinutes = completedSessions
                .filter { $0.startedAt >= day && $0.startedAt < nextDay }
                .reduce(0.0) { $0 + $1.duration / 60.0 }
            let label = offset == 0 ? "Today" : shortDayLabel(for: day)
            return DayData(date: day, label: label, minutes: dayMinutes)
        }
    }

    private var maxDailyMinutes: Double {
        last7Days.map(\.minutes).max() ?? 1
    }

    // MARK: - Formatters

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return total > 0 ? "\(total)s" : "–"
        }
    }

    private func shortDuration(minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 {
            return "\(m / 60)h\(m % 60 > 0 ? "\(m % 60)m" : "")"
        }
        return "\(m)m"
    }

    private func shortDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
