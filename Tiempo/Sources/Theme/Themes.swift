import SwiftUI

// MARK: - Minimal Zen

struct ZenTheme: TiempoTheme {
    let id = "zen"
    let displayName = "Minimal Zen"

    let background = Color(red: 0.06, green: 0.06, blue: 0.11)
    let surface = Color(red: 0.08, green: 0.08, blue: 0.14)
    let surfaceHover = Color(red: 0.10, green: 0.10, blue: 0.17)
    let border = Color.white.opacity(0.06)
    let accent = Color(red: 0.51, green: 0.55, blue: 0.97)      // Soft indigo
    let accentSecondary = Color(red: 0.29, green: 0.87, blue: 0.60) // Muted green
    let textPrimary = Color.white.opacity(0.9)
    let textSecondary = Color.white.opacity(0.5)
    let textTertiary = Color.white.opacity(0.25)
    let timerText = Color.white.opacity(0.95)
    let destructive = Color(red: 0.95, green: 0.30, blue: 0.30)
    let success = Color(red: 0.29, green: 0.87, blue: 0.60)
    let warning = Color(red: 0.98, green: 0.75, blue: 0.14)

    let timerFont = Font.system(size: 36, weight: .ultraLight, design: .monospaced)
    let headingFont = Font.system(size: 24, weight: .light)
    let labelFont = Font.system(size: 10, weight: .medium)
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelLetterSpacing: CGFloat = 3.0

    let cornerRadius: CGFloat = 12
    let tileCornerRadius: CGFloat = 12
    let tilePadding: CGFloat = 14

    let timerPulseSpeed: Double = 3.0     // Slow breathing
    let springResponse: Double = 0.8
    let springDamping: Double = 0.6
    let transitionDuration: Double = 0.5

    let startSound: String? = "Purr"
    let stopSound: String? = "Tink"
    let completeSound: String? = "Glass"
    let hapticOnStart = true
    let hapticOnStop = true
}

// MARK: - Native macOS Refined

struct NativeTheme: TiempoTheme {
    let id = "native"
    let displayName = "Native macOS"

    let background = Color(.windowBackgroundColor)
    let surface = Color(.controlBackgroundColor)
    let surfaceHover = Color(.selectedContentBackgroundColor).opacity(0.1)
    let border = Color(.separatorColor)
    let accent = Color.accentColor
    let accentSecondary = Color(.systemGreen)
    let textPrimary = Color(.labelColor)
    let textSecondary = Color(.secondaryLabelColor)
    let textTertiary = Color(.tertiaryLabelColor)
    let timerText = Color(.labelColor)
    let destructive = Color(.systemRed)
    let success = Color(.systemGreen)
    let warning = Color(.systemYellow)

    let timerFont = Font.system(size: 28, weight: .medium, design: .monospaced)
    let headingFont = Font.system(size: 22, weight: .bold)
    let labelFont = Font.system(size: 11, weight: .medium)
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelLetterSpacing: CGFloat = 0.5

    let cornerRadius: CGFloat = 8
    let tileCornerRadius: CGFloat = 8
    let tilePadding: CGFloat = 10

    let timerPulseSpeed: Double = 2.0
    let springResponse: Double = 0.5
    let springDamping: Double = 0.75
    let transitionDuration: Double = 0.25

    let startSound: String? = "Tink"
    let stopSound: String? = "Pop"
    let completeSound: String? = "Hero"
    let hapticOnStart = true
    let hapticOnStop = true
}

// MARK: - Warm Luxury

struct WarmLuxuryTheme: TiempoTheme {
    let id = "warm-luxury"
    let displayName = "Warm Luxury"

    let background = Color(red: 0.11, green: 0.10, blue: 0.09)   // #1C1917
    let surface = Color(red: 0.14, green: 0.13, blue: 0.11)
    let surfaceHover = Color(red: 0.17, green: 0.15, blue: 0.13)
    let border = Color(red: 0.85, green: 0.65, blue: 0.37).opacity(0.08) // Gold tint
    let accent = Color(red: 0.85, green: 0.65, blue: 0.37)       // #D9A75F gold
    let accentSecondary = Color(red: 0.96, green: 0.90, blue: 0.82) // #F5E6D0 cream
    let textPrimary = Color(red: 0.96, green: 0.90, blue: 0.82)
    let textSecondary = Color(red: 0.85, green: 0.65, blue: 0.37).opacity(0.6)
    let textTertiary = Color(red: 0.85, green: 0.65, blue: 0.37).opacity(0.3)
    let timerText = Color(red: 0.96, green: 0.90, blue: 0.82)
    let destructive = Color(red: 0.90, green: 0.35, blue: 0.30)
    let success = Color(red: 0.85, green: 0.65, blue: 0.37)
    let warning = Color(red: 0.98, green: 0.80, blue: 0.30)

    let timerFont = Font.system(size: 42, weight: .ultraLight, design: .monospaced)
    let headingFont = Font.system(size: 18, weight: .light, design: .serif)
    let labelFont = Font.system(size: 9, weight: .medium)
    let captionFont = Font.system(size: 12, weight: .regular, design: .serif)
    let labelLetterSpacing: CGFloat = 3.0

    let cornerRadius: CGFloat = 10
    let tileCornerRadius: CGFloat = 8
    let tilePadding: CGFloat = 14

    let timerPulseSpeed: Double = 3.5     // Ultra-slow luxury breathing
    let springResponse: Double = 1.0
    let springDamping: Double = 0.5
    let transitionDuration: Double = 0.6

    let startSound: String? = "Tink"       // Subtle analog click
    let stopSound: String? = "Purr"
    let completeSound: String? = "Glass"
    let hapticOnStart = true
    let hapticOnStop = true
}

// MARK: - Bold Editorial

struct BoldEditorialTheme: TiempoTheme {
    let id = "bold-editorial"
    let displayName = "Bold Editorial"

    let background = Color.black
    let surface = Color(red: 0.067, green: 0.067, blue: 0.067)   // #111
    let surfaceHover = Color(red: 0.1, green: 0.1, blue: 0.1)
    let border = Color(red: 0.13, green: 0.13, blue: 0.13)       // #222
    let accent = Color.white
    let accentSecondary = Color(red: 0.0, green: 1.0, blue: 0.0) // Terminal green
    let textPrimary = Color.white
    let textSecondary = Color(red: 0.53, green: 0.53, blue: 0.53)
    let textTertiary = Color(red: 0.27, green: 0.27, blue: 0.27)
    let timerText = Color.white
    let destructive = Color.white           // White STOP on black
    let success = Color(red: 0.0, green: 1.0, blue: 0.0)
    let warning = Color(red: 0.92, green: 0.72, blue: 0.03)

    let timerFont = Font.system(size: 56, weight: .thin, design: .monospaced)
    let headingFont = Font.system(size: 24, weight: .black)
    let labelFont = Font.system(size: 9, weight: .heavy)
    let captionFont = Font.system(size: 12, weight: .medium)
    let labelLetterSpacing: CGFloat = 3.0

    let cornerRadius: CGFloat = 0          // Sharp edges
    let tileCornerRadius: CGFloat = 0
    let tilePadding: CGFloat = 12

    let timerPulseSpeed: Double = 1.0      // Fast, precise
    let springResponse: Double = 0.25
    let springDamping: Double = 0.9        // Snappy, minimal bounce
    let transitionDuration: Double = 0.1   // Instant feel

    let startSound: String? = "Tink"       // Mechanical click
    let stopSound: String? = "Pop"
    let completeSound: String? = "Morse"
    let hapticOnStart = true
    let hapticOnStop = true
}
