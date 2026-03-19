import SwiftUI
import SwiftData

struct EventsView: View {
    @Environment(TimeEntryEngine.self) private var engine
    @Query(
        filter: #Predicate<TimeEntry> { !$0.isRunning && $0.deletedAt == nil },
        sort: \TimeEntry.startedAt,
        order: .reverse
    )
    private var entries: [TimeEntry]

    @State private var showingAddEntry = false
    @State private var editingEntry: TimeEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Events")
                    .font(.largeTitle.bold())
                Spacer()
                Text("\(entries.count) entries")
                    .foregroundStyle(.secondary)
                Button {
                    showingAddEntry = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
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
                        .contextMenu {
                            Button("Edit") {
                                editingEntry = entry
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                engine.softDeleteEntry(entry)
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntrySheet()
        }
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(entry: entry)
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
                HStack(spacing: 6) {
                    Text(entry.category?.name ?? "Unknown")
                        .font(.body.bold())
                    if let note = entry.note, !note.isEmpty {
                        Text("— \(note)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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

                if !entry.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(entry.tags) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.secondary.opacity(0.15)))
                        }
                    }
                }
            }

            Spacer()

            Text(entry.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Entry Sheet

struct EditEntrySheet: View {
    @Environment(TimeEntryEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    let entry: TimeEntry
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String

    init(entry: TimeEntry) {
        self.entry = entry
        self._startDate = State(initialValue: entry.startedAt)
        self._endDate = State(initialValue: entry.endedAt ?? Date())
        self._note = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Entry")
                .font(.title2.bold())

            HStack {
                Circle()
                    .fill(Color(hex: entry.category?.color ?? "#888") ?? .gray)
                    .frame(width: 10, height: 10)
                Text(entry.category?.name ?? "Unknown")
                    .font(.headline)
            }

            DatePicker("Start", selection: $startDate)
            DatePicker("End", selection: $endDate, in: startDate...)

            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    engine.updateEntry(
                        entry,
                        startedAt: startDate,
                        endedAt: endDate,
                        note: note.isEmpty ? nil : note
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
