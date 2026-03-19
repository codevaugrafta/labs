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

        let content = FloatingTimerView(engine: engine, onClose: { [weak self] in
            self?.hide()
        })

        let hostingView = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
            let y = screenFrame.midY + screenFrame.height * 0.3
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
    }

    var isVisible: Bool { panel != nil }
}

// MARK: - Floating Timer View — Clean borderless widget

struct FloatingTimerView: View {
    let engine: TimeEntryEngine
    let onClose: () -> Void
    private let countdown = CountdownTimer.shared
    private let tm = ThemeManager.shared

    @State private var tick = Date()
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var showCountdownPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Main compact view
            HStack(spacing: 10) {
                // Category dot + timer
                if let entry = engine.activeEntry, let cat = entry.category {
                    Circle()
                        .fill(Color(hex: cat.color) ?? tm.accent)
                        .frame(width: 8, height: 8)
                        .timerPulse(isActive: true)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(tiempoText(for: entry))
                            .font(.system(size: 18, weight: .light, design: .monospaced))
                            .foregroundStyle(tm.textPrimary)
                            .contentTransition(.numericText())
                        Text(cat.name)
                            .font(.system(size: 10))
                            .foregroundStyle(tm.textTertiary)
                    }
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundStyle(tm.textTertiary)
                    Text("No timer")
                        .font(.system(size: 12))
                        .foregroundStyle(tm.textTertiary)
                }

                Spacer(minLength: 4)

                // Stop button (only when timer running)
                if engine.activeEntry != nil {
                    Button {
                        TiempoFeedback.onTimerStop()
                        engine.stopTimer()
                    } label: {
                        Circle()
                            .fill(tm.destructive)
                            .frame(width: 22, height: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white)
                                    .frame(width: 8, height: 8)
                            }
                    }
                    .buttonStyle(.plain)
                }

                // Close button (visible on hover)
                if isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(tm.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Countdown row (if active)
            if countdown.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 10))
                        .foregroundStyle(countdown.remainingSeconds <= 60 ? tm.destructive : tm.accent)

                    Text(countdownText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(countdown.remainingSeconds <= 60 ? tm.destructive : tm.textPrimary)
                        .contentTransition(.numericText())

                    Spacer(minLength: 4)

                    Button {
                        if countdown.isRunning { countdown.pause() }
                        else { countdown.resume() }
                    } label: {
                        Image(systemName: countdown.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(tm.accent)
                    }
                    .buttonStyle(.plain)

                    Button { countdown.stop() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(tm.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Set countdown button (when no countdown active, on hover)
            if !countdown.isActive && isHovered {
                Button {
                    showCountdownPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass.badge.plus")
                            .font(.system(size: 9))
                        Text("Set countdown")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(tm.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            // Radial countdown picker
            if showCountdownPicker {
                CountdownRadialPicker { hours, minutes in
                    countdown.start(hours: hours, minutes: minutes)
                    showCountdownPicker = false
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(tm.surface.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(tm.border, lineWidth: 0.5)
                }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: tm.springResponse, dampingFraction: tm.springDamping), value: countdown.isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showCountdownPicker)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
                countdown.tick()
            }
        }
    }

    private func tiempoText(for entry: TimeEntry) -> String {
        _ = tick
        return entry.formattedDuration
    }

    private var countdownText: String {
        _ = tick
        return countdown.formattedRemaining
    }
}

// MARK: - Radial Countdown Picker

struct CountdownRadialPicker: View {
    let onStart: (_ hours: Int, _ minutes: Int) -> Void

    @State private var selectedMinutes: Double = 30
    @State private var dragAngle: Double = 0
    private let tm = ThemeManager.shared

    private var hours: Int { Int(selectedMinutes) / 60 }
    private var mins: Int { Int(selectedMinutes) % 60 }

    var body: some View {
        VStack(spacing: 10) {
            // Circular dial
            ZStack {
                // Track
                Circle()
                    .strokeBorder(tm.border, lineWidth: 3)
                    .frame(width: 120, height: 120)

                // Progress arc
                Circle()
                    .trim(from: 0, to: selectedMinutes / 180) // 3 hours max
                    .stroke(tm.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                // Time display
                VStack(spacing: 0) {
                    Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                        .font(.system(size: 18, weight: .light, design: .monospaced))
                        .foregroundStyle(tm.textPrimary)
                        .contentTransition(.numericText())
                }

                // Drag handle
                Circle()
                    .fill(tm.accent)
                    .frame(width: 14, height: 14)
                    .shadow(color: tm.accent.opacity(0.4), radius: 4)
                    .offset(y: -60)
                    .rotationEffect(.degrees(selectedMinutes / 180 * 360))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let center = CGPoint(x: 60, y: 60)
                                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                                var degrees = (angle * 180 / .pi + 90).truncatingRemainder(dividingBy: 360)
                                if degrees < 0 { degrees += 360 }
                                let normalized: Double = degrees / 360.0 * 180.0
                                selectedMinutes = max(5, min(180, normalized))
                            }
                    )
            }
            .frame(width: 120, height: 120)

            // Quick presets
            HStack(spacing: 6) {
                ForEach([15, 30, 60, 120], id: \.self) { mins in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMinutes = Double(mins)
                        }
                    } label: {
                        Text(mins >= 60 ? "\(mins/60)h" : "\(mins)m")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Int(selectedMinutes) == mins ? tm.accent : tm.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Int(selectedMinutes) == mins ? tm.accent.opacity(0.15) : tm.background)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Start button
            Button {
                onStart(hours, mins)
            } label: {
                Text("Start")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(tm.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
