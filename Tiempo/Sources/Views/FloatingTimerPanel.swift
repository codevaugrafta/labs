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
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
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
            panel.setFrameOrigin(NSPoint(x: sf.midX - 120, y: sf.midY + sf.height * 0.25))
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

// MARK: - Main floating view

struct FloatingTimerView: View {
    let engine: TimeEntryEngine
    let onClose: () -> Void

    @State private var tick = Date()
    @State private var isHovered = false
    @State private var showPicker = false
    @State private var scale: CGFloat = 1.0

    var body: some View {
        let tm = ThemeManager.shared
        VStack(spacing: 0) {
            timerRow
            if CountdownTimer.shared.isActive { countdownRow }
            if !CountdownTimer.shared.isActive && isHovered { setCountdownButton }
            if isHovered && engine.activeEntry == nil { favoritesRow }
            if showPicker { pickerSection }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tm.surface.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tm.border, lineWidth: 0.5))
        )
        .scaleEffect(scale)
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { isHovered = h } }
        .onScrollWheel { d in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                scale = max(0.7, min(1.6, scale + d * 0.05))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showPicker)
        .onReceive(NotificationCenter.default.publisher(for: .openCountdownPicker)) { _ in
            withAnimation { showPicker = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
                CountdownTimer.shared.tick()
            }
        }
    }

    // MARK: - Sub-views

    private var timerRow: some View {
        let tm = ThemeManager.shared
        return HStack(spacing: 10) {
            if let entry = engine.activeEntry, let cat = entry.category {
                Circle().fill(Color(hex: cat.color) ?? tm.accent).frame(width: 8, height: 8)
                    .timerPulse(isActive: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text({ _ = tick; return entry.formattedDuration }())
                        .font(.system(size: 18, weight: .light, design: .monospaced))
                        .foregroundStyle(tm.textPrimary)
                        .contentTransition(.numericText())
                    Text(cat.name).font(.system(size: 10)).foregroundStyle(tm.textTertiary)
                }
            } else {
                Image(systemName: "timer").font(.system(size: 12)).foregroundStyle(tm.textTertiary)
                Text("No timer").font(.system(size: 12)).foregroundStyle(tm.textTertiary)
            }
            Spacer(minLength: 4)
            if engine.activeEntry != nil {
                Button { TiempoFeedback.onTimerStop(); engine.stopTimer() } label: {
                    Circle().fill(tm.destructive).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 8, height: 8))
                }.buttonStyle(.plain)
            }
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(tm.textTertiary)
                }.buttonStyle(.plain).transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var countdownRow: some View {
        let tm = ThemeManager.shared
        let cd = CountdownTimer.shared
        let remaining = { _ = tick; return cd.formattedRemaining }()
        let isLow = cd.remainingSeconds <= 60
        return HStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 10)).foregroundStyle(isLow ? tm.destructive : tm.accent)
            Text(remaining).font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(isLow ? tm.destructive : tm.textPrimary).contentTransition(.numericText())
            Spacer(minLength: 4)
            Button { if cd.isRunning { cd.pause() } else { cd.resume() } } label: {
                Image(systemName: cd.isRunning ? "pause.fill" : "play.fill").font(.system(size: 9)).foregroundStyle(tm.accent)
            }.buttonStyle(.plain)
            Button { cd.stop() } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(tm.textTertiary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var setCountdownButton: some View {
        let tm = ThemeManager.shared
        return Button { withAnimation { showPicker.toggle() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "hourglass.badge.plus").font(.system(size: 9))
                Text("Set countdown").font(.system(size: 10))
            }.foregroundStyle(tm.textTertiary).padding(.horizontal, 14).padding(.bottom, 6)
        }.buttonStyle(.plain).transition(.opacity)
    }

    private var favoritesRow: some View {
        let tm = ThemeManager.shared
        let favs = Array(engine.favoriteCategories.prefix(5))
        return Group {
            if !favs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(favs, id: \.id) { cat in
                        Button { TiempoFeedback.onTimerStart(); engine.toggleTimer(for: cat) } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: cat.color) ?? tm.accent).frame(width: 6, height: 6)
                                Text(cat.name).font(.system(size: 9)).foregroundStyle(tm.textSecondary)
                            }.padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(tm.background))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 6).transition(.opacity)
            }
        }
    }

    private var pickerSection: some View {
        CountdownPickerView { h, m in
            CountdownTimer.shared.start(hours: h, minutes: m)
            withAnimation { showPicker = false }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Scroll Wheel

struct ScrollWheelModifier: ViewModifier {
    let action: (CGFloat) -> Void
    func body(content: Content) -> some View {
        content.background(ScrollWheelReceiver(action: action))
    }
}
struct ScrollWheelReceiver: NSViewRepresentable {
    let action: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScrollWheelNSView { let v = ScrollWheelNSView(); v.action = action; return v }
    func updateNSView(_ v: ScrollWheelNSView, context: Context) { v.action = action }
}
class ScrollWheelNSView: NSView {
    var action: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) { action?(event.deltaY) }
}
extension View {
    func onScrollWheel(action: @escaping (CGFloat) -> Void) -> some View { modifier(ScrollWheelModifier(action: action)) }
}

// MARK: - Countdown Picker (stepper-based, no broken drag)

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
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(h > 0 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(h <= 0)
                    Text("\(h)").font(.system(size: 20, weight: .medium, design: .monospaced)).foregroundStyle(tm.textPrimary).frame(width: 24)
                    Button { adj(60) } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(totalMinutes < 480 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(totalMinutes >= 480)
                }
            }
            Text(":").font(.system(size: 20, weight: .light)).foregroundStyle(tm.textTertiary)
            VStack(spacing: 2) {
                Text("MINUTES").font(.system(size: 8, weight: .bold)).tracking(2).foregroundStyle(tm.textTertiary)
                HStack(spacing: 8) {
                    Button { adj(-5) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(totalMinutes > 5 ? tm.accent : tm.textTertiary)
                    }.buttonStyle(.plain).disabled(totalMinutes <= 5)
                    Text(String(format: "%02d", m)).font(.system(size: 20, weight: .medium, design: .monospaced)).foregroundStyle(tm.textPrimary).frame(width: 30)
                    Button { adj(5) } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(totalMinutes < 480 ? tm.accent : tm.textTertiary)
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
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(totalMinutes == mins ? .white : tm.textTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(totalMinutes == mins ? tm.accent : tm.background))
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
