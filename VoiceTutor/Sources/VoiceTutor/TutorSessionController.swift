import Combine
import ElevenLabs
import Foundation

/// Owns the ElevenLabs `Conversation` lifecycle, tool-call handling, and user-visible status.
@MainActor
final class TutorSessionController: ObservableObject {
    @Published private(set) var conversation: Conversation?
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    private var toolCallCancellable: AnyCancellable?
    private var inFlightToolCallIds = Set<String>()

    init() {
        ElevenLabs.configure(ElevenLabs.Configuration(logLevel: .warning))
    }

    func clearError() {
        lastError = nil
    }

    func startSession() async {
        clearError()
        let agentId = TutorPreferences.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentId.isEmpty else {
            lastError = "Set an Agent ID in Settings."
            return
        }

        if conversation != nil {
            lastError = "A session is already active. End it first."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let config = makeConversationConfig()
            let conv: Conversation
            if TutorPreferences.useTokenBroker {
                guard let broker = TutorPreferences.brokerURL else {
                    lastError = "Invalid token broker URL in Settings."
                    return
                }
                let aid = agentId
                conv = try await ElevenLabs.startConversation(
                    tokenProvider: {
                        try await TokenBrokerClient.fetchToken(agentId: aid, brokerBase: broker)
                    },
                    config: config,
                    onDisconnect: { [weak self] _ in
                        Task { @MainActor in
                            self?.handleDisconnect()
                        }
                    }
                )
            } else {
                conv = try await ElevenLabs.startConversation(
                    agentId: agentId,
                    config: config,
                    onDisconnect: { [weak self] _ in
                        Task { @MainActor in
                            self?.handleDisconnect()
                        }
                    }
                )
            }
            inFlightToolCallIds.removeAll()
            conversation = conv
            bindToolCalls(conv)
            try await conv.setMuted(false)
        } catch {
            conversation = nil
            toolCallCancellable = nil
            inFlightToolCallIds.removeAll()
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func endSession() async {
        guard let conv = conversation else { return }
        toolCallCancellable = nil
        inFlightToolCallIds.removeAll()
        conversation = nil
        await conv.endConversation()
    }

    func toggleMute() async {
        guard let conv = conversation else { return }
        do {
            try await conv.toggleMute()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleDisconnect() {
        toolCallCancellable = nil
        inFlightToolCallIds.removeAll()
        conversation = nil
    }

    private func makeConversationConfig() -> ConversationConfig {
        ConversationConfig(
            onError: { [weak self] err in
                Task { @MainActor in
                    self?.lastError = err.localizedDescription
                }
            }
        )
    }

    private func bindToolCalls(_ conv: Conversation) {
        toolCallCancellable = conv.$pendingToolCalls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] calls in
                guard let self else { return }
                for call in calls where !inFlightToolCallIds.contains(call.toolCallId) {
                    inFlightToolCallIds.insert(call.toolCallId)
                    Task { @MainActor [weak self] in
                        await self?.handleClientToolCall(call)
                        self?.inFlightToolCallIds.remove(call.toolCallId)
                    }
                }
            }
    }

    private func handleClientToolCall(_ event: ClientToolCallEvent) async {
        guard let conv = conversation, conv.state.isActive else { return }

        do {
            let params = try event.getParameters()
            let payload: [String: Any] = [
                "ok": true,
                "tool": event.toolName,
                "echo": params
            ]
            try await conv.sendToolResult(for: event.toolCallId, result: payload)
        } catch {
            try? await conv.sendToolResult(
                for: event.toolCallId,
                result: ["error": error.localizedDescription],
                isError: true
            )
        }
    }
}
