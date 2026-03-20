import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil && !$0.isArchived },
           sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var goalsEngine = GoalsEngine()
    @State private var progressList: [GoalsEngine.GoalProgress] = []
    @State private var showingAddGoal = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Goals")
                    .font(.largeTitle.bold())
                Spacer()
                Button { showingAddGoal = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            if let err = goalsEngine.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") {
                        goalsEngine.clearLastError()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Goals error: \(err)")
            }

            if progressList.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No goals yet")
                        .foregroundStyle(.secondary)
                    Text("Set daily, weekly, or monthly time targets")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Add Goal") { showingAddGoal = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Today") {
                        ForEach(progressList.filter { $0.goal.period == "daily" }, id: \.goal.id) { p in
                            GoalRow(progress: p) {
                                goalsEngine.deleteGoal(p.goal)
                                refreshProgress()
                            }
                        }
                    }
                    Section("This Week") {
                        ForEach(progressList.filter { $0.goal.period == "weekly" }, id: \.goal.id) { p in
                            GoalRow(progress: p) {
                                goalsEngine.deleteGoal(p.goal)
                                refreshProgress()
                            }
                        }
                    }
                    Section("This Month") {
                        ForEach(progressList.filter { $0.goal.period == "monthly" }, id: \.goal.id) { p in
                            GoalRow(progress: p) {
                                goalsEngine.deleteGoal(p.goal)
                                refreshProgress()
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            goalsEngine.configure(with: modelContext)
            refreshProgress()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                refreshProgress()
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet(goalsEngine: goalsEngine, categories: categories) {
                refreshProgress()
            }
        }
    }

    private func refreshProgress() {
        progressList = goalsEngine.allProgress()
    }
}

struct GoalRow: View {
    let progress: GoalsEngine.GoalProgress
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: progress.color) ?? .blue)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(progress.categoryName)
                        .font(.body.bold())
                    Spacer()
                    if progress.isMet {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ThemeManager.shared.border)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: geo.size.width * min(progress.percentage, 1.0))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(formatMinutes(progress.trackedMinutes))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("of \(formatMinutes(progress.targetMinutes))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(progress.percentage * 100))%")
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(progressColor)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete Goal", role: .destructive, action: onDelete)
        }
    }

    private var progressColor: Color {
        if progress.percentage >= 1.0 { return .green }
        if progress.percentage >= 0.5 { return .orange }
        return .accentColor
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

struct AddGoalSheet: View {
    let goalsEngine: GoalsEngine
    let categories: [Category]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Category?
    @State private var targetHours = 1
    @State private var targetMinutes = 0
    @State private var period = "daily"
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("New Goal")
                .font(.title2.bold())

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("Category", selection: $selectedCategory) {
                Text("Select...").tag(nil as Category?)
                ForEach(categories) { cat in
                    HStack {
                        Circle().fill(Color(hex: cat.color) ?? .blue).frame(width: 10, height: 10)
                        Text(cat.name)
                    }.tag(cat as Category?)
                }
            }

            HStack {
                Stepper("Hours: \(targetHours)", value: $targetHours, in: 0...24)
                Stepper("Min: \(targetMinutes)", value: $targetMinutes, in: 0...55, step: 5)
            }

            Picker("Period", selection: $period) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
                Text("Monthly").tag("monthly")
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Goal") {
                    error = nil
                    guard let cat = selectedCategory else { return }
                    let total = targetHours * 60 + targetMinutes
                    guard total > 0 else { return }
                    guard goalsEngine.createGoal(category: cat, targetMinutes: total, period: period) != nil else {
                        error = goalsEngine.lastError ?? "Could not create goal. Try again."
                        return
                    }
                    onDone()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCategory == nil || (targetHours == 0 && targetMinutes == 0))
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
