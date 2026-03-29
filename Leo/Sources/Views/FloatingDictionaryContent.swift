import SwiftUI
import AppKit

// MARK: - View model

/// Data model passed into the floating panel for a single word lookup.
struct DictionaryLookupData: Sendable {
    let word: String
    let pinyin: String           // Empty string when user has pinyin disabled
    let primaryDefinition: String
    let hskLevel: Int?
    let grammarTitle: String?    // e.g. "A2 · 不得不 structure"
    let grammarLevel: String?
    let familiarity: FamiliarityState
    let alreadyInReview: Bool
}

// MARK: - Content view

/// SwiftUI content hosted inside FloatingDictionaryPanel.
/// Design: macOS Dictionary.app feel — compact, native, non-intrusive.
struct FloatingDictionaryContent: View {

    let data: DictionaryLookupData
    let onKnow: () -> Void
    let onReview: () -> Void
    let onListen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VisualEffectBackground()

            VStack(alignment: .leading, spacing: 0) {
                // MARK: Header row — word + HSK badge
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(data.word)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    if !data.pinyin.isEmpty {
                        Text(data.pinyin)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(hex: "#f97316")) // orange-500
                    }

                    Spacer()

                    if let hsk = data.hskLevel {
                        HSKBadge(level: hsk)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 16)

                Divider()
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                // MARK: Primary definition
                Text(data.primaryDefinition)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                // MARK: Grammar note
                if let grammarTitle = data.grammarTitle,
                   let grammarLevel = data.grammarLevel {
                    HStack(spacing: 4) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(grammarLevel) · \(grammarTitle)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 7)
                    .padding(.horizontal, 16)
                }

                // MARK: Familiarity indicator
                FamiliarityPill(state: data.familiarity)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                // MARK: Action buttons
                HStack(spacing: 8) {
                    if data.familiarity != .known {
                        ActionButton(
                            label: "Know",
                            icon: "checkmark.circle.fill",
                            color: Color(hex: "#22c55e"),
                            action: onKnow
                        )
                    }

                    if !data.alreadyInReview {
                        ActionButton(
                            label: "Review",
                            icon: "arrow.clockwise.circle.fill",
                            color: Color(hex: "#3b82f6"),
                            action: onReview
                        )
                    } else {
                        Text("In review")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    Button(action: onListen) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Listen")
                    .help("Listen to pronunciation")
                }
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
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
        case 1...3: Color(hex: "#22c55e")  // green — foundational
        case 4...6: Color(hex: "#3b82f6")  // blue — intermediate
        default:    Color(hex: "#8b5cf6")  // purple — advanced
        }
    }
}

private struct FamiliarityPill: View {
    let state: FamiliarityState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(state.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var stateColor: Color {
        switch state {
        case .unknown:  Color(hex: "#ef4444")
        case .seen:     Color(hex: "#f97316")
        case .learning: Color(hex: "#eab308")
        case .familiar: Color(hex: "#6b7280")
        case .known:    Color(hex: "#22c55e")
        }
    }
}

private struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NSVisualEffectView wrapper

/// Wraps NSVisualEffectView with `.hudWindow` material for a native glassmorphism background.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
