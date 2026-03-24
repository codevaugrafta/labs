import SwiftUI

struct VoiceTutorSettingsView: View {
    @State private var agentId: String = TutorPreferences.agentId
    @State private var useTokenBroker: Bool = TutorPreferences.useTokenBroker
    @State private var brokerURLString: String = TutorPreferences.brokerURLString
    @State private var elevenLabsEnvironment: String = TutorPreferences.elevenLabsEnvironment

    var body: some View {
        Form {
            Section("Agent") {
                TextField("Agent ID", text: $agentId)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: agentId) { _, new in
                        TutorPreferences.agentId = new
                    }
                Text(
                    "Use the ConvAI agent ID from your ElevenLabs dashboard. With the token broker off, the agent must be public; private agents need the broker below."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Advanced (Swift SDK)") {
                TextField("Environment (optional)", text: $elevenLabsEnvironment)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: elevenLabsEnvironment) { _, new in
                        TutorPreferences.elevenLabsEnvironment = new
                    }
                Text(
                    "Only if ElevenLabs documents a deployment `environment` value for your account or region. Leave blank for the default. Match `ELEVENLABS_API_BASE` on the token broker when using private agents."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Private agent (token broker)") {
                Toggle("Use token broker", isOn: $useTokenBroker)
                    .onChange(of: useTokenBroker) { _, new in
                        TutorPreferences.useTokenBroker = new
                    }
                TextField("Broker base URL", text: $brokerURLString)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: brokerURLString) { _, new in
                        TutorPreferences.brokerURLString = new
                    }
                Text(
                    "Run `python3 scripts/elevenlabs_token_broker.py` from the VoiceTutor package directory with ELEVENLABS_API_KEY in your environment (the macOS app does not load .env.local). See docs/TOKEN_BROKER.md."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 340)
    }
}
