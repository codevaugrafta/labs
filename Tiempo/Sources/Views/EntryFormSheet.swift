import SwiftUI
import SwiftData

// MARK: - Shared entry form used by both Add Retroactive and Edit flows

struct EntryFormSheet: View {
    enum Mode {
        case add
        case edit(TimeEntry)
    }

    let mode: Mode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeEntryEngine.self) private var engine

    @Query(
        filter: #Predicate<Category> { !$0.isArchived && $0.deletedAt == nil },
        sort: \Category.sortOrder
    )
    private var categories: [Category]

    @Query(
        filter: #Predicate<Tag> { $0.deletedAt == nil },
        sort: \Tag.name
    )
    private var allTags: [Tag]

    @State private var selectedCategoryId: UUID?
    @State private var startDate: Date = Date().addingTimeInterval(-3600)
    @State private var endDate: Date = Date()
    @State private var note: String = ""
    @State private var selectedTagIds: Set<UUID> = []
    @State private var validationError: String?

    private var title: String {
        switch mode {
        case .add: return "Add Entry"
        case .edit: return "Edit Entry"
        }
    }

    private var selectedCategory: Category? {
        categories.first { $0.id == selectedCategoryId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 20)

            // Validation error
            if let error = validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.bottom, 12)
            }

            // Category picker
            VStack(alignment: .leading, spacing: 6) {
                Label("Category", systemImage: "tag.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $selectedCategoryId) {
                    Text("Select a category").tag(UUID?.none)
                    ForEach(categories) { cat in
                        HStack {
                            Circle()
                                .fill(Color(hex: cat.color) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(cat.name)
                        }
                        .tag(Optional(cat.id))
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.bottom, 16)

            // Time range
            VStack(alignment: .leading, spacing: 6) {
                Label("Start", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                DatePicker("Start time", selection: $startDate, in: ...Date())
                    .labelsHidden()
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 6) {
                Label("End", systemImage: "clock.badge.checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                DatePicker("End time", selection: $endDate, in: startDate...Date())
                    .labelsHidden()
            }
            .padding(.bottom, 16)

            // Note
            VStack(alignment: .leading, spacing: 6) {
                Label("Note", systemImage: "note.text")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Optional note", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
            }
            .padding(.bottom, 16)

            // Tags
            if !allTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tags", systemImage: "number")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TagPillGrid(allTags: allTags, selectedTagIds: $selectedTagIds)
                }
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode.isAdd ? "Add Entry" : "Save Changes") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedCategoryId == nil)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { populateIfEditing() }
    }

    private func populateIfEditing() {
        switch mode {
        case .add:
            // Preselect first available category
            selectedCategoryId = categories.first?.id
        case .edit(let entry):
            selectedCategoryId = entry.category?.id
            startDate = entry.startedAt
            endDate = entry.endedAt ?? Date()
            note = entry.note ?? ""
            selectedTagIds = Set(entry.tags.map { $0.id })
        }
    }

    private func save() {
        // Validation
        guard endDate > startDate else {
            validationError = "End time must be after start time."
            return
        }
        guard endDate <= Date() else {
            validationError = "End time cannot be in the future."
            return
        }
        guard startDate <= Date() else {
            validationError = "Start time cannot be in the future."
            return
        }
        guard let category = selectedCategory else {
            validationError = "Please select a category."
            return
        }

        switch mode {
        case .add:
            if let newEntry = engine.addRetroactiveEntry(
                category: category,
                startedAt: startDate,
                endedAt: endDate,
                note: note.isEmpty ? nil : note
            ) {
                for tag in allTags where selectedTagIds.contains(tag.id) {
                    engine.assignTag(tag, to: newEntry)
                }
            }

        case .edit(let entry):
            engine.updateEntry(
                entry,
                category: category,
                startedAt: startDate,
                endedAt: endDate,
                note: note,
                updateNote: true
            )
            // Sync tags
            let currentTagIds = Set(entry.tags.map { $0.id })
            let toAdd = selectedTagIds.subtracting(currentTagIds)
            let toRemove = currentTagIds.subtracting(selectedTagIds)

            for tag in allTags where toAdd.contains(tag.id) {
                engine.assignTag(tag, to: entry)
            }
            for tag in entry.tags.filter({ toRemove.contains($0.id) }) {
                engine.removeTag(tag, from: entry)
            }
        }

        dismiss()
    }
}

extension EntryFormSheet.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

// MARK: - Tag pill selection grid

struct TagPillGrid: View {
    let allTags: [Tag]
    @Binding var selectedTagIds: Set<UUID>

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(allTags) { tag in
                TagPill(
                    tag: tag,
                    isSelected: selectedTagIds.contains(tag.id)
                ) {
                    if selectedTagIds.contains(tag.id) {
                        selectedTagIds.remove(tag.id)
                    } else {
                        selectedTagIds.insert(tag.id)
                    }
                }
            }
        }
    }
}

struct TagPill: View {
    let tag: Tag
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(tag.name)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Simple flow layout for tag pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
