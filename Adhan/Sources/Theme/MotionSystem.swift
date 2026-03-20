import SwiftUI
import AppKit

// MARK: - Theme-Aware Spring Animation

extension View {
    func adhanSpring() -> some View {
        let theme = AdhanThemeManager.shared.current
        return self.animation(
            .spring(response: theme.springResponse, dampingFraction: theme.springDamping),
            value: UUID()
        )
    }

    func adhanTransition() -> some View {
        let theme = AdhanThemeManager.shared.current
        return self.transition(
            .asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.98).combined(with: .opacity)
            )
        )
        .animation(.easeInOut(duration: theme.transitionDuration), value: UUID())
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

// MARK: - Crescent Moon Phase Animation

struct MoonPhaseModifier: ViewModifier {
    @State private var phase: CGFloat = 0.3

    func body(content: Content) -> some View {
        content
            .onAppear {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    phase = 0.6
                }
            }
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
}
