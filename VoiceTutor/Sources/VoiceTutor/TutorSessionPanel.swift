import ElevenLabs
import SwiftUI

/// Shared session UI for the popover and main window.
struct TutorSessionPanel: View {
    @ObservedObject var session: TutorSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Tutor")
                .font(.title2.weight(.semibold))

            if let err = session.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Dismiss error") {
                    session.clearError()
                }
                .buttonStyle(.borderless)
            }

            controlRow

            if let conv = session.conversation {
                ConversationSubview(conversation: conv)
            } else {
                Text("No active session. Set your Agent ID in Settings, then start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var controlRow: some View {
        HStack(spacing: 8) {
            if session.conversation == nil {
                Button("Start session") {
                    Task { await session.startSession() }
                }
                .disabled(session.isBusy)
            } else {
                Button("End session", role: .destructive) {
                    Task { await session.endSession() }
                }
                Button("Toggle mute") {
                    Task { await session.toggleMute() }
                }
            }
            if session.isBusy {
                ProgressView()
                    .scaleEffect(0.7)
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
                    }
                }
            }
            .frame(minHeight: 120)
        }
    }

    private func roleLabel(_ role: Message.Role) -> String {
        switch role {
        case .user: "You"
        case .agent: "Tutor"
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

    var body: some View {
        TutorSessionPanel(session: session)
            .padding(16)
            .frame(width: 340, height: 440)
    }
}

struct VoiceTutorMainView: View {
    @ObservedObject var session: TutorSessionController

    var body: some View {
        TutorSessionPanel(session: session)
            .padding(24)
            .frame(minWidth: 480, minHeight: 520)
    }
}
