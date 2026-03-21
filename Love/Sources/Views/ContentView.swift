import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskSection.sortOrder) private var sections: [TaskSection]
    @Query(
        filter: #Predicate<MustDoItem> { $0.completedAt == nil },
        sort: [SortDescriptor(\MustDoItem.sortOrder)]
    )
    private var activeMustDos: [MustDoItem]

    var engine: LoveEngine

    @State private var listFilter: MainListFilter = .all
    @State private var selectedTab: MainTab = .mustDo
    @State private var newTaskTitle = ""
    @State private var newTaskSectionID: UUID?
    @State private var showAddSection = false
    @State private var newSectionName = ""

    private enum MainTab: String, CaseIterable {
        case mustDo = "Must do"
        case later = "Later"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let err = engine.lastError {
                    LoveSaveErrorBanner(message: err) {
                        engine.clearLastError()
                    }
                }
                LoveTabRail {
                    Picker("", selection: $selectedTab) {
                        ForEach(MainTab.allCases, id: \.rawValue) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)
                }
                .padding(.vertical, 12)

                if selectedTab == .mustDo {
                    mustDoPane
                } else {
                    LaterDrawerView(engine: engine)
                }
            }
            .animation(FeedbackPolicy.listTransition(reduceMotion: reduceMotion), value: selectedTab)
            .navigationTitle("")
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 4) {
                        Text("Love")
                            .font(LoveTypography.brandTitle)
                            .foregroundStyle(.primary)
                        Text("One focus · calm later drawer")
                            .font(LoveTypography.brandTagline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NotificationCenter.default.post(name: .loveQuickCapture, object: nil)
                    } label: {
                        Label("Quick capture", systemImage: "tray.and.arrow.down.fill")
                    }
                    .help("Later drawer quick capture (⌃⌥L)")
                }
            }
        }
        .sheet(isPresented: $showAddSection) {
            addSectionSheet
        }
        .onAppear {
            if newTaskSectionID == nil {
                newTaskSectionID = sections.first?.id
            }
        }
        .onChange(of: sections.count) { _, _ in
            if newTaskSectionID == nil {
                newTaskSectionID = sections.first?.id
            }
        }
    }

    private var mustDoPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Picker("Scope", selection: $listFilter) {
                    ForEach(MainListFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)

                Spacer(minLength: 12)

                Button {
                    newSectionName = ""
                    showAddSection = true
                } label: {
                    Label("Add section", systemImage: "folder.badge.plus")
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, LoveTheme.contentGutter)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("New must-do…", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous))
                    .onSubmit(addTaskFromField)
                Picker("Section", selection: $newTaskSectionID) {
                    ForEach(sections, id: \.id) { s in
                        Text(s.name).tag(Optional(s.id))
                    }
                }
                .frame(minWidth: 128, maxWidth: 180)
                Button("Add") { addTaskFromField() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTaskSectionID == nil)
            }
            .padding(16)
            .background {
                LoveComposerChrome()
            }
            .padding(.horizontal, LoveTheme.contentGutter)

            List {
                ForEach(sections) { section in
                    let items = visibleItems(for: section)
                    if !items.isEmpty || listFilter == .all {
                        Section {
                            ForEach(items, id: \.id) { item in
                                mustDoRow(item)
                            }
                            .onMove { source, dest in
                                engine.moveItems(in: section, activeOrdered: items, fromOffsets: source, toOffset: dest)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                LoveAccentRule(width: 28)
                                Text(section.name)
                                    .font(LoveTypography.sectionHeader)
                                    .textCase(.none)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 2)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .listRowSeparator(.hidden)
        }
    }

    private func visibleItems(for section: TaskSection) -> [MustDoItem] {
        activeMustDos
            .filter { $0.section?.id == section.id }
            .filter { !$0.isSnoozed() }
            .filter { $0.matches(listFilter: listFilter) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mustDoRow(_ item: MustDoItem) -> some View {
        let isFocus = engine.focusedItemID == item.id
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFocus ? "circle.inset.filled" : "circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(isFocus ? LoveTheme.accent : .secondary, .secondary)
                .imageScale(.large)
                .accessibilityLabel(isFocus ? "Focused must-do" : "Must-do")

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(isFocus ? LoveTypography.mustDoTitleFocus : LoveTypography.mustDoTitle)
                    .foregroundStyle(.primary)
                HStack(spacing: 10) {
                    Picker("", selection: Binding(
                        get: { item.planningBucket },
                        set: { engine.setPlanningBucket(item, bucket: $0) }
                    )) {
                        ForEach(PlanningBucket.allCases, id: \.rawValue) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 132)

                    if item.snoozeUntil != nil {
                        Button("Clear snooze") {
                            engine.clearSnooze(item)
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    } else {
                        Button("Tomorrow") {
                            engine.deferToTomorrow(item)
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Set focus") {
                    engine.setFocus(item)
                }
                Button("Complete") {
                    engine.complete(item)
                }
                Divider()
                Button("Defer to tomorrow") {
                    engine.deferToTomorrow(item)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    engine.deleteMustDo(item)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("More actions")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: LoveTheme.contentGutter - 4, bottom: 4, trailing: LoveTheme.contentGutter - 4))
        .listRowBackground(
            RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                .fill(isFocus ? LoveTheme.accentMuted : Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                        .strokeBorder(isFocus ? LoveTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                }
                .padding(.vertical, 2)
        )
    }

    private func addTaskFromField() {
        let t = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let sid = newTaskSectionID, let section = sections.first(where: { $0.id == sid }) else { return }
        engine.addMustDo(title: t, section: section, bucket: .backlog)
        newTaskTitle = ""
    }

    private var addSectionSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                LoveAccentRule(width: 32)
                Text("New section")
                    .font(LoveTypography.sheetTitle)
                Text("Group must-dos the way your week actually runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TextField("Name", text: $newSectionName)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous))
            HStack {
                Spacer()
                Button("Cancel") { showAddSection = false }
                Button("Create") {
                    let name = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        engine.addSection(named: name)
                    }
                    showAddSection = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(minWidth: 340)
        .tint(LoveTheme.accent)
    }
}
