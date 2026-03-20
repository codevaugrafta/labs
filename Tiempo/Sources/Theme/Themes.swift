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

    let springResponse: Double = 0.42
    let springDamping: Double = 0.74
    let transitionDuration: Double = 0.38

    /// System sound names (loaded from `/System/Library/Sounds/*.aiff`).
    let startSound: String? = "Ping"
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

    let springResponse: Double = 0.42
    let springDamping: Double = 0.74
    let transitionDuration: Double = 0.38

    /// System sound names (loaded from `/System/Library/Sounds/*.aiff`).
    let startSound: String? = "Ping"
    let stopSound: String? = "Pop"
    let completeSound: String? = "Hero"

    let forcedAppearance: String? = "dark"
    let usesCustomLayout: Bool = false
}

