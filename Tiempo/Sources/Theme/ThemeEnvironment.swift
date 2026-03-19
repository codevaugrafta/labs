import SwiftUI

// MARK: - Theme accessor for views

/// Views should use `@Environment(ThemeManager.self) var theme` when possible.
/// For non-environment contexts (menu bar, floating panel), use ThemeManager.shared directly.
///
/// TiempoStyle.current is kept as a convenience for code that can't use @Environment
/// (e.g., computed properties, non-View code). It reads from the shared singleton.
enum TiempoStyle {
    @MainActor
    static var current: any TiempoTheme {
        ThemeManager.shared.current
    }
}

// MARK: - Themed background modifier

struct ThemedBackground: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.background)
    }
}

extension View {
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}
