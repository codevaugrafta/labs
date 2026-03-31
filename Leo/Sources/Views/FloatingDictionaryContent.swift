import SwiftUI
import AppKit

// MARK: - View model

/// Data model passed into the floating panel for a single word lookup.
struct DictionaryLookupData: Sendable {
    let word: String
    /// Tone-marked pinyin — always shown when present.
    let pinyin: String
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
    /// True while the OpenRouter contextual gloss request is in flight.
    var isLoadingGloss: Bool = false
    /// The full sentence (between nearest Chinese punctuation) in which the word was tapped.
    let contextSentence: String?
}

// MARK: - Content view

/// SwiftUI content hosted inside FloatingDictionaryPanel.
/// Design: clean, minimal, no colored state indicators — pure typography + subtle chrome.
struct FloatingDictionaryContent: View {

    let data: DictionaryLookupData
    let onReview: () -> Void
    let onListen: () -> Void
    let onDismiss: () -> Void
    let onFamiliarityChange: (FamiliarityState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header — lemma, pinyin, HSK badge, familiarity dots
            HStack(alignment: .top, spacing: 10) {

                // Left column: word + pinyin
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.word)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .kerning(0)

                    if !data.pinyin.isEmpty {
                        Text(data.pinyin)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .kerning(0)
                    }
                }

                Spacer(minLength: 6)

                // Right column: HSK badge + familiarity dots
                VStack(alignment: .trailing, spacing: 6) {
                    if let hsk = data.hskLevel {
                        SubtleHSKBadge(level: hsk)
                    }
                    FamiliarityDots(
                        current: data.familiarity,
                        onChange: onFamiliarityChange
                    )
                }
                .padding(.top, 2)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)

            // MARK: Context sentence
            if let sentence = data.contextSentence, !sentence.isEmpty {
                Text(attributedSentence(sentence: sentence, word: data.word))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
            }

            // MARK: Contextual gloss (AI-generated, shown first when available)
            if let gloss = data.contextualGloss {
                Text(gloss)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            } else if data.isLoadingGloss {
                HStack(spacing: 5) {
                    ProgressView().scaleEffect(0.6)
                    Text("Thinking…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }

            // MARK: Definitions
            Group {
                if data.definitions.count == 1 {
                    Text(data.definitions[0])
                        .font(.system(size: 13))
                        .foregroundStyle(data.contextualGloss != nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(data.definitions.prefix(5).enumerated()), id: \.offset) { idx, def in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14, alignment: .trailing)
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
            .padding(.horizontal, 16)

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
                .padding(.horizontal, 16)
            }

            // MARK: Grammar note
            if let grammarTitle = data.grammarTitle,
               let grammarLevel = data.grammarLevel {
                HStack(spacing: 4) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("\(grammarLevel) · \(grammarTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 6)
                .padding(.horizontal, 16)
            }

            Divider()
                .padding(.top, 10)
                .padding(.horizontal, 12)

            // MARK: Actions
            HStack(spacing: 8) {
                // Track button — promotes word into active tracking (learning state)
                if data.familiarity == .unknown || data.familiarity == .seen {
                    CleanActionButton(label: "Track", icon: "bookmark", disabled: false, action: {
                        LeoHaptics.tick()
                        onFamiliarityChange(.learning)
                    })
                } else {
                    CleanActionButton(label: "Tracked", icon: "bookmark.fill", disabled: false, accentColor: Color.purple, action: {})
                }

                if data.alreadyInReview {
                    CleanActionButton(label: "In SRS", icon: "checkmark", disabled: true, action: {})
                } else {
                    CleanActionButton(label: "Add to SRS", icon: "square.stack", disabled: false, action: {
                        LeoHaptics.tick()
                        onReview()
                    })
                }

                Spacer()

                Button(action: onListen) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Listen")
                .accessibilityLabel("Listen")
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            dictionaryPanelBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Panel Background

    /// Liquid Glass on macOS 26; ultraThinMaterial fallback on earlier versions.
    @ViewBuilder
    private var dictionaryPanelBackground: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Attributed sentence helper

/// Returns an `AttributedString` with `word` rendered semibold + `.primary` within `sentence`.
private func attributedSentence(sentence: String, word: String) -> AttributedString {
    var result = AttributedString(sentence)

    var searchRange = sentence.startIndex..<sentence.endIndex
    while let range = sentence.range(of: word, options: .literal, range: searchRange) {
        if let attrRange = Range(range, in: result) {
            result[attrRange].font = .system(size: 12, weight: .semibold)
            result[attrRange].foregroundColor = .primary
        }
        searchRange = range.upperBound..<sentence.endIndex
    }

    return result
}

// MARK: - Sub-components

/// 5 small dot indicators representing familiarity states.
/// Active dot = filled `.secondary`; inactive = stroked `.quaternary`.
/// Each dot is individually tappable.
private struct FamiliarityDots: View {
    let current: FamiliarityState
    let onChange: (FamiliarityState) -> Void

    private let dotSize: CGFloat = 11
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(FamiliarityState.allCases, id: \.self) { state in
                Button(action: { onChange(state) }) {
                    Circle()
                        .fill(current == state ? stateColor(state) : Color.clear)
                        .overlay(
                            Circle().strokeBorder(
                                current == state ? Color.clear : stateColor(state).opacity(0.5),
                                lineWidth: 1
                            )
                        )
                        .frame(width: dotSize, height: dotSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.label)
                .accessibilityIdentifier("leo.lookup.familiarity.\(state.rawValue)")
            }
        }
    }

    private func stateColor(_ state: FamiliarityState) -> Color {
        switch state {
        case .unknown:  .secondary
        case .seen:     .orange
        case .learning: Color(red: 0.58, green: 0.20, blue: 0.92) // purple
        case .familiar: .blue
        case .known:    .green
        }
    }
}

/// Gray-stroked HSK badge — no color fill.
private struct SubtleHSKBadge: View {
    let level: Int

    var body: some View {
        Text("HSK \(level)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5)
            )
    }
}

/// Bordered action button — rounded rect outline, no filled background.
/// Pass `disabled: true` for a non-interactive confirmation state (e.g. "In SRS").
/// Pass `accentColor` to tint the foreground and border (e.g. the "Tracked" state).
private struct CleanActionButton: View {
    let label: String
    let icon: String
    let disabled: Bool
    var accentColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(
                accentColor.map { AnyShapeStyle($0) }
                    ?? (disabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(accentColor.map { AnyShapeStyle($0.opacity(0.08)) } ?? AnyShapeStyle(.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        accentColor.map { $0.opacity(0.5) } ?? Color.secondary.opacity(0.4),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(LeoPressButtonStyle())
        .disabled(disabled)
    }
}
