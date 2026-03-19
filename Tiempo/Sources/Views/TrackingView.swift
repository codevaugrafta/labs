import SwiftUI
import SwiftData

// MARK: - TrackingView

struct TrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimeEntryEngine.self) private var engine

    @Query(
        filter: #Predicate<Category> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Category.sortOrder
    )
    private var categories: [Category]

    @State private var showingAddCategory = false
    @State private var showingTagManagement = false
    @State private var categoryToDelete: Category?
    @State private var categoryDeleteError: String?
    @State private var timerTick = Date()

    // Local mutable copy for drag reordering
    @State private var orderedCategories: [Category] = []

    // Top-level categories (no parent)
    private var rootCategories: [Category] {
        orderedCategories.filter { $0.parentId == nil }
    }

    // Subcategories grouped by parent id
    private func subcategories(of parent: Category) -> [Category] {
        orderedCategories.filter { $0.parentId == parent.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tracking")
                    .font(.largeTitle.bold())
                Spacer()
                Menu {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                    Button {
                        showingTagManagement = true
                    } label: {
                        Label("Manage Tags", systemImage: "number")
                    }
                    Divider()
                    Toggle(isOn: Binding(
                        get: { engine.allowConcurrentTimers },
                        set: { engine.allowConcurrentTimers = $0 }
                    )) {
                        Label("Allow Concurrent Timers", systemImage: "timer.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                Button {
                    showingAddCategory = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Add category")
            }
            .padding()

            // Error banner
            if let error = engine.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.1))
            }

            // Active timer banner
            if let active = engine.activeEntry, let cat = active.category {
                ActiveTimerBanner(
                    entry: active,
                    categoryName: cat.name,
                    color: cat.color,
                    tick: timerTick
                ) {
                    TiempoFeedback.onTimerStop()
                    engine.stopTimer()
                }
                .padding(.horizontal)
            }

            if categories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Create your first category to start tracking")
                        .foregroundStyle(.secondary)
                    Button("Add Category") {
                        showingAddCategory = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16, pinnedViews: []) {
                        // Root categories with their subcategories
                        ForEach(rootCategories) { parent in
                            VStack(alignment: .leading, spacing: 8) {
                                // Parent tile
                                CategoryTile(
                                    category: parent,
                                    activeEntry: engine.isActive(category: parent) ? engine.activeEntry : nil,
                                    tick: timerTick
                                ) {
                                    let wasActive = engine.isActive(category: parent)
                                    engine.toggleTimer(for: parent)
                                    if wasActive { TiempoFeedback.onTimerStop() }
                                    else { TiempoFeedback.onTimerStart() }
                                }
                                .contextMenu {
                                    categoryContextMenu(for: parent)
                                }

                                // Subcategory row (indented)
                                let subs = subcategories(of: parent)
                                if !subs.isEmpty {
                                    HStack(spacing: 0) {
                                        // Indentation line
                                        Rectangle()
                                            .fill(Color(hex: parent.color)?.opacity(0.3) ?? Color.secondary.opacity(0.2))
                                            .frame(width: 2)
                                            .padding(.leading, 16)
                                            .padding(.trailing, 10)

                                        LazyVGrid(
                                            columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 8)],
                                            spacing: 8
                                        ) {
                                            ForEach(subs) { sub in
                                                CategoryTile(
                                                    category: sub,
                                                    activeEntry: engine.isActive(category: sub) ? engine.activeEntry : nil,
                                                    tick: timerTick,
                                                    isSubcategory: true
                                                ) {
                                                    engine.toggleTimer(for: sub)
                                                }
                                                .contextMenu {
                                                    categoryContextMenu(for: sub)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Orphaned subcategories (parent was archived/deleted but child remains)
                        let orphans = orderedCategories.filter { cat in
                            guard let pid = cat.parentId else { return false }
                            return !orderedCategories.contains(where: { $0.id == pid })
                        }
                        if !orphans.isEmpty {
                            ForEach(orphans) { cat in
                                CategoryTile(
                                    category: cat,
                                    activeEntry: engine.isActive(category: cat) ? engine.activeEntry : nil,
                                    tick: timerTick
                                ) {
                                    engine.toggleTimer(for: cat)
                                }
                                .contextMenu {
                                    categoryContextMenu(for: cat)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            engine.configure(with: modelContext)
            orderedCategories = categories
        }
        .onChange(of: categories) { _, newValue in
            orderedCategories = newValue
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timerTick = Date()
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(allCategories: categories)
        }
        .sheet(isPresented: $showingTagManagement) {
            TagManagementView()
        }
        .alert("Cannot Delete Category", isPresented: Binding(
            get: { categoryDeleteError != nil },
            set: { if !$0 { categoryDeleteError = nil } }
        )) {
            Button("Archive Instead") {
                if let cat = categoryToDelete {
                    engine.archiveCategory(cat)
                }
                categoryToDelete = nil
                categoryDeleteError = nil
            }
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
                categoryDeleteError = nil
            }
        } message: {
            Text(categoryDeleteError ?? "")
        }
        .alert("Timer Recovery", isPresented: Binding(
            get: { engine.showCrashRecovery },
            set: { engine.showCrashRecovery = $0 }
        )) {
            Button("Keep Running") { engine.keepRecoveredTimer() }
            Button("Stop Now") { engine.trimRecoveredTimer(to: Date()) }
            Button("Discard", role: .destructive) { engine.discardRecoveredTimer() }
        } message: {
            if let entry = engine.recoveredEntry {
                Text("A timer for \"\(entry.category?.name ?? "Unknown")\" was running since \(entry.startedAt.formatted(date: .abbreviated, time: .shortened)). What would you like to do?")
            }
        }
    }

    @ViewBuilder
    private func categoryContextMenu(for category: Category) -> some View {
        Button {
            engine.toggleFavorite(category)
        } label: {
            Label(
                category.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: category.isFavorite ? "star.fill" : "star"
            )
        }
        Button {
            engine.archiveCategory(category)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            categoryToDelete = category
            if engine.canDeleteCategory(category) {
                // Direct delete (soft-delete via deletedAt)
                category.deletedAt = Date()
                category.updatedAt = Date()
                try? modelContext.save()
                categoryToDelete = nil
            } else {
                categoryDeleteError = "\"\(category.name)\" has time entries. Archive it instead to keep your history."
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - CategoryTile

struct CategoryTile: View {
    let category: Category
    let activeEntry: TimeEntry?
    let tick: Date
    var isSubcategory: Bool = false
    let onTap: () -> Void

    private var isActive: Bool { activeEntry != nil }

    private var parsedColor: Color {
        Color(hex: category.color) ?? .blue
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(parsedColor)
                        .frame(width: 4, height: isSubcategory ? 24 : 32)

                    VStack(alignment: .leading, spacing: 2) {
                        if isActive, let entry = activeEntry {
                            Text(elapsedText(for: entry))
                                .font(.system(isSubcategory ? .callout : .title3, design: .monospaced).bold())
                                .foregroundStyle(parsedColor)
                        }
                        HStack(spacing: 4) {
                            if let icon = category.icon, !icon.isEmpty {
                                Text(icon)
                                    .font(isSubcategory ? .caption : .body)
                            }
                            Text(category.name)
                                .font(isActive ? .caption : (isSubcategory ? .callout : .body))
                                .foregroundStyle(isActive ? .secondary : .primary)
                            if category.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                    Spacer()
                }
            }
            .padding(isSubcategory ? 8 : 12)
            .background {
                RoundedRectangle(cornerRadius: isSubcategory ? 8 : 10)
                    .fill(isActive ? parsedColor.opacity(0.1) : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: isSubcategory ? 8 : 10)
                            .strokeBorder(isActive ? parsedColor : .clear, lineWidth: 2)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func elapsedText(for entry: TimeEntry) -> String {
        _ = tick
        return entry.formattedDuration
    }
}

// MARK: - ActiveTimerBanner

struct ActiveTimerBanner: View {
    let entry: TimeEntry
    let categoryName: String
    let color: String
    let tick: Date
    let onStop: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: color) ?? .blue)
                .frame(width: 10, height: 10)
                .timerPulse(isActive: true)
            Text(durationText)
                .font(.system(.body, design: .monospaced).bold())
            Text(categoryName)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        }
    }

    private var durationText: String {
        _ = tick
        return entry.formattedDuration
    }
}

// MARK: - AddCategorySheet (enhanced with icon picker + parent picker)

struct AddCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimeEntryEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    let allCategories: [Category]

    @State private var name = ""
    @State private var selectedColor = "#4A90D9"
    @State private var icon = ""
    @State private var parentId: UUID?
    @State private var validationError: String?

    private let colorOptions = [
        "#4A90D9", "#E74C3C", "#2ECC71", "#F39C12",
        "#9B59B6", "#1ABC9C", "#E67E22", "#3498DB",
        "#E91E63", "#00BCD4", "#8BC34A", "#FF5722"
    ]

    // Only top-level categories are valid parents (1-level max)
    private var parentCandidates: [Category] {
        allCategories.filter { $0.parentId == nil && !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New Category")
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

            if let error = validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Emoji icon
            VStack(alignment: .leading, spacing: 4) {
                Text("Icon (optional emoji)").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("e.g. 💼 🏃 🎨", text: $icon)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: icon) { _, newValue in
                        // Limit to first character if it's an emoji
                        if newValue.count > 2 {
                            icon = String(newValue.prefix(2))
                        }
                    }
            }

            // Color
            VStack(alignment: .leading, spacing: 6) {
                Text("Color").font(.caption.bold()).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                    ForEach(colorOptions, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if hex == selectedColor {
                                    Circle().strokeBorder(.white, lineWidth: 3)
                                }
                            }
                            .onTapGesture { selectedColor = hex }
                    }
                }
            }

            // Parent category (subcategory support)
            if !parentCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parent category (optional)").font(.caption.bold()).foregroundStyle(.secondary)
                    Picker("Parent", selection: $parentId) {
                        Text("None (top-level)").tag(UUID?.none)
                        ForEach(parentCandidates) { cat in
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
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Validate subcategory nesting
        if let error = engine.validateSubcategory(parentId: parentId, allCategories: allCategories) {
            validationError = error
            return
        }

        let nextOrder = (allCategories.map(\.sortOrder).max() ?? -1) + 1
        let iconValue = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = Category(
            name: trimmed,
            color: selectedColor,
            icon: iconValue.isEmpty ? nil : iconValue,
            parentId: parentId,
            sortOrder: nextOrder
        )
        modelContext.insert(category)
        try? modelContext.save()
        dismiss()
    }
}
