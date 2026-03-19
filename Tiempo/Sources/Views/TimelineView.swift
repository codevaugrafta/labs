import SwiftUI
import SwiftData
import Charts

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TimeEntry> { !$0.isRunning && $0.deletedAt == nil },
           sort: \TimeEntry.startedAt, order: .reverse)
    private var allEntries: [TimeEntry]

    @Query(filter: #Predicate<Category> { $0.deletedAt == nil && !$0.isArchived },
           sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var selectedRange: DateRange = .week
    @State private var chartType: ChartType = .bar
    @State private var selectedCategories: Set<UUID> = []
    @State private var referenceDate = Date()

    enum DateRange: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
    }

    enum ChartType: String, CaseIterable {
        case bar = "Bar"
        case pie = "Pie"
        case timeline = "Timeline"
    }

    private var filteredEntries: [TimeEntry] {
        let (start, end) = dateRangeBounds
        return allEntries.filter { entry in
            guard let endedAt = entry.endedAt else { return false }
            let inRange = entry.startedAt < end && endedAt > start
            let inCategory = selectedCategories.isEmpty || (entry.category.map { selectedCategories.contains($0.id) } ?? false)
            return inRange && inCategory
        }
    }

    private var dateRangeBounds: (Date, Date) {
        let cal = Calendar.current
        switch selectedRange {
        case .day:
            let start = cal.startOfDay(for: referenceDate)
            return (start, cal.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            let start = cal.date(from: comps)!
            return (start, cal.date(byAdding: .weekOfYear, value: 1, to: start)!)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: referenceDate)
            let start = cal.date(from: comps)!
            return (start, cal.date(byAdding: .month, value: 1, to: start)!)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Timeline")
                    .font(.largeTitle.bold())
                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(DateRange.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Picker("Chart", selection: $chartType) {
                    ForEach(ChartType.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding()

            // Date navigation
            HStack {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Text(rangeLabel)
                    .font(.headline)
                    .frame(minWidth: 180)
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                Spacer()
                Button("Today") { referenceDate = Date() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        selectedCategories.removeAll()
                    } label: {
                        Text("All")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedCategories.isEmpty ? Color.accentColor : Color(.controlBackgroundColor))
                            .foregroundStyle(selectedCategories.isEmpty ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(categories) { cat in
                        let isOn = selectedCategories.contains(cat.id)
                        Button {
                            if isOn { selectedCategories.remove(cat.id) }
                            else { selectedCategories.insert(cat.id) }
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: cat.color) ?? .blue).frame(width: 8, height: 8)
                                Text(cat.name).font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isOn ? (Color(hex: cat.color) ?? .blue).opacity(0.2) : Color(.controlBackgroundColor))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 6)

            // Chart
            Group {
                switch chartType {
                case .bar:
                    StackedBarChart(entries: filteredEntries, range: selectedRange, bounds: dateRangeBounds)
                case .pie:
                    PieChartView(entries: filteredEntries)
                case .timeline:
                    HorizontalTimeline(entries: filteredEntries, bounds: dateRangeBounds)
                }
            }
            .padding()
        }
    }

    private var rangeLabel: String {
        let (start, end) = dateRangeBounds
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let endAdj = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        if selectedRange == .day { return start.formatted(date: .abbreviated, time: .omitted) }
        return "\(fmt.string(from: start)) – \(fmt.string(from: endAdj))"
    }

    private func navigate(_ direction: Int) {
        let cal = Calendar.current
        switch selectedRange {
        case .day: referenceDate = cal.date(byAdding: .day, value: direction, to: referenceDate)!
        case .week: referenceDate = cal.date(byAdding: .weekOfYear, value: direction, to: referenceDate)!
        case .month: referenceDate = cal.date(byAdding: .month, value: direction, to: referenceDate)!
        }
    }
}

// MARK: - Stacked Bar Chart

struct ChartDataPoint: Identifiable {
    let id: String
    let date: Date
    let category: String
    let color: String
    let minutes: Double
}

struct StackedBarChart: View {
    let entries: [TimeEntry]
    let range: TimelineView.DateRange
    let bounds: (Date, Date)

    private var dailyData: [ChartDataPoint] {
        let cal = Calendar.current
        var result: [ChartDataPoint] = []
        var date = bounds.0
        while date < bounds.1 {
            let dayEnd = cal.date(byAdding: .day, value: 1, to: date)!
            let dayEntries = entries.filter { entry in
                guard let end = entry.endedAt else { return false }
                return entry.startedAt < dayEnd && end > date
            }

            var byCat: [UUID: (name: String, color: String, minutes: Double)] = [:]
            for entry in dayEntries {
                guard let cat = entry.category, let end = entry.endedAt else { continue }
                let start = max(entry.startedAt, date)
                let clampEnd = min(end, dayEnd)
                let mins = clampEnd.timeIntervalSince(start) / 60
                byCat[cat.id, default: (cat.name, cat.color, 0)].minutes += mins
            }
            for (catId, val) in byCat {
                result.append(ChartDataPoint(
                    id: "\(date.timeIntervalSince1970)-\(catId)",
                    date: date, category: val.name, color: val.color, minutes: val.minutes
                ))
            }
            date = dayEnd
        }
        return result
    }

    var body: some View {
        Chart(dailyData) { item in
            BarMark(
                x: .value("Date", item.date, unit: .day),
                y: .value("Hours", item.minutes / 60)
            )
            .foregroundStyle(Color(hex: item.color) ?? .blue)
        }
        .chartYAxisLabel("Hours")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pie Chart

struct PieChartView: View {
    let entries: [TimeEntry]

    private var categoryTotals: [(name: String, color: String, minutes: Double)] {
        var byCat: [UUID: (name: String, color: String, minutes: Double)] = [:]
        for entry in entries {
            guard let cat = entry.category else { continue }
            let mins = entry.duration / 60
            byCat[cat.id, default: (cat.name, cat.color, 0)].minutes += mins
        }
        return byCat.values.sorted { $0.minutes > $1.minutes }
    }

    var body: some View {
        if categoryTotals.isEmpty {
            Text("No data for this period")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(categoryTotals, id: \.name) { item in
                SectorMark(
                    angle: .value("Minutes", item.minutes),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .foregroundStyle(Color(hex: item.color) ?? .blue)
                .annotation(position: .overlay) {
                    Text(item.name)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Horizontal Timeline

struct HorizontalTimeline: View {
    let entries: [TimeEntry]
    let bounds: (Date, Date)

    private let hourHeight: CGFloat = 40

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                // Hour grid
                ForEach(0..<24, id: \.self) { hour in
                    HStack(spacing: 4) {
                        Text(String(format: "%02d:00", hour))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                        Rectangle()
                            .fill(Color(.separatorColor).opacity(0.5))
                            .frame(height: 0.5)
                    }
                    .offset(y: CGFloat(hour) * hourHeight)
                }

                // Entry blocks
                ForEach(entries) { entry in
                    if let cat = entry.category, let range = clampedMinuteRange(for: entry) {
                        let top = CGFloat(range.start) / 60.0 * hourHeight
                        let height = max(CGFloat(range.end - range.start) / 60.0 * hourHeight, 16)

                        HStack(spacing: 4) {
                            Text(cat.name)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                            Spacer()
                            Text(entry.formattedDuration)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .frame(height: height, alignment: .center)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: cat.color) ?? .blue))
                        .offset(x: 48, y: top)
                    }
                }
            }
            .frame(height: 24 * hourHeight)
            .padding()
        }
    }

    /// Clamp entry times to the current day's bounds for safe rendering.
    private func clampedMinuteRange(for entry: TimeEntry) -> (start: Int, end: Int)? {
        guard let endedAt = entry.endedAt else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: entry.startedAt)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let clampedStart = max(entry.startedAt, dayStart)
        let clampedEnd = min(endedAt, dayEnd)
        guard clampedStart < clampedEnd else { return nil }
        let startMin = minuteOfDay(clampedStart)
        let endMin = minuteOfDay(clampedEnd)
        return (startMin, max(endMin, startMin + 1)) // at least 1 minute for visibility
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
