import SwiftUI

/// Defines the complete visual language for an Adhan theme.
/// Islamic aesthetic: emerald/gold/midnight palettes, geometric patterns, calligraphic accents.
protocol AdhanTheme: Sendable {
    var id: String { get }
    var displayName: String { get }

    // MARK: Colors
    var background: Color { get }
    var surface: Color { get }
    var surfaceHover: Color { get }
    var border: Color { get }
    var accent: Color { get }              // Primary accent (emerald/gold)
    var accentSecondary: Color { get }     // Secondary accent
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }
    var prayerHighlight: Color { get }     // Next prayer glow
    var destructive: Color { get }
    var success: Color { get }
    var warning: Color { get }

    // Prayer-specific colors
    var fajrColor: Color { get }
    var dhuhrColor: Color { get }
    var asrColor: Color { get }
    var maghribColor: Color { get }
    var ishaColor: Color { get }
    var sunriseColor: Color { get }

    // MARK: Typography
    var timerFont: Font { get }
    var headingFont: Font { get }
    var arabicFont: Font { get }
    var labelFont: Font { get }
    var captionFont: Font { get }
    var labelLetterSpacing: CGFloat { get }

    // MARK: Spacing & Shape
    var cornerRadius: CGFloat { get }
    var tileCornerRadius: CGFloat { get }
    var tilePadding: CGFloat { get }

    // MARK: Animation
    var pulseSpeed: Double { get }
    var springResponse: Double { get }
    var springDamping: Double { get }
    var transitionDuration: Double { get }

    // MARK: Sounds
    var transitionSound: String? { get }

    // MARK: Haptic
    var hapticOnPrayer: Bool { get }

    // MARK: Layout
    var forcedAppearance: String? { get }
    var showsGeometricPattern: Bool { get }
    var patternOpacity: Double { get }
}

// MARK: - Defaults

extension AdhanTheme {
    var labelLetterSpacing: CGFloat { 1.0 }
    var cornerRadius: CGFloat { 12 }
    var tileCornerRadius: CGFloat { 12 }
    var tilePadding: CGFloat { 14 }
    var pulseSpeed: Double { 2.5 }
    var springResponse: Double { 0.5 }
    var springDamping: Double { 0.7 }
    var transitionDuration: Double { 0.35 }
    var transitionSound: String? { nil }
    var hapticOnPrayer: Bool { true }
    var forcedAppearance: String? { "dark" }
    var showsGeometricPattern: Bool { true }
    var patternOpacity: Double { 0.04 }

    func color(for prayer: PrayerName) -> Color {
        switch prayer {
        case .fajr:    return fajrColor
        case .sunrise: return sunriseColor
        case .dhuhr:   return dhuhrColor
        case .asr:     return asrColor
        case .maghrib: return maghribColor
        case .isha:    return ishaColor
        }
    }
}
