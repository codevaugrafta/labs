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

        let content = FloatingTimerView(engine: engine) { [weak self] in
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: content)
        let panelHeight: CGFloat = 100

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: panelHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.hasShadow = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - 300,
                y: screenFrame.maxY - panelHeight - 20
            ))
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

// MARK: - Floating Timer View

struct FloatingTimerView: View {
    let engine: TimeEntryEngine
    let onClose: () -> Void
    private let countdown = CountdownTimer.shared

    @State private var tick = Date()

    var body: some View {
        VStack(spacing: 6) {
            // Tiempo category timer
            if let entry = engine.activeEntry, let cat = entry.category {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: cat.color) ?? .blue)
                        .frame(width: 8, height: 8)
                        .timerPulse(isActive: true)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(durationText(for: entry))
                            .font(.system(.title3, design: .monospaced).bold())
                            .contentTransition(.numericText())
                        Text(cat.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        TiempoFeedback.onTimerStop()
                        engine.stopTimer()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("No active timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Countdown timer (if active)
            if countdown.isActive {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(countdownText)
                            .font(.system(.callout, design: .monospaced).bold())
                            .foregroundStyle(countdown.remainingSeconds <= 60 ? .red : .primary)
                            .contentTransition(.numericText())
                        Text(countdown.targetLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if countdown.isRunning {
                        Button {
                            countdown.pause()
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            countdown.resume()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        countdown.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
                countdown.tick()
            }
        }
    }

    private func durationText(for entry: TimeEntry) -> String {
        _ = tick
        return entry.formattedDuration
    }

    private var countdownText: String {
        _ = tick
        return countdown.formattedRemaining
    }
}
