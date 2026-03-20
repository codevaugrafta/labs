import SwiftUI

// MARK: - Emerald Theme (Default)
// Deep emerald green + warm gold — classic Islamic aesthetic

struct EmeraldTheme: AdhanTheme {
    let id = "emerald"
    let displayName = "Emerald"

    let background = Color(red: 0.04, green: 0.08, blue: 0.06)         // Deep dark green-black
    let surface = Color(red: 0.06, green: 0.12, blue: 0.09)            // Dark emerald surface
    let surfaceHover = Color(red: 0.08, green: 0.16, blue: 0.12)
    let border = Color(red: 0.15, green: 0.30, blue: 0.22).opacity(0.3)
    let accent = Color(red: 0.10, green: 0.65, blue: 0.40)             // Emerald green
    let accentSecondary = Color(red: 0.85, green: 0.68, blue: 0.35)    // Islamic gold
    let textPrimary = Color(red: 0.92, green: 0.95, blue: 0.93)        // Soft white-green
    let textSecondary = Color.white.opacity(0.55)
    let textTertiary = Color.white.opacity(0.25)
    let prayerHighlight = Color(red: 0.10, green: 0.65, blue: 0.40)    // Emerald glow
    let destructive = Color(red: 0.90, green: 0.25, blue: 0.25)
    let success = Color(red: 0.20, green: 0.80, blue: 0.50)
    let warning = Color(red: 0.95, green: 0.75, blue: 0.20)

    // Prayer colors — from dawn blue through to night purple
    let fajrColor = Color(red: 0.25, green: 0.45, blue: 0.75)          // Dawn blue
    let dhuhrColor = Color(red: 0.85, green: 0.68, blue: 0.35)         // Midday gold
    let asrColor = Color(red: 0.75, green: 0.55, blue: 0.25)           // Afternoon amber
    let maghribColor = Color(red: 0.85, green: 0.35, blue: 0.25)       // Sunset red
    let ishaColor = Color(red: 0.35, green: 0.25, blue: 0.55)          // Night indigo
    let sunriseColor = Color(red: 0.95, green: 0.65, blue: 0.25)       // Sunrise orange

    let timerFont = Font.system(size: 42, weight: .ultraLight, design: .monospaced)
    let headingFont = Font.system(size: 20, weight: .semibold)
    let arabicFont = Font.system(size: 14, weight: .medium)
    let labelFont = Font.system(size: 10, weight: .bold)
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelLetterSpacing: CGFloat = 2.0

    let pulseSpeed: Double = 3.0
    let springResponse: Double = 0.6
    let springDamping: Double = 0.65
    let transitionDuration: Double = 0.4

    let transitionSound: String? = "Tink"
    let hapticOnPrayer = true
    let forcedAppearance: String? = "dark"
    let showsGeometricPattern = true
    let patternOpacity: Double = 0.04
}

// MARK: - Midnight Theme
// Deep navy/indigo + silver accents — night sky aesthetic

struct MidnightTheme: AdhanTheme {
    let id = "midnight"
    let displayName = "Midnight"

    let background = Color(red: 0.04, green: 0.04, blue: 0.10)         // Deep navy
    let surface = Color(red: 0.06, green: 0.06, blue: 0.14)
    let surfaceHover = Color(red: 0.08, green: 0.08, blue: 0.18)
    let border = Color(red: 0.20, green: 0.20, blue: 0.40).opacity(0.3)
    let accent = Color(red: 0.55, green: 0.60, blue: 0.85)             // Soft lavender
    let accentSecondary = Color(red: 0.75, green: 0.78, blue: 0.90)    // Silver
    let textPrimary = Color(red: 0.88, green: 0.90, blue: 0.95)        // Cool white
    let textSecondary = Color.white.opacity(0.50)
    let textTertiary = Color.white.opacity(0.22)
    let prayerHighlight = Color(red: 0.55, green: 0.60, blue: 0.85)
    let destructive = Color(red: 0.85, green: 0.30, blue: 0.35)
    let success = Color(red: 0.30, green: 0.75, blue: 0.60)
    let warning = Color(red: 0.90, green: 0.70, blue: 0.25)

