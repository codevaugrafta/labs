import SwiftUI

// MARK: - Standard (Light) — current working theme, system colors

struct StandardTheme: TiempoTheme {
    let id = "standard"
    let displayName = "Standard"

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

    let startSound: String? = "Tink"
    let stopSound: String? = "Pop"
    let completeSound: String? = "Hero"

    /// Standard uses system appearance — no forced dark/light
    let forcedAppearance: String? = nil
    /// Standard uses TabView (not custom sidebar)
    let usesCustomLayout: Bool = false
}

// MARK: - Standard Dark — same as Standard but forces dark appearance

struct StandardDarkTheme: TiempoTheme {
    let id = "standard-dark"
    let displayName = "Standard Dark"

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

    let startSound: String? = "Tink"
    let stopSound: String? = "Pop"
    let completeSound: String? = "Hero"

    let forcedAppearance: String? = "dark"
    let usesCustomLayout: Bool = false
}

// MARK: - Tiempo Signature — fully custom, exploits full SwiftUI power

struct SignatureTheme: TiempoTheme {
    let id = "signature"
    let displayName = "Tiempo Signature"

    // Warm dark charcoal base with gold accents (Warm Luxury DNA)
    let background = Color(red: 0.09, green: 0.09, blue: 0.10)      // #171718
    let surface = Color(red: 0.12, green: 0.12, blue: 0.13)          // #1F1F21
    let surfaceHover = Color(red: 0.15, green: 0.15, blue: 0.16)     // #262628
    let border = Color.white.opacity(0.06)
    let accent = Color(red: 0.85, green: 0.65, blue: 0.37)           // #D9A75F gold
    let accentSecondary = Color(red: 0.96, green: 0.90, blue: 0.82)  // #F5E6D0 cream
    let textPrimary = Color(red: 0.93, green: 0.91, blue: 0.88)      // Warm white
    let textSecondary = Color.white.opacity(0.50)
    let textTertiary = Color.white.opacity(0.25)
    let timerText = Color(red: 0.96, green: 0.90, blue: 0.82)        // Cream timer
    let destructive = Color(red: 0.95, green: 0.30, blue: 0.30)
    let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    let warning = Color(red: 0.98, green: 0.75, blue: 0.14)

    // Bold Editorial DNA: large monospaced timer, heavy labels
    let timerFont = Font.system(size: 48, weight: .ultraLight, design: .monospaced)
    let headingFont = Font.system(size: 20, weight: .semibold)
    let labelFont = Font.system(size: 9, weight: .bold)
    let captionFont = Font.system(size: 12, weight: .regular)
    let labelLetterSpacing: CGFloat = 3.0

    // Native macOS Refined DNA: clean rounded corners
    let cornerRadius: CGFloat = 10
    let tileCornerRadius: CGFloat = 10
    let tilePadding: CGFloat = 14

    // Organic Natural DNA: slow breathing, bouncy springs
    let timerPulseSpeed: Double = 3.0
    let springResponse: Double = 0.7
    let springDamping: Double = 0.6
    let transitionDuration: Double = 0.5

    let startSound: String? = "Tink"
    let stopSound: String? = "Purr"
    let completeSound: String? = "Glass"
    let hapticOnStart = true
    let hapticOnStop = true

    let forcedAppearance: String? = "dark"
    /// Signature uses custom sidebar layout instead of TabView
    let usesCustomLayout: Bool = true
}
