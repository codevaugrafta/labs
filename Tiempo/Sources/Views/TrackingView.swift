import SwiftUI
import SwiftData

struct TrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimeEntryEngine.self) private var engine
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil && !$0.isArchived },
           sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var showingAddCategory = false
    @State private var timerTick = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tracking")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    showingAddCategory = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
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
                ActiveTimerBanner(entry: active, categoryName: cat.name, color: cat.color, tick: timerTick) {
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
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
                    ], spacing: 12) {
                        ForEach(categories) { category in
                            CategoryTile(
                                category: category,
                                activeEntry: engine.isActive(category: category) ? engine.activeEntry : nil,
                                tick: timerTick
                            ) {
                                engine.toggleTimer(for: category)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            engine.configure(with: modelContext)
        }
        .task {
            // Stable timer using async — no memory leak
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                timerTick = Date()
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet()
        }
        .alert("Timer Recovery", isPresented: Binding(
            get: { engine.showCrashRecovery },
            set: { engine.showCrashRecovery = $0 }
        )) {
            Button("Keep Running") { engine.keepRecoveredTimer() }
            Button("Stop Now") {
                engine.trimRecoveredTimer(to: Date())
            }
            Button("Discard", role: .destructive) {
                engine.discardRecoveredTimer()
            }
        } message: {
            if let entry = engine.recoveredEntry {
                Text("A timer for \"\(entry.category?.name ?? "Unknown")\" was running since \(entry.startedAt.formatted(date: .abbreviated, time: .shortened)). What would you like to do?")
            }
        }
    }
}

struct CategoryTile: View {
    let category: Category
    let activeEntry: TimeEntry?
    let tick: Date
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
                        .frame(width: 4, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        if isActive, let entry = activeEntry {
                            // Use the authoritative activeEntry, not the relationship array
                            Text(elapsedText(for: entry))
                                .font(.system(.title3, design: .monospaced).bold())
                                .foregroundStyle(parsedColor)
                        }
                        Text(category.name)
                            .font(isActive ? .caption : .body)
                            .foregroundStyle(isActive ? .secondary : .primary)
                    }
                    Spacer()
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? parsedColor.opacity(0.1) : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isActive ? parsedColor : .clear, lineWidth: 2)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func elapsedText(for entry: TimeEntry) -> String {
        _ = tick // force recomputation
        return entry.formattedDuration
    }
}

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
        _ = tick // consume tick to force re-render
        return entry.formattedDuration
    }
}

struct AddCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedColor = "#4A90D9"

    private let colorOptions = [
        "#4A90D9", "#E74C3C", "#2ECC71", "#F39C12",
        "#9B59B6", "#1ABC9C", "#E67E22", "#3498DB",
        "#E91E63", "#00BCD4", "#8BC34A", "#FF5722"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("New Category")
                .font(.title2.bold())

            TextField("Category name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                ForEach(colorOptions, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .blue)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if hex == selectedColor {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                            }
                        }
                        .onTapGesture {
                            selectedColor = hex
                        }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let category = Category(name: trimmed, color: selectedColor)
                    modelContext.insert(category)
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
