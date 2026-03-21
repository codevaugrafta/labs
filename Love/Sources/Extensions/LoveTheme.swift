import AppKit
import SwiftUI

/// Shared visual language: warm accent, editorial type, calm depth.
enum LoveTheme {
    /// Primary rose.
    static let accent = Color(red: 0.82, green: 0.38, blue: 0.44)
    /// Soft wash for chips and focus.
    static let accentMuted = Color(red: 0.82, green: 0.38, blue: 0.44).opacity(0.16)
    /// Secondary warmth for gradients and highlights (not UI chrome).
    static let warmth = Color(red: 0.95, green: 0.72, blue: 0.55)

    static let contentGutter: CGFloat = 24
    static let cardCorner: CGFloat = 16
    static let controlCorner: CGFloat = 12
}

enum LoveTypography {
    static let brandTitle = Font.system(size: 26, weight: .semibold, design: .serif)
    static let brandTagline = Font.system(.caption, design: .default).weight(.medium)
    static let panelTitle = Font.system(.title3, design: .serif).weight(.semibold)
    static let sheetTitle = Font.system(.title2, design: .serif).weight(.semibold)
    static let sectionHeader = Font.system(.subheadline, design: .serif).weight(.semibold)
    static let mustDoTitle = Font.system(.body, design: .default).weight(.medium)
    static let mustDoTitleFocus = Font.system(.body, design: .default).weight(.semibold)
}

struct LoveWindowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.09, green: 0.07, blue: 0.10), location: 0),
                            .init(color: Color(red: 0.05, green: 0.04, blue: 0.07), location: 0.45),
                            .init(color: Color(red: 0.11, green: 0.06, blue: 0.09), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [
                            LoveTheme.warmth.opacity(0.07),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 40,
                        endRadius: 420
                    )
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor),
                        Color(nsColor: .windowBackgroundColor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct LoveComposerChrome: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: LoveTheme.cardCorner, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: LoveTheme.cardCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                LoveTheme.accent.opacity(colorScheme == .dark ? 0.42 : 0.28),
                                Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09),
                                LoveTheme.warmth.opacity(colorScheme == .dark ? 0.12 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 24, y: 10)
            .shadow(color: LoveTheme.accent.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 20, y: 6)
    }
}

/// Segmented control on a soft material rail.
struct LoveTabRail<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
            }
            .padding(.horizontal, LoveTheme.contentGutter)
            .padding(.vertical, 4)
    }
}

/// Decorative accent rule for panel headers.
struct LoveAccentRule: View {
    var width: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [LoveTheme.accent, LoveTheme.warmth.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 4)
            .accessibilityHidden(true)
    }
}
