import SwiftUI

struct VoiceTutorSettingsView: View {
    @State private var agentId: String = TutorPreferences.agentId
    @State private var useTokenBroker: Bool = TutorPreferences.useTokenBroker
    @State private var brokerURLString: String = TutorPreferences.brokerURLString

    var body: some View {
        Form {
            Section("Agent") {
                TextField("Agent ID", text: $agentId)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: agentId) { _, new in
                        TutorPreferences.agentId = new
                    }
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
                    "Run `python3 scripts/elevenlabs_token_broker.py` from the VoiceTutor folder with ELEVENLABS_API_KEY set. See docs/TOKEN_BROKER.md."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 280)
    }
}
