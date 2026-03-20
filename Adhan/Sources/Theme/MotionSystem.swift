import SwiftUI
import AppKit

// MARK: - Theme-Aware Animation

extension View {
    /// Animates when `value` changes using the active theme’s spring parameters.
    func adhanSpring<V: Equatable>(value: V) -> some View {
        let t = AdhanThemeManager.shared
        return animation(
            .spring(response: t.springResponse, dampingFraction: t.springDamping),
            value: value
        )
    }

    func adhanEaseTransition<V: Equatable>(value: V) -> some View {
        let duration = AdhanThemeManager.shared.current.transitionDuration
        return animation(.easeInOut(duration: duration), value: value)
    }
}

// MARK: - Adhan Pulse (Prayer Time Indicator)

struct AdhanPulseModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        let speed = AdhanThemeManager.shared.current.pulseSpeed

        content
            .opacity(isActive ? (isPulsing ? 0.5 : 1.0) : 1.0)
            .scaleEffect(isActive ? (isPulsing ? 1.1 : 1.0) : 1.0)
            .shadow(color: isActive ? color.opacity(isPulsing ? 0.4 : 0.1) : .clear,
                    radius: isPulsing ? 12 : 4)
            .animation(
                isActive
                    ? .easeInOut(duration: speed).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if isActive { isPulsing = true }
            }
            .onChange(of: isActive) { _, newValue in
                isPulsing = newValue
            }
    }
}

extension View {
    func adhanPulse(isActive: Bool, color: Color = AdhanThemeManager.shared.accent) -> some View {
        modifier(AdhanPulseModifier(isActive: isActive, color: color))
    }
}

// MARK: - Prayer Transition Animation

struct PrayerTransitionModifier: ViewModifier {
    let isNext: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isNext ? 1.0 : 0.98)
            .opacity(isNext ? 1.0 : 0.7)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7),
                value: isNext
            )
    }
}

extension View {
    func prayerTransition(isNext: Bool) -> some View {
        modifier(PrayerTransitionModifier(isNext: isNext))
    }
}

// MARK: - Haptic + Sound Helpers

enum AdhanFeedback {
    @MainActor
    static func onPrayerTime() {
        AdhanThemeManager.shared.playPrayerFeedback()
    }

    @MainActor
    static func onThemeChange() {
        AdhanThemeManager.shared.playTransitionFeedback()
    }

    /// Short haptic + system “Pop” for successful button actions (macOS trackpad haptics where available).
    @MainActor
    static func onUIAction() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        if let pop = NSSound(named: "Pop") {
            pop.stop()
            pop.play()
        }
    }

    /// Haptic only — used when the floating panel appears (avoid stacking with Adhan audio).
    @MainActor
    static func onPanelReveal() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }
}