    let fajrColor = Color(red: 0.30, green: 0.50, blue: 0.80)
    let dhuhrColor = Color(red: 0.75, green: 0.78, blue: 0.90)
    let asrColor = Color(red: 0.65, green: 0.60, blue: 0.75)
    let maghribColor = Color(red: 0.75, green: 0.40, blue: 0.50)
    let ishaColor = Color(red: 0.45, green: 0.40, blue: 0.70)
    let sunriseColor = Color(red: 0.90, green: 0.70, blue: 0.40)

    let timerFont = Font.system(size: 42, weight: .thin, design: .monospaced)
    let headingFont = Font.system(size: 20, weight: .medium)
    let arabicFont = Font.system(size: 14, weight: .regular)
    let labelFont = Font.system(size: 10, weight: .semibold)
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelLetterSpacing: CGFloat = 1.5

    let pulseSpeed: Double = 4.0
    let springResponse: Double = 0.7
    let springDamping: Double = 0.6
    let transitionDuration: Double = 0.5

    let transitionSound: String? = "Purr"
    let hapticOnPrayer = true
    let forcedAppearance: String? = "dark"
    let showsGeometricPattern = true
    let patternOpacity: Double = 0.03
}

// MARK: - Ramadan Theme
// Deep purple/gold + warm amber — blessed month aesthetic

struct RamadanTheme: AdhanTheme {
    let id = "ramadan"
    let displayName = "Ramadan"

    let background = Color(red: 0.08, green: 0.04, blue: 0.10)         // Deep plum
    let surface = Color(red: 0.12, green: 0.06, blue: 0.14)
    let surfaceHover = Color(red: 0.16, green: 0.08, blue: 0.18)
    let border = Color(red: 0.35, green: 0.20, blue: 0.40).opacity(0.3)
    let accent = Color(red: 0.90, green: 0.72, blue: 0.30)             // Rich gold
    let accentSecondary = Color(red: 0.95, green: 0.85, blue: 0.60)    // Light gold
    let textPrimary = Color(red: 0.95, green: 0.92, blue: 0.88)        // Warm cream
    let textSecondary = Color.white.opacity(0.55)
    let textTertiary = Color.white.opacity(0.25)
    let prayerHighlight = Color(red: 0.90, green: 0.72, blue: 0.30)
    let destructive = Color(red: 0.90, green: 0.30, blue: 0.30)
    let success = Color(red: 0.30, green: 0.80, blue: 0.50)
    let warning = Color(red: 0.95, green: 0.75, blue: 0.20)

    let fajrColor = Color(red: 0.35, green: 0.45, blue: 0.75)
    let dhuhrColor = Color(red: 0.90, green: 0.72, blue: 0.30)
    let asrColor = Color(red: 0.80, green: 0.60, blue: 0.25)
    let maghribColor = Color(red: 0.85, green: 0.40, blue: 0.30)
    let ishaColor = Color(red: 0.50, green: 0.30, blue: 0.60)
    let sunriseColor = Color(red: 0.95, green: 0.70, blue: 0.30)

    let timerFont = Font.system(size: 46, weight: .ultraLight, design: .monospaced)
    let headingFont = Font.system(size: 22, weight: .semibold)
    let arabicFont = Font.system(size: 15, weight: .medium)
    let labelFont = Font.system(size: 9, weight: .bold)
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelLetterSpacing: CGFloat = 3.0

    let pulseSpeed: Double = 3.5
    let springResponse: Double = 0.6
    let springDamping: Double = 0.65
    let transitionDuration: Double = 0.45

    let transitionSound: String? = "Glass"
    let hapticOnPrayer = true
    let forcedAppearance: String? = "dark"
    let showsGeometricPattern = true
    let patternOpacity: Double = 0.05
}
