import SwiftUI
import SwiftData

/// SRS review interface — shows due cards and handles rating.
struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dueCards: [FSRSCard] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var sessionComplete = false

    var body: some View {
        VStack(spacing: 0) {
            if sessionComplete || dueCards.isEmpty {
                reviewCompleteView
            } else {
                cardView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            loadDueCards()
        }
    }

    // MARK: - Card View

    private var cardView: some View {
        let card = dueCards[currentIndex]
        let entries = DictionaryEngine.shared.lookup(card.word)
        let freq = FrequencyEngine.shared.lookup(card.word)

        return VStack(spacing: 24) {
            // Progress
            HStack {
                Text("\(currentIndex + 1) / \(dueCards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Reviews: \(card.reviewCount) | Lapses: \(card.lapseCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            Spacer()

            // Word (always visible)
            Text(card.word)
                .font(.system(size: 48, weight: .medium))

            if showAnswer {
                // Pinyin
                if let entry = entries.first {
                    Text(entry.pinyinDisplay)
                        .font(.title2)
                        .foregroundStyle(.orange)
                }

                // Frequency
                Text(freq.tier.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: freq.tier.color).opacity(0.2))
                    .foregroundStyle(Color(hex: freq.tier.color))
                    .clipShape(Capsule())

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

                Button("Show Answer") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showAnswer = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                .padding(.bottom, 24)
            }
        }
        .padding()
    }

    private func ratingButton(_ label: String, color: Color, rating: Rating) -> some View {
        Button(action: { rate(rating) }) {
            Text(label)
                .frame(width: 70)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .keyboardShortcut(keyForRating(rating), modifiers: [])
    }

    private func keyForRating(_ rating: Rating) -> KeyEquivalent {
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
            Text("No cards due for review.")
                .foregroundStyle(.secondary)
            Button("Refresh") {
                loadDueCards()
            }
        }
    }

    // MARK: - Actions

    private func rate(_ rating: Rating) {
        let fsrs = FSRSEngine(modelContext: modelContext)
        let card = dueCards[currentIndex]
        fsrs.review(card: card, rating: rating)

        showAnswer = false
        if currentIndex + 1 < dueCards.count {
            currentIndex += 1
        } else {
            sessionComplete = true
        }
    }

    private func loadDueCards() {
        let fsrs = FSRSEngine(modelContext: modelContext)
        dueCards = fsrs.dueCards()
        currentIndex = 0
        showAnswer = false
        sessionComplete = dueCards.isEmpty
    }
}
