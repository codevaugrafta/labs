import SwiftUI

// MARK: - Theme Protocol

/// Defines the complete visual language for a Tiempo theme.
/// Each theme provides colors, typography, spacing, animation curves, and sound identifiers.
protocol TiempoTheme: Sendable {
    var id: String { get }
    var displayName: String { get }

    // MARK: Colors
    var background: Color { get }
    var surface: Color { get }
    var surfaceHover: Color { get }
    var border: Color { get }
    var accent: Color { get }
    var accentSecondary: Color { get }
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }
    var timerText: Color { get }
    var destructive: Color { get }
    var success: Color { get }
    var warning: Color { get }

    // MARK: Typography
    var timerFont: Font { get }
    var headingFont: Font { get }
    var labelFont: Font { get }
    var captionFont: Font { get }
    var labelLetterSpacing: CGFloat { get }

    // MARK: Spacing & Shape
    var cornerRadius: CGFloat { get }
    var tileCornerRadius: CGFloat { get }
    var tilePadding: CGFloat { get }

    // MARK: Animation
    var timerPulseSpeed: Double { get }     // seconds per cycle
    var springResponse: Double { get }
    var springDamping: Double { get }
    var transitionDuration: Double { get }

    // MARK: Sounds
    var startSound: String? { get }
    var stopSound: String? { get }
    var completeSound: String? { get }

    // MARK: Haptic
    var hapticOnStart: Bool { get }
    var hapticOnStop: Bool { get }
}

// MARK: - Theme Defaults

extension TiempoTheme {
    var labelLetterSpacing: CGFloat { 1.0 }
    var cornerRadius: CGFloat { 10 }
    var tileCornerRadius: CGFloat { 10 }
    var tilePadding: CGFloat { 12 }
    var timerPulseSpeed: Double { 2.0 }
    var springResponse: Double { 0.5 }
    var springDamping: Double { 0.7 }
    var transitionDuration: Double { 0.3 }
    var startSound: String? { nil }
    var stopSound: String? { nil }
    var completeSound: String? { nil }
    var hapticOnStart: Bool { true }
    var hapticOnStop: Bool { true }
}
