import SwiftData
import SwiftUI

struct LaterDrawerView: View {
    @Query(sort: \LaterCapture.createdAt, order: .reverse) private var allCaptures: [LaterCapture]
    @Query(sort: \CaptureCategory.sortOrder) private var categories: [CaptureCategory]

    var engine: LoveEngine

    @State private var showArchived = false
    @State private var newCategoryName = ""
    @State private var showNewCategory = false
    @Query(sort: \TaskSection.sortOrder) private var sections: [TaskSection]

    private var visibleCaptures: [LaterCapture] {
        allCaptures.filter { showArchived || !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Show archived", isOn: $showArchived)
                    .toggleStyle(.switch)
                Spacer()
                Button {
                    newCategoryName = ""
                    showNewCategory = true
                } label: {
                    Label("New category", systemImage: "tag.circle.fill")
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, LoveTheme.contentGutter)
            .padding(.vertical, 12)
            .background {
                LoveComposerChrome()
            }
            .padding(.horizontal, LoveTheme.contentGutter)

            if visibleCaptures.isEmpty {
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        LoveAccentRule(width: 40)
                        Label {
                            Text("Later is quiet")
                                .font(LoveTypography.panelTitle)
                        } icon: {
                            Image(systemName: "tray.full")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(LoveTheme.accent, LoveTheme.warmth.opacity(0.6))
                                .font(.system(size: 48))
                        }
                    }
                } description: {
                    Text("Drop links and thoughts with Quick capture (⌃⌥L) or the toolbar — no inbox shame, just a gentle queue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleCaptures, id: \.id) { cap in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(cap.body)
                                .font(.body)
                                .lineSpacing(4)
                                .lineLimit(5)
                            HStack(alignment: .firstTextBaseline) {
                                if let cat = cap.category {
                                    Text(cat.name.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(.secondary)
                                }
                                if cap.isArchived {
                                    Text("Archived")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(LoveTheme.accent.opacity(0.15), in: Capsule())
                                }
                                Spacer()
                                Menu("Promote…") {
                                    ForEach(sections, id: \.id) { sec in
                                        Button(sec.name) {
                                            engine.promoteCapture(cap, to: sec)
                                        }
                                    }
                                }
                                .disabled(sections.isEmpty || cap.isArchived)
                                if cap.isArchived {
                                    Button("Unarchive") {
                                        engine.unarchiveCapture(cap)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                } else {
                                    Button("Archive") {
                                        engine.archiveCapture(cap)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .listRowInsets(EdgeInsets(top: 4, leading: LoveTheme.contentGutter - 4, bottom: 4, trailing: LoveTheme.contentGutter - 4))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                                .padding(.vertical, 2)
                        )
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .listRowSeparator(.hidden)
            }
        }
        .sheet(isPresented: $showNewCategory) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    LoveAccentRule(width: 32)
                    Text("Category name")
                        .font(LoveTypography.sheetTitle)
                    Text("Light labels for clusters of captures.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                TextField("e.g. Reading, AI, Home", text: $newCategoryName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    Spacer()
                    Button("Cancel") { showNewCategory = false }
                    Button("Add") {
                        let n = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !n.isEmpty { engine.addCaptureCategory(named: n) }
                        showNewCategory = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(28)
            .frame(minWidth: 320)
            .tint(LoveTheme.accent)
        }
    }
}
