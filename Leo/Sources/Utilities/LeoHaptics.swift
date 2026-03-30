import CoreHaptics
import AppKit

/// Lightweight haptic feedback helpers for Leo.
/// All methods are no-ops if the hardware does not support haptics (e.g. older Macs).
enum LeoHaptics {

    /// Plays a subtle selection tick — used when the user adds a word to SRS review.
    /// Creates a fresh `CHHapticEngine` per call; the call is fast (~1ms) and infrequent
    /// enough that engine reuse is not necessary.
    static func tick() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        guard let engine = try? CHHapticEngine() else { return }
        do {
            try engine.start()
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [sharpness, intensity],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Haptic failure is silent — never degrade the reading experience.
            NSLog("[LeoHaptics] tick failed: \(error)")
        }
    }
}
