import SwiftUI
import SwiftData

struct EventsView: View {
    @Query(
        filter: #Predicate<TimeEntry> { !$0.isRunning && $0.deletedAt == nil },
        sort: \TimeEntry.startedAt,
        order: .reverse
    )
    private var entries: [TimeEntry]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Events")
                    .font(.largeTitle.bold())
                Spacer()
                Text("\(entries.count) entries")
                    .foregroundStyle(.secondary)
            }
            .padding()

            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No events yet")
                        .foregroundStyle(.secondary)
                    Text("Start tracking to see your time entries here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    EventRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
    }
}

struct EventRow: View {
    let entry: TimeEntry

    private var categoryColor: Color {
        guard let cat = entry.category else { return .gray }
        return Color(hex: cat.color) ?? .gray
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category?.name ?? "Unknown")
                    .font(.body.bold())
                HStack(spacing: 8) {
                    Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                    if let end = entry.endedAt {
                        Text("→")
                            .foregroundStyle(.tertiary)
                        Text(end.formatted(date: .omitted, time: .shortened))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
