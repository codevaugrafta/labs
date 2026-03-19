import SwiftUI
import SwiftData

struct CompareView: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date

    @State private var engine = AccountabilityEngine()
    @State private var report: AccountabilityEngine.DayReport?
    @State private var viewMode: CompareMode = .scoreCard

    enum CompareMode: String, CaseIterable {
        case scoreCard = "Score"
        case sideBySide = "Side by Side"
        case overlay = "Overlay"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker
            Picker("View", selection: $viewMode) {
                ForEach(CompareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if let report {
                if !report.hasSchedule {
                    noScheduleView
                } else {
                    switch viewMode {
                    case .scoreCard:
                        ScoreCardView(report: report)
                    case .sideBySide:
                        SideBySideView(report: report)
                    case .overlay:
                        OverlayView(report: report)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            engine.configure(with: modelContext)
            report = engine.dailyReport(for: date)
        }
        .onChange(of: date) {
            report = engine.dailyReport(for: date)
        }
    }

    private var noScheduleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No plan for this day")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let report {
                Text("\(report.unscheduledMinutes) minutes tracked (all unscheduled)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Score Card View

struct ScoreCardView: View {
    let report: AccountabilityEngine.DayReport

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Daily score
                VStack(spacing: 4) {
                    Text(report.scoreLabel)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreColor)
                    Text("Daily Adherence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                // Block-by-block breakdown
                ForEach(report.blocks, id: \.block.id) { blockReport in
                    BlockReportRow(report: blockReport)
                }

                if report.unscheduledMinutes > 0 {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.orange)
                        Text("\(report.unscheduledMinutes) min unscheduled")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    private var scoreColor: Color {
        guard let score = report.score else { return .secondary }
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }
}

struct BlockReportRow: View {
    let report: AccountabilityEngine.BlockReport

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: report.color) ?? .blue)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(report.categoryName)
                        .font(.body.bold())
                    Spacer()
                    StatusBadge(status: report.status)
                }
                HStack(spacing: 12) {
                    Text("\(report.actualMinutes)m / \(report.plannedMinutes)m")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ThemeManager.shared.border)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(adherenceColor)
                                .frame(width: geo.size.width * report.adherence, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(report.adherence * 100))%")
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(adherenceColor)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal)
    }

    private var adherenceColor: Color {
        if report.adherence >= 0.9 { return .green }
        if report.adherence >= 0.5 { return .orange }
        return .red
    }
}

struct StatusBadge: View {
    let status: AccountabilityEngine.BlockStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .onTrack: return .green
        case .exceeded: return .blue
        case .partial: return .orange
        case .lateStart: return .yellow
        case .earlyEnd: return .yellow
        case .skipped: return .red
        }
    }
}

// MARK: - Side by Side View

struct SideBySideView: View {
    let report: AccountabilityEngine.DayReport

    var body: some View {
        HStack(spacing: 0) {
            // Planned column
            VStack(alignment: .leading) {
                Text("Planned")
                    .font(.headline)
                    .padding(.bottom, 8)
                ForEach(report.blocks, id: \.block.id) { blockReport in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: blockReport.color) ?? .blue)
                            .frame(width: 4, height: 30)
                        VStack(alignment: .leading) {
                            Text(blockReport.categoryName)
                                .font(.caption.bold())
                            Text("\(blockReport.plannedMinutes) min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)

            Divider()

            // Actual column
            VStack(alignment: .leading) {
                Text("Actual")
                    .font(.headline)
                    .padding(.bottom, 8)
                ForEach(report.blocks, id: \.block.id) { blockReport in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: blockReport.color) ?? .blue)
                            .frame(width: 4, height: 30)
                        VStack(alignment: .leading) {
                            Text(blockReport.categoryName)
                                .font(.caption.bold())
                            Text("\(blockReport.actualMinutes) min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: blockReport.status)
                    }
                    .padding(.vertical, 4)
                }
                if report.unscheduledMinutes > 0 {
                    HStack {
                        Text("+ \(report.unscheduledMinutes) min unscheduled")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Overlay View

struct OverlayView: View {
    let report: AccountabilityEngine.DayReport
    private let hourHeight: CGFloat = 50

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                ForEach(report.blocks, id: \.block.id) { blockReport in
                    let (sh, sm) = blockReport.block.startHourMinute
                    let topOffset = CGFloat(sh * 60 + sm) / 60.0 * hourHeight
                    let plannedHeight = CGFloat(blockReport.plannedMinutes) / 60.0 * hourHeight
                    let actualHeight = CGFloat(blockReport.actualMinutes) / 60.0 * hourHeight
                    let color = Color(hex: blockReport.color) ?? .blue

                    // Planned outline
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(color, lineWidth: 2, antialiased: true)
                        .frame(height: max(plannedHeight, 20))
                        .offset(y: topOffset)
                        .overlay(alignment: .topLeading) {
                            Text(blockReport.categoryName)
                                .font(.caption2)
                                .foregroundStyle(color)
                                .padding(4)
                                .offset(y: topOffset)
                        }

                    // Actual fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.3))
                        .frame(height: max(actualHeight, 2))
                        .offset(y: topOffset)
                }
            }
            .frame(height: 24 * hourHeight)
            .padding()
        }
    }
}
