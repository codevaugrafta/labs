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
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 60)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
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

        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - 260,
                y: screenFrame.maxY - 80
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

struct FloatingTimerView: View {
    let engine: TimeEntryEngine
    let onClose: () -> Void

    @State private var tick = Date()

    var body: some View {
        Group {
            if let entry = engine.activeEntry, let cat = entry.category {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: cat.color) ?? .blue)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(durationText(for: entry))
                            .font(.system(.title3, design: .monospaced).bold())
                        Text(cat.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        engine.stopTimer()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                    Text("No active timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
            }
        }
    }

    private func durationText(for entry: TimeEntry) -> String {
        _ = tick
        return entry.formattedDuration
    }
}
