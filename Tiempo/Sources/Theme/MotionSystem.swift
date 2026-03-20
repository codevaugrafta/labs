import SwiftUI
import AppKit

// MARK: - Theme-Aware Animation Modifiers

extension View {
    /// Spring animation tuned to the current theme
    func themeSpring() -> some View {
        let theme = ThemeManager.shared.current
        return self.animation(
            .spring(response: theme.springResponse, dampingFraction: theme.springDamping),
            value: UUID() // Triggers on any state change
        )
    }

    /// Themed transition for appearing/disappearing content
    func themeTransition() -> some View {
        let theme = ThemeManager.shared.current
        return self.transition(
            .asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.98).combined(with: .opacity)
            )
        )
        .animation(.easeInOut(duration: theme.transitionDuration), value: UUID())
    }
}

// MARK: - Pulse Animation (active timer indicator)

struct PulseModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        let speed = ThemeManager.shared.current.timerPulseSpeed

        Group {
            if reduceMotion {
                content
            } else {
                content
                    .opacity(isActive ? (isPulsing ? 0.4 : 1.0) : 1.0)
                    .scaleEffect(isActive ? (isPulsing ? 1.15 : 1.0) : 1.0)
                    .animation(
                        isActive
                            ? .easeInOut(duration: speed).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
            }
        }
        .onAppear {
            if isActive && !reduceMotion { isPulsing = true }
        }
        .onChange(of: isActive) { _, newValue in
            isPulsing = newValue && !reduceMotion
        }
        .onChange(of: reduceMotion) { _, limited in
            if limited { isPulsing = false }
            else if isActive { isPulsing = true }
        }
    }
}

extension View {
    func timerPulse(isActive: Bool) -> some View {
        modifier(PulseModifier(isActive: isActive))
    }
}

// MARK: - Timer Start/Stop Animation

struct TimerBounceModifier: ViewModifier {
    @Binding var trigger: Bool
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        let theme = ThemeManager.shared.current

        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: theme.springResponse, dampingFraction: theme.springDamping)) {
                    scale = 0.92
                }
                withAnimation(.spring(response: theme.springResponse, dampingFraction: theme.springDamping).delay(0.1)) {
                    scale = 1.0
                }
            }
    }
}

extension View {
    func timerBounce(trigger: Binding<Bool>) -> some View {
        modifier(TimerBounceModifier(trigger: trigger))
    }
}

// MARK: - Haptic + Sound Helpers

enum TiempoFeedback {
    @MainActor
    static func onTimerStart() {
        ThemeManager.shared.playStartFeedback()
    }

    @MainActor
    static func onTimerStop() {
        ThemeManager.shared.playStopFeedback()
    }

    @MainActor
    static func onGoalComplete() {
        ThemeManager.shared.playCompleteFeedback()
    }
}
