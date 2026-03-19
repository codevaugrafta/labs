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

    @State private var showingAddRetroactive = false
    @State private var entryToEdit: TimeEntry?
    @State private var entryToDelete: TimeEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Events")
                    .font(.largeTitle.bold())
                Spacer()
                Text("\(entries.count) entries")
                    .foregroundStyle(.secondary)
                Button {
                    showingAddRetroactive = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Add retroactive entry")
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
                    Button("Add Entry") {
                        showingAddRetroactive = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        EventRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                entryToEdit = entry
                            }
                            .contextMenu {
                                Button {
                                    entryToEdit = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    entryToEdit = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAddRetroactive) {
            EntryFormSheet(mode: .add)
        }
        .sheet(item: $entryToEdit) { entry in
            EntryFormSheet(mode: .edit(entry))
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    engine.softDeleteEntry(entry)
                }
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
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
                    // Category emoji icon if present
                    if let icon = entry.category?.icon, !icon.isEmpty {
                        Text(icon)
                            .font(.caption)
                    }
                    Text(entry.category?.name ?? "Unknown")
                        .font(.body.bold())
                    // Subcategory visual indicator
                    if entry.category?.parentId != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                // Tag pills (only non-deleted tags)
                let visibleTags = entry.tags.filter { $0.deletedAt == nil }
                if !visibleTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(visibleTags) { tag in
                            Text(tag.name)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
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
