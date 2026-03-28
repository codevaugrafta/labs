import SwiftUI
import SwiftData

/// Shows all tracked vocabulary entries with filtering by familiarity state.
struct VocabularyView: View {
    @Query(sort: \VocabularyEntry.lastSeenAt, order: .reverse) private var allVocab: [VocabularyEntry]
    @State private var filter: FamiliarityState?
    @State private var searchText = ""

    private var filteredVocab: [VocabularyEntry] {
        var result = allVocab
        if let filter {
            result = result.filter { $0.state == filter }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.text.contains(searchText) ||
                $0.pinyin.contains(searchText) ||
                $0.definition.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                filterButton(nil, label: "All", count: allVocab.count)
                filterButton(.known, label: "Known", count: allVocab.filter { $0.state == .known }.count)
                filterButton(.learning, label: "Learning", count: allVocab.filter { $0.state == .learning || $0.state == .familiar }.count)
                filterButton(.seen, label: "Tapped", count: allVocab.filter { $0.state == .seen }.count)
                filterButton(.unknown, label: "New", count: allVocab.filter { $0.state == .unknown }.count)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if filteredVocab.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No vocabulary yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap words while reading to build your vocabulary.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List(filteredVocab) { entry in
                    VocabularyRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search vocabulary")
        .frame(minWidth: 400, minHeight: 300)
    }

    private func filterButton(_ state: FamiliarityState?, label: String, count: Int) -> some View {
        Button(action: { filter = state }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filter == state ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct VocabularyRow: View {
    let entry: VocabularyEntry

    var body: some View {
        HStack(spacing: 12) {
            // State indicator
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            // Word + pinyin
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.text)
                        .font(.system(size: 18, weight: .medium))
                    Text(entry.pinyin)
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }
                if !entry.definition.isEmpty {
                    Text(entry.definition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Encounter count
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.encounterCount)x")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.state.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var stateColor: Color {
        switch entry.state {
        case .unknown: .red
        case .seen: .orange
        case .learning: .yellow
        case .familiar: .gray
        case .known: .green
        }
    }
}
