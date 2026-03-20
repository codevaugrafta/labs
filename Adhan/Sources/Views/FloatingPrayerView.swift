import SwiftUI

struct FloatingPrayerView: View {
    let engine: PrayerTimesEngine
    let onClose: () -> Void
    private let tm = AdhanThemeManager.shared

    @State private var tick = Date()
    @State private var isHovered = false
    @AppStorage("adhan_floatingPanelSize") private var sizeLevel: Int = 1

    private var scale: CGFloat { [0.85, 1.0, 1.15][min(sizeLevel, 2)] }
    private var padding: CGFloat { [10, 14, 18][min(sizeLevel, 2)] }
    private var timeCol: CGFloat { [40, 44, 48][min(sizeLevel, 2)] }

    private var showIqamahColumn: Bool {
        let g = engine.mosqueGuid ?? ""
        return !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            prayerList
        }
        .scaleEffect(scale)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tm.background.opacity(0.95))
                .shadow(color: tm.accent.opacity(0.15), radius: 24, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(tm.border, lineWidth: 0.5)
                )
        )
        .islamicPatternOverlay()
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { isHovered = h } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
                engine.tick()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            // Controls (on hover)
            HStack {
                // Hijri date
                Text(engine.hijriEngine.hijriDateString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tm.textTertiary)

                Spacer()

                if isHovered {
                    HStack(spacing: 8) {
                        Button { cycleSize() } label: {
                            Image(systemName: sizeIcon)
                                .font(.system(size: 9))
                                .foregroundStyle(tm.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help(sizeLabel)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tm.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, padding)
            .padding(.top, padding)

            // Next prayer countdown
            if let next = engine.nextPrayer {
                HStack(spacing: 10) {
                    // Crescent accent
                    CrescentMoon(phase: 0.35)
                        .fill(tm.accentSecondary)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.prayer.displayName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tm.textPrimary)
                        if next.isNextDayPreview {
                            Text("Tomorrow")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tm.accent)
                        }
                        Text(next.prayer.arabicName)
                            .font(.system(size: 12))
                            .foregroundStyle(tm.textTertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(next.formattedBeginTime)
                            .font(.system(size: 24, weight: .light, design: .monospaced))
                            .foregroundStyle(tm.accent)
                        Text(next.isNextDayPreview ? "Tomorrow · in \(next.formattedCountdown)" : "in \(next.formattedCountdown)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(tm.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tm.color(for: next.prayer).opacity(0.08))
                )
                .padding(.horizontal, padding)
                .adhanPulse(isActive: true, color: tm.color(for: next.prayer))
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Prayer List

    private var prayerList: some View {
        VStack(spacing: 0) {
            if showIqamahColumn {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 6, height: 1)
                    Color.clear.frame(width: 18, height: 1)
                    Text("Prayer")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tm.textTertiary)
                    Spacer(minLength: 4)
                    Text("Begins")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tm.textTertiary)
                        .frame(width: timeCol, alignment: .trailing)
                    Text("Iqamah")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tm.textTertiary)
                        .frame(width: timeCol, alignment: .trailing)
                }
                .padding(.horizontal, padding)
                .padding(.bottom, 2)
            }
            ForEach(engine.todayEntries) { entry in
                let isNext = entry.id == engine.nextPrayer?.id
                let isPassed = entry.hasPassed

                HStack(spacing: 10) {
                    // Status dot
                    Circle()
                        .fill(isPassed ? tm.textTertiary : tm.color(for: entry.prayer))
                        .frame(width: 6, height: 6)

                    // Prayer icon
                    Image(systemName: entry.prayer.systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(isPassed ? tm.textTertiary : tm.color(for: entry.prayer))
                        .frame(width: 18)

                    // Name
                    Text(entry.prayer.displayName)
                        .font(.system(size: 12, weight: isNext ? .semibold : .regular))
                        .foregroundStyle(isPassed && !isNext ? tm.textTertiary : tm.textPrimary)

                    Spacer(minLength: 4)

                    Text({ _ = tick; return entry.formattedBeginTime }())
                        .font(.system(size: 12, weight: isNext ? .medium : .regular, design: .monospaced))
                        .foregroundStyle(isPassed && !isNext ? tm.textTertiary : tm.textSecondary)
                        .frame(width: timeCol, alignment: .trailing)

                    if showIqamahColumn {
                        Text(entry.formattedIqamahTime ?? "—")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(entry.formattedIqamahTime == nil ? tm.textTertiary.opacity(0.5) : tm.textTertiary)
                            .frame(width: timeCol, alignment: .trailing)
                    }
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 6)
                .background(isNext ? tm.color(for: entry.prayer).opacity(0.06) : .clear)
                .prayerTransition(isNext: isNext)
            }
        }
        .padding(.bottom, padding)
    }

    // MARK: - Size Control

    private func cycleSize() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            sizeLevel = (sizeLevel + 1) % 3
        }
    }

    private var sizeIcon: String {
        sizeLevel < 2 ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
    }

    private var sizeLabel: String { ["Small", "Medium", "Large"][min(sizeLevel, 2)] }
}
