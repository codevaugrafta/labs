import AppKit
import ElevenLabs
import SwiftUI

/// Shared session UI for the popover and main window.
struct TutorSessionPanel: View {
    @ObservedObject var session: TutorSessionController
    /// Always use `AppDelegate.showSettings()` — `@Environment(\.openSettings)` is unreliable for LSUIElement apps.
    let openSettingsAction: () -> Void

    @AppStorage(TutorPreferences.StorageKey.agentId) private var agentIdStorage = ""
    @AppStorage(TutorPreferences.StorageKey.useTokenBroker) private var useTokenBrokerStorage = false

    private var agentConfigured: Bool {
        !agentIdStorage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var agentPreview: String {
        let id = agentIdStorage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "Not set" }
        if id.count <= 12 { return id }
        return String(id.prefix(6)) + "…" + String(id.suffix(4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Agent ID") {
                            Text(agentPreview)
                                .font(.body.monospaced())
                                .foregroundStyle(agentConfigured ? .primary : .secondary)
                        }
                        LabeledContent("Auth") {
                            Text(useTokenBrokerStorage ? "Token broker" : "Public agent")
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            "ElevenLabs is used only after you tap Start session (LiveKit + ConvAI). This screen is local until then."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Configuration", systemImage: "slider.horizontal.3")
                }

                if let err = session.lastError {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(err)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            Button("Dismiss") {
                                session.clearError()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Error", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                controlRow

                Button(action: openSettingsAction) {
                    Label("Open Settings…", systemImage: "gearshape.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(",", modifiers: .command)
                .help("Set Agent ID and token broker (⌘,)")

                if let conv = session.conversation {
                    ConversationSubview(conversation: conv)
                } else {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No live session")
                                .font(.subheadline.weight(.medium))
                            Text(
                                "Add your ConvAI Agent ID in Settings, then start. You need network access; the microphone is used only while connected."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Session", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("IMI")
                    .font(.largeTitle.weight(.semibold))
                Text("Voice companion · ElevenLabs ConvAI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var controlRow: some View {
        HStack(spacing: 10) {
            if session.conversation == nil {
                Button {
                    Task { await session.startSession() }
                } label: {
                    Label("Start session", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isBusy || !agentConfigured)
                .help(agentConfigured ? "Connect to ElevenLabs with your Agent ID" : "Set an Agent ID in Settings first")
            } else {
                Button(role: .destructive) {
                    Task { await session.endSession() }
                } label: {
                    Label("End session", systemImage: "phone.down.fill")
                }
                .disabled(session.isBusy)
                Button {
                    Task { await session.toggleMute() }
                } label: {
                    Label("Mic", systemImage: "mic.fill")
                }
                .disabled(session.isBusy)
            }
            if session.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
    }
}

struct ConversationSubview: View {
    @ObservedObject var conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                Text("Status: \(conversationStatus(conversation.state))")
                Text("Agent: \(agentStateLabel(conversation.agentState))")
                Text("Mic: \(conversation.isMuted ? "muted" : "live")")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            Divider()

            Text("Transcript")
                .font(.subheadline.weight(.medium))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(conversation.messages) { msg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(roleLabel(msg.role))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(msg.content)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .id(msg.id)
                        }
                    }
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    if let id = conversation.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 120)
        }
    }

    private func roleLabel(_ role: Message.Role) -> String {
        switch role {
        case .user: "You"
        case .agent: "IMI"
        }
    }

    private func conversationStatus(_ state: ConversationState) -> String {
        switch state {
        case .idle: "idle"
        case .connecting: "connecting…"
        case .active(let info): "active · \(info.agentId)"
        case .ended(let reason): "ended · \(endReasonLabel(reason))"
        case .error(let err): "error · \(err.localizedDescription)"
        }
    }

    private func endReasonLabel(_ reason: EndReason) -> String {
        switch reason {
        case .userEnded: "you ended"
        case .agentNotConnected: "agent not connected"
        case .remoteDisconnected: "remote disconnected"
        }
    }

    private func agentStateLabel(_ state: ElevenLabs.AgentState) -> String {
        switch state {
        case .listening: "listening"
        case .speaking: "speaking"
        case .thinking: "thinking"
        }
    }
}

struct TutorPopoverView: View {
    @ObservedObject var session: TutorSessionController
    let openSettingsAction: () -> Void

    var body: some View {
        TutorSessionPanel(session: session, openSettingsAction: openSettingsAction)
            .padding(16)
            .frame(width: 340, height: 440)
    }
}

struct VoiceTutorMainView: View {
    @ObservedObject var session: TutorSessionController
    let openSettingsAction: () -> Void

    var body: some View {
        TutorSessionPanel(session: session, openSettingsAction: openSettingsAction)
            .frame(minWidth: 480, minHeight: 520)
    }
}
