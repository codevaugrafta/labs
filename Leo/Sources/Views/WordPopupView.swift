import SwiftUI

/// Floating popup showing dictionary entry for a tapped word.
/// Includes: pinyin, definitions, frequency tier, familiarity state, SRS actions.
struct WordPopupView: View {
    let word: String
    let entries: [DictionaryEngine.Entry]
    let familiarityState: FamiliarityState
    let frequencyData: FrequencyEngine.FrequencyData
    let onDismiss: () -> Void
    let onMarkKnown: () -> Void
    let onAddToSRS: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: word + pinyin + frequency badge
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word)
                    .font(.system(size: 28, weight: .medium))

                if let entry = entries.first {
                    Text(entry.pinyinDisplay)
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                }

                Spacer()

                // Frequency badge
                Text(frequencyData.tier.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: frequencyData.tier.color).opacity(0.2))
                    .foregroundStyle(Color(hex: frequencyData.tier.color))
                    .clipShape(Capsule())

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Familiarity + HSK level
            HStack(spacing: 8) {
                Label(familiarityState.label, systemImage: familiarityIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hsk = frequencyData.hskLevel {
                    Text("HSK \(hsk)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            Divider()

            // Definitions
            if entries.isEmpty {
                Text("No definition found")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(Array(entries.prefix(2).enumerated()), id: \.offset) { _, entry in
                    ForEach(Array(entry.definitions.prefix(4).enumerated()), id: \.offset) { idx, def in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(def)
                                .font(.body)
                        }
                    }

                    if entry.traditional != entry.simplified {
                        Text("Trad: \(entry.traditional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                if familiarityState != .known {
                    Button(action: onMarkKnown) {
                        Label("I know this", systemImage: "checkmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }

                if familiarityState < .learning {
                    Button(action: onAddToSRS) {
                        Label("Add to review", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var familiarityIcon: String {
        switch familiarityState {
        case .unknown: "questionmark.circle"
        case .seen: "eye"
        case .learning: "book"
        case .familiar: "star.leadinghalf.filled"
        case .known: "checkmark.seal.fill"
        }
    }
}

// MARK: - Color from hex string

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
