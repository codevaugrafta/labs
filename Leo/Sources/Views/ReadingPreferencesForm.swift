import SwiftUI

/// Apple Books-style reading preferences popover (themes, font size, layout, toggles).
struct ReadingPreferencesForm: View {
    @Binding var theme: ReadingTheme
    @Binding var fontSize: Double
    /// Reserved for future reading-form controls (also held in Settings).
    @Binding var lineHeight: Double
    @Binding var textDirection: String
    @Binding var showHighlights: Bool
    @Binding var pageStyle: String
    @Binding var spreadMode: String
    /// When set (reader popover), shows a control to open the full Settings window.
    var onOpenFullSettings: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            Text("Themes & settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(-0.2)
                .frame(maxWidth: .infinity)

            // MARK: Section 1 — Theme cards
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Theme")

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ThemeCard(
                        name: "Light",
                        bg: Color(red: 0.984, green: 0.984, blue: 0.984),
                        fg: .black,
                        isSelected: theme == .light
                    ) {
                        theme = .light
                    }
                    ThemeCard(
                        name: "Sepia",
                        bg: Color(red: 0.973, green: 0.945, blue: 0.890),
                        fg: Color(red: 0.173, green: 0.122, blue: 0.055),
                        isSelected: theme == .sepia
                    ) {
                        theme = .sepia
                    }
                    ThemeCard(
                        name: "Dark",
                        bg: Color(red: 0.071, green: 0.071, blue: 0.071),
                        fg: Color(red: 0.69, green: 0.69, blue: 0.69),
                        isSelected: theme == .dark
                    ) {
                        theme = .dark
                    }
                }
                .accessibilityIdentifier("leo.readingPrefs.themeGrid")
            }

            Divider().opacity(0.35)

            // MARK: Section 2 — Font size
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Font size")

                HStack(spacing: 0) {
                    Button {
                        fontSize = max(14, fontSize - 1)
                    } label: {
                        Text("A")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("leo.readingPrefs.fontSizeDown")

                    Spacer()

                    Text("\(Int(fontSize))pt")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Button {
                        fontSize = min(28, fontSize + 1)
                    } label: {
                        Text("A")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("leo.readingPrefs.fontSizeUp")
                }
                .padding(.horizontal, 6)
            }

            Divider().opacity(0.35)

            // MARK: Section 3 — Layout (spread mode)
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Page layout")

                HStack(spacing: 10) {
                    LayoutModeButton(
                        title: "Single",
                        subtitle: "One column",
                        systemImage: "doc.plaintext",
                        isSelected: spreadMode == "none"
                    ) {
                        spreadMode = "none"
                    }
                    .accessibilityIdentifier("leo.readingPrefs.layoutSingle")

                    LayoutModeButton(
                        title: "Two pages",
                        subtitle: "Two columns",
                        systemImage: "book.pages",
                        isSelected: spreadMode == "both"
                    ) {
                        spreadMode = "both"
                    }
                    .accessibilityIdentifier("leo.readingPrefs.layoutSpread")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("leo.readingPrefs.spreadMode")
                .onAppear {
                    if spreadMode == "auto" { spreadMode = "both" }
                }
            }

            Divider().opacity(0.35)

            // MARK: Section 4 — Toggles
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show familiarity highlights", isOn: $showHighlights)
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("leo.readingPrefs.showHighlights")
            }

            if let onOpenFullSettings {
                Divider().opacity(0.35)
                Button(action: onOpenFullSettings) {
                    Label("Customise…", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("leo.readingPrefs.customise")
            }
        }
        .padding(18)
        .frame(width: 300)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityIdentifier("leo.readingPrefs.form")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.75)
    }
}

// MARK: - Layout mode control

private struct LayoutModeButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ThemeCard

private struct ThemeCard: View {
    let name: String
    let bg: Color
    let fg: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(bg)
                    .frame(height: 50)
                    .overlay {
                        Text("Aa")
                            .font(.system(size: 20, weight: .medium, design: .serif))
                            .foregroundStyle(fg)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
