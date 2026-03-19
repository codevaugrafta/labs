import AppKit
import SwiftUI

@MainActor
final class FloatingTimerPanel {
    private var panel: NSPanel?
    private weak var engine: TimeEntryEngine?

    func setup(engine: TimeEntryEngine) {
        self.engine = engine
    }

    func show() {
        guard let engine, panel == nil else { return }
        let content = FloatingTimerView(engine: engine, onClose: { [weak self] in self?.hide() })
        let hostingView = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: sf.midX - 160, y: sf.midY + sf.height * 0.25))
        }
        panel.orderFront(nil)
        self.panel = panel
    }

    func showWithCountdownPicker() {
        show()
        NotificationCenter.default.post(name: .openCountdownPicker, object: nil)
    }

    func hide() { panel?.close(); panel = nil }
    var isVisible: Bool { panel != nil }
}

extension Notification.Name {
    static let openCountdownPicker = Notification.Name("openCountdownPicker")
    static let autoShowFloatingTimer = Notification.Name("autoShowFloatingTimer")
}

// MARK: - Floating Timer View

struct FloatingTimerView: View {
    let engine: TimeEntryEngine
    let onClose: () -> Void
    private let countdown = CountdownTimer.shared
    private let tm = ThemeManager.shared

    @State private var tick = Date()
    @State private var isHovered = false
    @State private var showPicker = false
    @AppStorage("floatingTimerSize") private var sizeLevel: Int = 1 // 0=small, 1=medium, 2=large

    private var timerFontSize: CGFloat { [22, 32, 44][min(sizeLevel, 2)] }
    private var labelFontSize: CGFloat { [10, 13, 16][min(sizeLevel, 2)] }
    private var countdownFontSize: CGFloat { [16, 22, 30][min(sizeLevel, 2)] }
    private var dotSize: CGFloat { [8, 12, 16][min(sizeLevel, 2)] }
    private var stopSize: CGFloat { [24, 32, 40][min(sizeLevel, 2)] }
    private var stopIconSize: CGFloat { [8, 12, 16][min(sizeLevel, 2)] }
    private var padding: CGFloat { [12, 18, 24][min(sizeLevel, 2)] }

    var body: some View {
        VStack(spacing: 0) {
            timerRow
            if countdown.isActive { countdownRow }
            if !countdown.isActive && isHovered { setCountdownButton }
            if isHovered && engine.activeEntry == nil { favoritesRow }
            if showPicker { pickerSection }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tm.surface.opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tm.border, lineWidth: 0.5))
        )
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { isHovered = h } }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showPicker)
        .onReceive(NotificationCenter.default.publisher(for: .openCountdownPicker)) { _ in
            withAnimation { showPicker = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
                countdown.tick()
            }
        }
    }

    // MARK: - Timer Row

    private var timerRow: some View {
        HStack(spacing: 12) {
            if let entry = engine.activeEntry, let cat = entry.category {
                Circle()
                    .fill(Color(hex: cat.color) ?? tm.accent)
                    .frame(width: dotSize, height: dotSize)
                    .timerPulse(isActive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text({ _ = tick; return entry.formattedDuration }())
                        .font(.system(size: timerFontSize, weight: .light, design: .monospaced))
                        .foregroundStyle(tm.textPrimary)
                        .contentTransition(.numericText())
                    Text(cat.name)
                        .font(.system(size: labelFontSize))
                        .foregroundStyle(tm.textTertiary)
                }
            } else {
                Image(systemName: "timer")
                    .font(.system(size: labelFontSize))
                    .foregroundStyle(tm.textTertiary)
                Text("No timer")
                    .font(.system(size: labelFontSize))
                    .foregroundStyle(tm.textTertiary)
            }

            Spacer(minLength: 8)

            // Stop button
            if engine.activeEntry != nil {
                Button { TiempoFeedback.onTimerStop(); engine.stopTimer() } label: {
                    Circle()
                        .fill(tm.destructive)
                        .frame(width: stopSize, height: stopSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white)
                                .frame(width: stopIconSize, height: stopIconSize)
                        )
                }
                .buttonStyle(.plain)
            }

            // Size + Close (on hover)
            if isHovered {
                VStack(spacing: 4) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tm.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Button { cycleSize() } label: {
                        Image(systemName: sizeIcon)
                            .font(.system(size: 9))
                            .foregroundStyle(tm.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Resize: \(sizeLabel)")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, padding)
        .padding(.vertical, padding * 0.7)
    }

    // MARK: - Countdown Row

    private var countdownRow: some View {
        let cd = countdown
        let remaining = { _ = tick; return cd.formattedRemaining }()
        let isLow = cd.remainingSeconds <= 60
        return HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: labelFontSize * 0.8))
                .foregroundStyle(isLow ? tm.destructive : tm.accent)
            Text(remaining)
                .font(.system(size: countdownFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(isLow ? tm.destructive : tm.textPrimary)
                .contentTransition(.numericText())
            Spacer(minLength: 4)
            Button { if cd.isRunning { cd.pause() } else { cd.resume() } } label: {
                Image(systemName: cd.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11)).foregroundStyle(tm.accent)
            }.buttonStyle(.plain)
            Button { cd.stop() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(tm.textTertiary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, padding).padding(.bottom, padding * 0.5)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Set Countdown

    private var setCountdownButton: some View {
        Button { withAnimation { showPicker.toggle() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "hourglass.badge.plus").font(.system(size: 10))
                Text("Set countdown").font(.system(size: 11))
            }.foregroundStyle(tm.textTertiary)
                .padding(.horizontal, padding).padding(.bottom, padding * 0.4)
        }.buttonStyle(.plain).transition(.opacity)
    }

    // MARK: - Favorites

    private var favoritesRow: some View {
        let favs = Array(engine.favoriteCategories.prefix(5))
        return Group {
            if !favs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(favs, id: \.id) { cat in
                        Button { TiempoFeedback.onTimerStart(); engine.toggleTimer(for: cat) } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: cat.color) ?? tm.accent).frame(width: 6, height: 6)
                                Text(cat.name).font(.system(size: 10)).foregroundStyle(tm.textSecondary)
                            }.padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(tm.background))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, padding).padding(.bottom, padding * 0.4).transition(.opacity)
            }
        }
    }

    // MARK: - Picker

    private var pickerSection: some View {
        CountdownPickerView { h, m in
            countdown.start(hours: h, minutes: m)
            withAnimation { showPicker = false }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Size Control

    private func cycleSize() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            sizeLevel = (sizeLevel + 1) % 3
        }
    }

    private var sizeIcon: String {
        switch sizeLevel {
        case 0: return "arrow.up.left.and.arrow.down.right" // will grow
        case 1: return "arrow.up.left.and.arrow.down.right"
        case 2: return "arrow.down.right.and.arrow.up.left" // will shrink
        default: return "arrow.up.left.and.arrow.down.right"
        }
    }

    private var sizeLabel: String { ["Small", "Medium", "Large"][min(sizeLevel, 2)] }
}

