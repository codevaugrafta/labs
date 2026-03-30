import SwiftUI
import SwiftData

/// SRS review interface — shows due cards and handles rating.
struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dueCards: [FSRSCard] = []
    @State private var showAnswer = false
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

            // MARK: Card front — sentence context or bare word
            if let sentence = card.contextSentence, !sentence.isEmpty {
                // Show the sentence with the target word highlighted as the recall cue
                Text(highlightedSentence(sentence: sentence, word: card.word))
                    .font(.system(size: 20, weight: .regular))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.horizontal)
            } else {
                // Fallback: bare word
                Text(card.word)
                    .font(.system(size: 48, weight: .medium))
            }

            if showAnswer {
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
                    ratingButton("Again", color: .red, rating: .again)
                    ratingButton("Hard", color: .orange, rating: .hard)
                    ratingButton("Good", color: .green, rating: .good)
                    ratingButton("Easy", color: .blue, rating: .easy)
                }
                .padding(.bottom, 24)
            } else {
                Spacer()

                VStack(spacing: 8) {
                    Button("Show Answer") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showAnswer = true
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
        .padding()
        .accessibilityIdentifier("leo.review.root")
        .accessibilityElement(children: .contain)
    }

    /// Returns an `AttributedString` with the target `word` bolded and tinted in accent color
    /// within the full `sentence`. Falls back to plain sentence text if the word is not found.
    private func highlightedSentence(sentence: String, word: String) -> AttributedString {
        var attributed = AttributedString(sentence)

        guard !word.isEmpty,
              let range = sentence.range(of: word) else {
            return attributed
        }

        // Map String.Index range to AttributedString.Index range
        let start = AttributedString.Index(range.lowerBound, within: attributed)
        let end = AttributedString.Index(range.upperBound, within: attributed)

        if let start, let end, start < end {
            attributed[start..<end].font = .system(size: 20, weight: .bold)
            attributed[start..<end].foregroundColor = .accentColor
        }

        return attributed
    }

    private func ratingButton(_ label: String, color: Color, rating: Rating) -> some View {
        Button(action: { rate(rating) }) {
            VStack(spacing: 2) {
                Text(label)
                Text(keyHint(for: rating))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .keyboardShortcut(keyForRating(rating), modifiers: [])
        .accessibilityLabel(label)
        .accessibilityValue("Shortcut \(keyHint(for: rating))")
        .accessibilityIdentifier(rating == .good ? "leo.review.rate.good" : "leo.review.rate.\(label.lowercased())")
    }

    private func keyForRating(_ rating: Rating) -> KeyEquivalent {
        switch rating {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }

    private func keyHint(for rating: Rating) -> String {
        switch rating {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }

    // MARK: - Review Complete

    private var reviewCompleteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("All caught up!")
                .font(.title2.weight(.medium))
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
        }
        .accessibilityIdentifier("leo.review.root")
        .accessibilityElement(children: .contain)
    }

    // MARK: - Actions

    private func rate(_ rating: Rating) {
        let fsrs = FSRSEngine(modelContext: modelContext)
        let card = dueCards[0]
        fsrs.review(card: card, rating: rating)

        reviewedCount += 1
        showAnswer = false
        loadDueCards(preservingSessionCounts: true)
    }

    private func loadDueCards(preservingSessionCounts: Bool = false) {
        let fsrs = FSRSEngine(modelContext: modelContext)
        dueCards = fsrs.dueCards()
        showAnswer = false
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
