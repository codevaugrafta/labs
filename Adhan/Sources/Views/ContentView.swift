import SwiftUI

struct ContentView: View {
    @Environment(PrayerTimesEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(AppSettings.mainWindowTextSizeKey) private var textSizeTier: Int = 1
    @Bindable private var themeManager = AdhanThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Pinned header — always visible, never scrolls
            headerSection

            Divider()
                .transition(.opacity)

            // Scrollable prayer list — grows to fill available space
            ScrollView(.vertical, showsIndicators: false) {
                prayerListSection
                    .padding(.vertical, 8)
            }

            Divider()

            // Pinned footer
            footerSection
        }
        .frame(
            minWidth: 400, idealWidth: 480, maxWidth: .infinity,
            minHeight: 540, idealHeight: 640, maxHeight: .infinity
        )
        .background(mainWindowBackground)
        .environment(\.dynamicTypeSize, mainWindowDynamicTypeSize)
        .adhanSpring(value: engine.nextPrayer?.id)
        .adhanSpring(value: themeManager.themeVersion)
    }

    private var mainWindowBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.windowBackgroundColor),
                    themeManager.accent.opacity(0.07),
                    Color(.windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if themeManager.showsGeometricPattern {
                GeometricPattern(theme: themeManager.current, tileSize: 56, appliesThemeOpacity: false)
                    .opacity(min(themeManager.patternOpacity * 2.0, 0.10))
            }
        }
    }

    private var mainWindowDynamicTypeSize: DynamicTypeSize {
        switch textSizeTier {
        case 0: return .medium
        case 1: return .large
        case 2: return .xLarge
        default: return .xxLarge
        }
    }

    /// Scales fixed `.system(size:)` list fonts so the General setting has visible effect beyond semantic headers.
    private var listFontScale: CGFloat {
        switch textSizeTier {
        case 0: return 0.9
        case 1: return 1.0
        case 2: return 1.12
        default: return 1.26
        }
    }

    private var timeColumnWidth: CGFloat { max(44, 48 * listFontScale) }

    /// Show Iqamah column when a mosque is configured (times fill in after a successful fetch).
    private var showIqamahColumn: Bool {
        let g = engine.mosqueGuid ?? ""
        return !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            AdhanBrandHeader(markSize: 46)

            // Hijri date
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(themeManager.accent.opacity(0.85))
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: !accessibilityReduceMotion)
                Text(engine.hijriEngine.hijriDateString)
                    .font(.headline)
                    .contentTransition(.interpolate)
                Spacer()
                Text(engine.locationName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .adhanEaseTransition(value: engine.hijriEngine.hijriDateString)

            // Friday / Ramadan banners
            if engine.isFriday {
                HStack(spacing: 6) {
                    Text("\u{1F54C}")
                    Text("Jumu'ah Mubarak")
                        .font(.system(size: 12, weight: .semibold))
                    if let jummah = engine.jummahTime {
                        Spacer()
                        Text("Jumu'ah at \(jummah)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.accentSecondary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(themeManager.accentSecondary.opacity(0.25), lineWidth: 0.5)
                )
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if engine.isRamadan {
                HStack(spacing: 6) {
                    Text("\u{2728}")
                    Text("Ramadan Mubarak")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(engine.hijriEngine.arabicMonthName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(themeManager.accent.opacity(0.22), lineWidth: 0.5)
                )
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Next prayer countdown
            if let next = engine.nextPrayer {
                HStack(spacing: 12) {
                    Image(systemName: next.prayer.systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(prayerColor(next.prayer))
                        .frame(width: 40)
                        .symbolEffect(.variableColor.iterative, options: .repeating.speed(0.8), isActive: !accessibilityReduceMotion)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.isNextDayPreview ? "Next (tomorrow)" : "Next Prayer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(next.prayer.displayName)
                            .font(.title2.bold())
                            .contentTransition(.interpolate)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(next.formattedBeginTime)
                            .font(.system(.title3, design: .monospaced))
                            .contentTransition(.numericText())
                        Text("in \(next.formattedCountdown)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                        if let iq = next.formattedIqamahTime {
                            Text("Iqamah \(iq)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(prayerColor(next.prayer).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(prayerColor(next.prayer).opacity(0.28), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.bottom, 8)
        .animation(.spring(response: themeManager.springResponse, dampingFraction: themeManager.springDamping), value: engine.isFriday)
        .animation(.spring(response: themeManager.springResponse, dampingFraction: themeManager.springDamping), value: engine.isRamadan)
    }

    // MARK: - Prayer List

    private var prayerListSection: some View {
        VStack(spacing: 0) {
            // Column header
            HStack(spacing: 8) {
                Text("PRAYER")
                    .font(.system(size: 10 * listFontScale, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Text("BEGINS")
                    .font(.system(size: 10 * listFontScale, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)
                    .frame(width: timeColumnWidth, alignment: .trailing)
                if showIqamahColumn {
                    Text("IQAMAH")
                        .font(.system(size: 10 * listFontScale, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            ForEach(engine.todayEntries) { entry in
                prayerRow(entry)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                if entry.prayer != .isha {
                    Divider().padding(.leading)
                }
            }
        }
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func prayerRow(_ entry: PrayerTimeEntry) -> some View {
        let isNext = entry.id == engine.nextPrayer?.id
        let isPassed = entry.hasPassed

        return HStack(spacing: 12) {
            // Prayer icon
            Image(systemName: entry.prayer.systemImage)
                .font(.system(size: 16 * listFontScale))
                .foregroundStyle(prayerColor(entry.prayer))
                .frame(width: 24 * listFontScale)

            // Prayer name
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.prayer.displayName)
                    .font(.system(size: 14 * listFontScale, weight: isNext ? .semibold : .regular))
                    .foregroundStyle(isPassed && !isNext ? .secondary : .primary)

                Text(entry.prayer.arabicName)
                    .font(.system(size: 11 * listFontScale))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            // Begins
            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.formattedBeginTime)
                    .font(.system(size: 14 * listFontScale, weight: isNext ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(isPassed && !isNext ? .secondary : .primary)

                if isNext {
                    Text("in \(entry.formattedCountdown)")
                        .font(.system(size: 11 * listFontScale, design: .monospaced))
                        .foregroundStyle(prayerColor(entry.prayer))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: entry.formattedCountdown)
                }
            }
            .frame(width: timeColumnWidth, alignment: .trailing)

            // Iqamah (mosque source)
            if showIqamahColumn {
                Text(entry.formattedIqamahTime ?? "—")
                    .font(.system(size: 13 * listFontScale, weight: .regular, design: .monospaced))
                    .foregroundStyle(entry.formattedIqamahTime == nil ? .quaternary : (isPassed && !isNext ? .secondary : .primary))
                    .frame(width: timeColumnWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(isNext ? prayerColor(entry.prayer).opacity(0.06) : .clear)
        .adhanSpring(value: isNext)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            if let error = engine.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if engine.nextPrayer?.isNextDayPreview == true {
                Text("Times in the list are for today. The header counts down to tomorrow’s Fajr.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack {
                Text("Calculation: \(currentMethodName)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Spacer()
                Button("Recalculate") {
                    AdhanFeedback.onUIAction()
                    engine.recalculate()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func prayerColor(_ prayer: PrayerName) -> Color {
        themeManager.color(for: prayer)
    }

    private var currentMethodName: String {
        PrayerTimesEngine.availableCalculationMethods
            .first { $0.id == engine.calculationMethodId }?.name ?? "Unknown"
    }
}
