import SwiftUI
import SwiftData

/// SRS review interface — shows due cards and handles rating.
struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dueCards: [FSRSCard] = []
    @State private var isShowingBack = false
    @State private var cardRotation: Double = 0
    @State private var sessionComplete = false
    @State private var reviewedCount = 0
    @State private var sessionTargetCount = 0

    var body: some View {
        VStack(spacing: 0) {
            if sessionComplete || dueCards.isEmpty {
                reviewCompleteView
            } else {
                cardView
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: sessionComplete)
        .accessibilityIdentifier("leo.review.root")
        .frame(minWidth: 500, minHeight: 400)
        .task {
            loadDueCards()
        }
    }

    // MARK: - Card View

    private var cardView: some View {
        let card = dueCards[0]
        let entries = DictionaryEngine.shared.lookup(card.word)
        let freq = FrequencyEngine.shared.lookup(card.word)
        let remainingCount = dueCards.count
        let progressTotal = max(sessionTargetCount, 1)

        return VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Session")
                            .font(.headline)
                        Text("\(remainingCount) due now")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(reviewedCount) reviewed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(reviewedCount), total: Double(progressTotal))
                    .accessibilityIdentifier("leo.review.progress")

                HStack {
                    Text("Card \(reviewedCount + 1) of \(sessionTargetCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Reviews \(card.reviewCount) · Lapses \(card.lapseCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)

            Spacer()

            // MARK: Flippable card content
            VStack(spacing: 24) {
                // Card front — sentence context or bare word (always visible)
                if let sentence = card.contextSentence, !sentence.isEmpty {
                    Text(highlightedSentence(sentence: sentence, word: card.word))
                        .font(.system(size: 20, weight: .regular))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.horizontal)
                } else {
                    Text(card.word)
                        .font(.system(size: 48, weight: .medium))
                }

                if isShowingBack {
                    // Word (always shown on the answer side when context was the cue)
                    if card.contextSentence != nil {
                        Text(card.word)
                            .font(.system(size: 36, weight: .bold))
                            .padding(.top, 4)
                    }

                    // Pinyin
                    if let entry = entries.first {
                        Text(entry.pinyinDisplay)
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }

                    // Frequency
                    HStack(spacing: 8) {
                        Text("Frequency")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(freq.tier.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: freq.tier.color).opacity(0.2))
                            .foregroundStyle(Color(hex: freq.tier.color))
                            .clipShape(Capsule())
                    }

                    // Contextual definition (AI-generated)
                    if let contextDef = card.contextualDefinition {
                        Text(contextDef)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.blue)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                            .padding(.horizontal)
                    }

                    // Book sentence — context the word was encountered in
                    if let sentence = card.contextSentence, !sentence.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("From book:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(highlightedSentence(sentence: sentence, word: card.word, size: 15))
                                .font(.system(size: 15))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                        .padding(.horizontal)
                    }

                    // Lemma example sentence (AI-generated) — word highlighted for visual anchoring
                    if let example = card.lemmaExampleSentence, !example.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Example:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(highlightedSentence(sentence: example, word: card.word, size: 15))
                                .font(.system(size: 15))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                        .padding(.horizontal)
                    }

                    // Definitions
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(entries.prefix(2).enumerated()), id: \.offset) { _, entry in
                            ForEach(Array(entry.definitions.prefix(3).enumerated()), id: \.offset) { idx, def in
                                Text("\(idx + 1). \(def)")
                                    .font(.body)
                            }
                        }
                    }
                    .frame(maxWidth: 400, alignment: .leading)
                    .padding()

                    Spacer()

                    Text("Rate with 1, 2, 3, or 4")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Rating buttons
                    HStack(spacing: 16) {
                        RatingButton(label: "Again", color: .red, rating: .again, keyHint: "1", keyEquivalent: "1") { rate(.again) }
                        RatingButton(label: "Hard", color: .orange, rating: .hard, keyHint: "2", keyEquivalent: "2") { rate(.hard) }
                        RatingButton(label: "Good", color: .green, rating: .good, keyHint: "3", keyEquivalent: "3") { rate(.good) }
                        RatingButton(label: "Easy", color: .blue, rating: .easy, keyHint: "4", keyEquivalent: "4") { rate(.easy) }
                    }
                    .padding(.bottom, 24)
                } else {
                    Spacer()

                    VStack(spacing: 8) {
                        Button("Show Answer") {
                            withAnimation(.easeIn(duration: 0.15)) {
                                cardRotation = 90
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isShowingBack = true
                                LeoHaptics.tick()
                                withAnimation(.easeOut(duration: 0.15)) {
                                    cardRotation = 0
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.space, modifiers: [])
                        .accessibilityLabel("Show Answer")
                        .accessibilityValue("Shortcut Space")
                        .accessibilityIdentifier("leo.review.showAnswer")

                        Text("Press Space to reveal the answer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 24)
                }
            }
            .rotation3DEffect(.degrees(cardRotation), axis: (x: 0, y: 1, z: 0))
        }
        .padding()
        .accessibilityIdentifier("leo.review.root")
        .accessibilityElement(children: .contain)
    }

    /// Returns an `AttributedString` with ALL occurrences of `word` bolded and tinted in accent
    /// color within `sentence`. `size` controls the bold font size (default 20 for the card front,
    /// pass the parent text size for answer sections to avoid mismatched rendering).
    private func highlightedSentence(sentence: String, word: String, size: CGFloat = 20) -> AttributedString {
        var attributed = AttributedString(sentence)
        guard !word.isEmpty else { return attributed }

        var searchStart = sentence.startIndex
        while searchStart < sentence.endIndex,
              let range = sentence.range(of: word, range: searchStart..<sentence.endIndex) {
            if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
               let attrEnd = AttributedString.Index(range.upperBound, within: attributed),
               attrStart < attrEnd {
                attributed[attrStart..<attrEnd].font = .system(size: size, weight: .bold)
                attributed[attrStart..<attrEnd].foregroundColor = .accentColor
            }
            searchStart = range.upperBound
        }

        return attributed
    }

    // MARK: - Review Complete

    private var reviewCompleteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: sessionComplete)
                .padding(.bottom, 4)
            Text("All caught up!")
                .font(.title2.weight(.semibold))
            if reviewedCount > 0 {
                Text("Reviewed \(reviewedCount) card\(reviewedCount == 1 ? "" : "s") this session.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No cards due for review.")
                    .foregroundStyle(.secondary)
            }
            Text("Leo will bring the next due cards back here automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Refresh") {
                loadDueCards()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .accessibilityIdentifier("leo.review.complete")
        .accessibilityElement(children: .contain)
    }

    // MARK: - Actions

    private func rate(_ rating: Rating) {
        let fsrs = FSRSEngine(modelContext: modelContext)
        let card = dueCards[0]
        fsrs.review(card: card, rating: rating)

        reviewedCount += 1
        isShowingBack = false
        cardRotation = 0
        loadDueCards(preservingSessionCounts: true)
    }

    private func loadDueCards(preservingSessionCounts: Bool = false) {
        let fsrs = FSRSEngine(modelContext: modelContext)
        dueCards = fsrs.dueCards()
        isShowingBack = false
        sessionComplete = dueCards.isEmpty

        if preservingSessionCounts {
            sessionComplete = dueCards.isEmpty
            sessionTargetCount = max(sessionTargetCount, reviewedCount + dueCards.count)
        } else {
            reviewedCount = 0
            sessionTargetCount = dueCards.count
        }
    }
}

// MARK: - Rating Button

private struct RatingButton: View {
    let label: String
    let color: Color
    let rating: Rating
    let keyHint: String
    let keyEquivalent: KeyEquivalent
    let onRate: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(duration: 0.12, bounce: 0)) { isPressed = true }
            LeoHaptics.tick()
            onRate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(duration: 0.2)) { isPressed = false }
            }
        }) {
            VStack(spacing: 2) {
                Text(label)
                Text(keyHint)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(isPressed ? 0.18 : 0))
            )
        }
        .buttonStyle(.bordered)
        .tint(color)
        .keyboardShortcut(keyEquivalent, modifiers: [])
        .accessibilityLabel(label)
        .accessibilityIdentifier("leo.review.rate.\(label.lowercased())")
    }
}
