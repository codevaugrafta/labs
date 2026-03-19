import SwiftUI
import SwiftData

struct TagManagementView: View {
    @Environment(TimeEntryEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Tag> { $0.deletedAt == nil },
        sort: \Tag.name
    )
    private var tags: [Tag]

    @State private var newTagName = ""
    @State private var editingTag: Tag?
    @State private var editingName = ""
    @State private var tagToDelete: Tag?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Manage Tags")
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
            .padding(.bottom, 16)

            // Add new tag
            HStack(spacing: 8) {
                TextField("New tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 8)

            if tags.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No tags yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tags) { tag in
                            TagRow(
                                tag: tag,
                                isEditing: editingTag?.id == tag.id,
                                editingName: $editingName,
                                onEdit: {
                                    editingTag = tag
                                    editingName = tag.name
                                },
                                onSave: {
                                    engine.updateTag(tag, name: editingName)
                                    editingTag = nil
                                    editingName = ""
                                },
                                onCancelEdit: {
                                    editingTag = nil
                                    editingName = ""
                                },
                                onDelete: {
                                    tagToDelete = tag
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 320)
        .alert("Delete tag?", isPresented: Binding(
            get: { tagToDelete != nil },
            set: { if !$0 { tagToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let tag = tagToDelete {
                    engine.deleteTag(tag)
                }
                tagToDelete = nil
            }
            Button("Cancel", role: .cancel) { tagToDelete = nil }
        } message: {
            if let tag = tagToDelete {
                Text("Delete \"\(tag.name)\"? It will be removed from all entries.")
            }
        }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = engine.addTag(name: trimmed)
        newTagName = ""
    }
}

private struct TagRow: View {
    let tag: Tag
    let isEditing: Bool
    @Binding var editingName: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            if isEditing {
                TextField("Tag name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onSave() }
                Button("Save") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { onCancelEdit() }
                    .controlSize(.small)
            } else {
                Text(tag.name)
                    .lineLimit(1)
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
