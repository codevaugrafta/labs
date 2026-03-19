import SwiftUI
import SwiftData

/// The Tiempo Signature layout — replaces system TabView with a custom dark sidebar.
/// Only shown when SignatureTheme is active (usesCustomLayout == true).
struct SignatureContentView: View {
    @Environment(TimeEntryEngine.self) private var engine
    @State private var selectedTab: SignatureTab = .tracking
    @State private var timerTick = Date()

    enum SignatureTab: String, CaseIterable {
        case tracking = "Tracking"
        case schedule = "Schedule"
        case events = "Events"
        case timeline = "Timeline"
        case goals = "Goals"

        var icon: String {
            switch self {
            case .tracking: return "timer"
            case .schedule: return "calendar"
            case .events: return "list.bullet.clipboard"
            case .timeline: return "chart.bar.xaxis"
            case .goals: return "target"
            }
        }
    }

    private let tm = ThemeManager.shared

    var body: some View {
        HStack(spacing: 0) {
            // ── Custom Sidebar ──
            VStack(spacing: 0) {
                // Logo area
                VStack(spacing: 4) {
                    Text("TIEMPO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(tm.accent)
                    Rectangle()
                        .fill(tm.accent.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Active timer mini-display in sidebar
                if let active = engine.activeEntry, let cat = active.category {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: cat.color) ?? .blue)
                                .frame(width: 6, height: 6)
                                .timerPulse(isActive: true)
                            Text("RECORDING")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(tm.accent.opacity(0.5))
                        }
                        Text(active.formattedDuration)
                            .font(.system(size: 18, weight: .light, design: .monospaced))
                            .foregroundStyle(tm.timerText)
                            .contentTransition(.numericText())
                        Text(cat.name)
                            .font(.system(size: 10))
                            .foregroundStyle(tm.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(tm.border)
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                // Tab buttons
                ForEach(SignatureTab.allCases, id: \.self) { tab in
                    SidebarButton(
                        tab: tab,
                        isSelected: tab == selectedTab,
                        accent: tm.accent,
                        textSecondary: tm.textSecondary,
                        surface: tm.surfaceHover
                    ) {
                        withAnimation(.spring(response: tm.springResponse, dampingFraction: tm.springDamping)) {
                            selectedTab = tab
                        }
                    }
                }

                Spacer()

                // Adherence score at bottom of sidebar
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(tm.border)
                        .frame(height: 1)
                    HStack {
                        Text("ADHERENCE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(tm.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .padding(.bottom, 12)
            }
            .frame(width: 170)
            .background(tm.background)

            // ── Divider ──
            Rectangle()
                .fill(tm.border)
                .frame(width: 1)

            // ── Content Area ──
            ZStack {
                tm.surface.opacity(0.3)

                switch selectedTab {
                case .tracking:
                    TrackingView()
                case .schedule:
                    ScheduleView()
                case .events:
                    EventsView()
                case .timeline:
                    TimelineView()
                case .goals:
                    GoalsView()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(tm.background)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timerTick = Date()
            }
        }
    }
}

// MARK: - Sidebar Button

private struct SidebarButton: View {
    let tab: SignatureContentView.SignatureTab
    let isSelected: Bool
    let accent: Color
    let textSecondary: Color
    let surface: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? accent : textSecondary)
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accent : textSecondary)
                Spacer()
                if isSelected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accent)
                        .frame(width: 2, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accent.opacity(0.08) : (isHovered ? surface : Color.clear))
                    .padding(.horizontal, 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
