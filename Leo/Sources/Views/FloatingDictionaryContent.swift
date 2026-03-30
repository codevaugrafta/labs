import SwiftUI
import AppKit

// MARK: - View model

/// Data model passed into the floating panel for a single word lookup.
struct DictionaryLookupData: Sendable {
    let word: String
    let pinyin: String           // Empty string when user has pinyin disabled
    let definitions: [String]
    let hskLevel: Int?
    let grammarTitle: String?    // e.g. "A2 · 不得不 structure"
    let grammarLevel: String?
    let familiarity: FamiliarityState
    let alreadyInReview: Bool
    let components: [String]?    // Direct Unicode components; nil for multi-char words
    let radical: String?         // Kangxi radical character; nil for multi-char words
    /// AI-generated contextual gloss for the word in the sentence it was tapped. Set asynchronously when OpenRouter responds.
    var contextualGloss: String?
}

// MARK: - Content view

/// SwiftUI content hosted inside FloatingDictionaryPanel.
/// Design: macOS Dictionary.app — solid background, clean typography, native feel.
struct FloatingDictionaryContent: View {

    let data: DictionaryLookupData
    let onKnow: () -> Void
    let onReview: () -> Void
    let onListen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header — word + pinyin + HSK badge
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(data.word)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                if !data.pinyin.isEmpty {
                    Text(data.pinyin)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let hsk = data.hskLevel {
                    HSKBadge(level: hsk)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)

            // MARK: Contextual gloss (AI-generated, shown first when available)
            if let gloss = data.contextualGloss {
                Text(gloss)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.horizontal, 18)
            }

            // MARK: Definitions
            Group {
                if data.definitions.count == 1 {
                    Text(data.definitions[0])
                        .font(.system(size: 14))
                        .foregroundStyle(data.contextualGloss != nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(data.definitions.prefix(5).enumerated()), id: \.offset) { idx, def in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16, alignment: .trailing)
                                Text(def)
                                    .font(.system(size: 13))
                                    .foregroundStyle(data.contextualGloss != nil ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.top, data.contextualGloss != nil ? 4 : 8)
            .padding(.horizontal, 18)

            // MARK: Components (single-char only)
            if let components = data.components, !components.isEmpty {
                HStack(spacing: 4) {
                    Text("Components: \(components.joined(separator: " · "))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let radical = data.radical {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("Radical: \(radical)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 18)
            }

            // MARK: Grammar note
            if let grammarTitle = data.grammarTitle,
               let grammarLevel = data.grammarLevel {
                HStack(spacing: 4) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("\(grammarLevel) · \(grammarTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 6)
                .padding(.horizontal, 18)
            }

            // MARK: Familiarity
            FamiliarityPill(state: data.familiarity)
                .padding(.top, 6)
                .padding(.horizontal, 18)

            Divider()
                .padding(.top, 10)
                .padding(.horizontal, 14)

            // MARK: Actions
            HStack(spacing: 10) {
                if data.familiarity != .known {
                    ActionButton(label: "Know", icon: "checkmark", tint: .green, action: onKnow)
                }

                if !data.alreadyInReview {
                    ActionButton(label: "Review", icon: "arrow.clockwise", tint: .blue, action: onReview)
                } else {
                    Text("In review")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onListen) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Listen")
            }
            .padding(.top, 8)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Sub-components

private struct HSKBadge: View {
    let level: Int

    var body: some View {
        Text("HSK \(level)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor, in: Capsule())
    }

    private var badgeColor: Color {
        switch level {
        case 1...3: .green
        case 4...6: .blue
        default:    .purple
        }
    }
}

private struct FamiliarityPill: View {
    let state: FamiliarityState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var stateColor: Color {
        switch state {
        case .unknown:  .red
        case .seen:     .orange
        case .learning: .yellow
        case .familiar: .gray
        case .known:    .green
        }
    }
}

private struct ActionButton: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
