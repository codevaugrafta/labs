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
                Picker("", selection: $selectedTab) {
                    ForEach(MainTab.allCases, id: \.rawValue) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == .mustDo {
                    mustDoPane
                } else {
                    LaterDrawerView(engine: engine)
                }
            }
            .animation(FeedbackPolicy.listTransition(reduceMotion: reduceMotion), value: selectedTab)
            .navigationTitle("Love")
            .toolbar {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Scope", selection: $listFilter) {
                    ForEach(MainListFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                Spacer()

                Button("Add section") {
                    newSectionName = ""
                    showAddSection = true
                }
            }
            .padding(.horizontal)

            HStack(alignment: .firstTextBaseline) {
                TextField("New must-do…", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTaskFromField)
                Picker("Section", selection: $newTaskSectionID) {
                    ForEach(sections, id: \.id) { s in
                        Text(s.name).tag(Optional(s.id))
                    }
                }
                .frame(minWidth: 120)
                Button("Add") { addTaskFromField() }
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTaskSectionID == nil)
            }
            .padding(.horizontal)

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
                            Text(section.name)
                                .font(.headline)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func visibleItems(for section: TaskSection) -> [MustDoItem] {
        activeMustDos
            .filter { $0.section?.id == section.id }
            .filter { !$0.isSnoozed() }
            .filter { $0.matches(listFilter: listFilter) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    private func mustDoRow(_ item: MustDoItem) -> some View {
        let isFocus = engine.focusedItemID == item.id
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isFocus ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isFocus ? Color.accentColor : .secondary)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .fontWeight(isFocus ? .semibold : .regular)
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { item.planningBucket },
                        set: { engine.setPlanningBucket(item, bucket: $0) }
                    )) {
                        ForEach(PlanningBucket.allCases, id: \.rawValue) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)

                    if item.snoozeUntil != nil {
                        Button("Clear snooze") {
                            engine.clearSnooze(item)
                        }
                        .font(.caption)
                    } else {
                        Button("Tomorrow") {
                            engine.deferToTomorrow(item)
                        }
                        .font(.caption)
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
        }
        .padding(.vertical, 4)
    }

    private func addTaskFromField() {
        let t = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let sid = newTaskSectionID, let section = sections.first(where: { $0.id == sid }) else { return }
        engine.addMustDo(title: t, section: section, bucket: .backlog)
        newTaskTitle = ""
    }

    private var addSectionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New section")
                .font(.title2)
            TextField("Name", text: $newSectionName)
                .textFieldStyle(.roundedBorder)
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
                .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
