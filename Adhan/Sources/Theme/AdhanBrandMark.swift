import SwiftUI

/// In-app logo mark: crescent + eight-point star on a soft radial glow.
/// The Dock icon remains `AppIcon.icns`; this elevates the main window identity.
struct AdhanBrandMark: View {
    @Bindable private var themeManager = AdhanThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    var size: CGFloat = 44
    @State private var appeared = false
    @State private var glowPhase: CGFloat = 0

    private var moonSize: CGFloat { size * 0.64 }
    private var starSize: CGFloat { size * 0.22 }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            themeManager.accent.opacity(0.45),
                            themeManager.accentSecondary.opacity(0.18),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.85
                    )
                )
                .scaleEffect(1.0 + glowPhase * 0.06)
                .opacity(0.85 + glowPhase * 0.15)

            CrescentMoon(phase: 0.32)
                .fill(
                    LinearGradient(
                        colors: [themeManager.accent, themeManager.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: moonSize, height: moonSize)
                .rotationEffect(.degrees(appeared ? 0 : -10))
                .scaleEffect(appeared ? 1 : 0.82)
                .shadow(color: themeManager.accent.opacity(0.35), radius: appeared ? 8 : 2, y: 2)

            EightPointStar()
                .fill(themeManager.accentSecondary.opacity(0.95))
                .frame(width: starSize, height: starSize)
                .offset(x: size * 0.34, y: -size * 0.34)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Adhan")
        .accessibilityAddTraits(.isImage)
        .onAppear {
            if accessibilityReduceMotion {
                appeared = true
                glowPhase = 0.5
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    appeared = true
                }
                withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                    glowPhase = 1
                }
            }
        }
    }
}

/// Title row beside the mark — reads well in light and dark Aqua.
struct AdhanBrandHeader: View {
    var markSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AdhanBrandMark(size: markSize)

            VStack(alignment: .leading, spacing: 3) {
                Text("Adhan")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Prayer Times")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 14)
    }
}
