import SwiftUI

extension ReadingTheme {
    /// Matches `FoliateReaderView.pushReaderChrome` hex values and web `setTheme`.
    var leoContentBackground: Color {
        switch self {
        case .light:
            Color(red: 251 / 255, green: 251 / 255, blue: 251 / 255)
        case .sepia:
            Color(red: 248 / 255, green: 241 / 255, blue: 227 / 255)
        case .dark:
            Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
        }
    }

    var foliateBackgroundHex: String {
        switch self {
        case .light: "#FBFBFB"
        case .dark: "#121212"
        case .sepia: "#F8F1E3"
        }
    }

    var foliateForegroundHex: String {
        switch self {
        case .light: "#000000"
        case .dark: "#B0B0B0"
        case .sepia: "#2C1F0E"
        }
    }
}