// MARK: - Countdown Picker

struct CountdownPickerView: View {
    let onStart: (_ hours: Int, _ minutes: Int) -> Void
    @State private var totalMinutes: Int = 30

    var body: some View {
        let tm = ThemeManager.shared
        let h = totalMinutes / 60
        let m = totalMinutes % 60

        VStack(spacing: 10) {
            Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                .font(.system(size: 22, weight: .light, design: .monospaced))
                .foregroundStyle(tm.textPrimary)
                .contentTransition(.numericText())

            stepperRow(tm: tm, h: h, m: m)
            presetsRow(tm: tm)

            Button { onStart(h, m) } label: {
                Text("Start").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(tm.accent))
            }.buttonStyle(.plain)
        }.padding(.vertical, 6)
    }

    private func stepperRow(tm: ThemeManager, h: Int, m: Int) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("HOURS").font(.system(size: 8, weight: .bold)).tracking(2).foregroundStyle(tm.textTertiary)
                HStack(spacing: 8) {
                    Button { adj(-60) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(h > 0 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(h <= 0)
                    Text("\(h)").font(.system(size: 22, weight: .medium, design: .monospaced)).foregroundStyle(tm.textPrimary).frame(width: 28)
                    Button { adj(60) } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(totalMinutes < 480 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(totalMinutes >= 480)
                }
            }
            Text(":").font(.system(size: 22, weight: .light)).foregroundStyle(tm.textTertiary)
            VStack(spacing: 2) {
                Text("MINUTES").font(.system(size: 8, weight: .bold)).tracking(2).foregroundStyle(tm.textTertiary)
                HStack(spacing: 8) {
                    Button { adj(-5) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(totalMinutes > 5 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(totalMinutes <= 5)
                    Text(String(format: "%02d", m)).font(.system(size: 22, weight: .medium, design: .monospaced)).foregroundStyle(tm.textPrimary).frame(width: 34)
                    Button { adj(5) } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(totalMinutes < 480 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(totalMinutes >= 480)
                }
            }
        }
    }

    private func presetsRow(tm: ThemeManager) -> some View {
        HStack(spacing: 4) {
            ForEach([5, 15, 25, 30, 45, 60, 90, 120, 180], id: \.self) { mins in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { totalMinutes = mins }
                } label: {
                    Text(mins >= 60 ? "\(mins/60)h" : "\(mins)m")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(totalMinutes == mins ? .white : tm.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(totalMinutes == mins ? tm.accent : tm.background))
                }.buttonStyle(.plain)
            }
        }
    }

    private func adj(_ delta: Int) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            totalMinutes = max(5, min(480, totalMinutes + delta))
        }
    }
}
