import SwiftUI

/// Apple Books-style reading preferences popover (themes, font size, layout, toggles).
struct ReadingPreferencesForm: View {
    @Binding var theme: ReadingTheme
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var textDirection: String
    @Binding var showPinyin: Bool
    @Binding var showHighlights: Bool
    @Binding var pageStyle: String
    @Binding var spreadMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: Section 1 — Theme cards
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

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

            Divider()

            // MARK: Section 2 — Font size
            VStack(alignment: .leading, spacing: 10) {
                Text("Font Size")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 0) {
                    Button {
                        fontSize = max(14, fontSize - 1)
                    } label: {
                        Text("A")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("leo.readingPrefs.fontSizeDown")

                    Spacer()

                    Text("\(Int(fontSize))pt")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Button {
                        fontSize = min(28, fontSize + 1)
                    } label: {
                        Text("A")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("leo.readingPrefs.fontSizeUp")
                }
                .padding(.horizontal, 4)
            }

            Divider()

            // MARK: Section 3 — Layout (spread mode)
            VStack(alignment: .leading, spacing: 10) {
                Text("Layout")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("", selection: $spreadMode) {
                    Text("Single page").tag("none")
                    Text("Two pages").tag("auto")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("leo.readingPrefs.spreadMode")
            }

            Divider()

            // MARK: Section 4 — Toggles
            VStack(spacing: 4) {
                Toggle("Show pinyin in lookup", isOn: $showPinyin)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("leo.readingPrefs.showPinyin")
                Toggle("Show familiarity highlights", isOn: $showHighlights)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("leo.readingPrefs.showHighlights")
            }
        }
        .padding(16)
        .frame(width: 280)
        .accessibilityIdentifier("leo.readingPrefs.form")
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
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
