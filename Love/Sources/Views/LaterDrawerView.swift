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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Show archived", isOn: $showArchived)
                Spacer()
                Button("New category") {
                    newCategoryName = ""
                    showNewCategory = true
                }
            }
            .padding(.horizontal)

            if visibleCaptures.isEmpty {
                ContentUnavailableView(
                    "Nothing in the later drawer",
                    systemImage: "tray",
                    description: Text("Use Quick capture (⌃⌥L) or the toolbar button.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleCaptures, id: \.id) { cap in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cap.body)
                                .lineLimit(4)
                            HStack {
                                if let cat = cap.category {
                                    Text(cat.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if cap.isArchived {
                                    Text("Archived")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary)
                                        .clipShape(Capsule())
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
                                } else {
                                    Button("Archive") {
                                        engine.archiveCapture(cap)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showNewCategory) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Category name")
                    .font(.title2)
                TextField("e.g. AI", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showNewCategory = false }
                    Button("Add") {
                        let n = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !n.isEmpty { engine.addCaptureCategory(named: n) }
                        showNewCategory = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(minWidth: 300)
        }
    }
}
