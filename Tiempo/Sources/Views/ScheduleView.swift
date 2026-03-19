import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var scheduleEngine = ScheduleEngine()
    @State private var selectedWeekStart = ScheduleEngine().mondayOfWeek(containing: Date())
    @State private var selectedMode: ScheduleMode = .plan
    @State private var selectedDay: Int = Calendar.current.component(.weekday, from: Date()) - 1 // 0=Sun

    enum ScheduleMode: String, CaseIterable {
        case plan = "Plan"
        case compare = "Compare"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Schedule")
                    .font(.largeTitle.bold())
                Spacer()
                Picker("Mode", selection: $selectedMode) {
                    ForEach(ScheduleMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()

            // Week navigation
            HStack {
                Button {
                    selectedWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedWeekStart) ?? selectedWeekStart
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(weekLabel)
                    .font(.headline)
                    .frame(minWidth: 200)

                Button {
                    selectedWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedWeekStart) ?? selectedWeekStart
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Today") {
                    selectedWeekStart = scheduleEngine.mondayOfWeek(containing: Date())
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // Day selector
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { day in
                    let dayName = dayNames[day]
                    let isSelected = day == selectedDay
                    Button {
                        selectedDay = day
                    } label: {
                        Text(dayName)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Content
            switch selectedMode {
            case .plan:
                DayScheduleGrid(
                    scheduleEngine: scheduleEngine,
                    weekStart: selectedWeekStart,
                    dayOfWeek: selectedDay
                )
            case .compare:
                CompareView(date: selectedDate)
            }
        }
        .onAppear {
            scheduleEngine.configure(with: modelContext)
            scheduleEngine.materializeIfNeeded()
        }
    }

    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDay, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
        return "\(formatter.string(from: selectedWeekStart)) – \(formatter.string(from: end))"
    }

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}

// MARK: - Day Schedule Grid (the calendar-like time grid)

struct DayScheduleGrid: View {
    let scheduleEngine: ScheduleEngine
    let weekStart: Date
    let dayOfWeek: Int

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil && !$0.isArchived },
           sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var blocks: [ScheduledBlock] = []
    @State private var showingAddBlock = false
    @State private var newBlockStart: Int = 9 * 60 // 9:00 AM in minutes
    @State private var newBlockEnd: Int = 10 * 60 // 10:00 AM

    private let hourHeight: CGFloat = 60
    private let startHour = 6  // 6 AM
    private let endHour = 23   // 11 PM

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                // Hour lines + labels
                ForEach(startHour..<endHour, id: \.self) { hour in
                    HStack(spacing: 8) {
                        Text(String(format: "%d:00", hour))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 45, alignment: .trailing)

                        Rectangle()
                            .fill(Color(.separatorColor))
                            .frame(height: 0.5)
                    }
                    .offset(y: CGFloat(hour - startHour) * hourHeight)
                }

                // Blocks
                ForEach(blocks) { block in
                    if let cat = block.category {
                        ScheduleBlockView(
                            block: block,
                            categoryName: cat.name,
                            color: cat.color,
                            hourHeight: hourHeight,
                            startHour: startHour
                        )
                        .offset(x: 55) // After time labels
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                scheduleEngine.deleteBlock(block)
                                refreshBlocks()
                            }
                        }
                    }
                }

                // Click area for creating new blocks
                Color.clear
                    .contentShape(Rectangle())
                    .frame(height: CGFloat(endHour - startHour) * hourHeight)
                    .offset(x: 55)
                    .onTapGesture { location in
                        let minuteFromTop = Int(location.y / hourHeight * 60) + startHour * 60
                        let snapped = (minuteFromTop / 30) * 30 // Snap to 30-min
                        newBlockStart = snapped
                        newBlockEnd = snapped + 60
                        showingAddBlock = true
                    }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight)
            .padding()
        }
        .onAppear { refreshBlocks() }
        .onChange(of: weekStart) { refreshBlocks() }
        .onChange(of: dayOfWeek) { refreshBlocks() }
        .sheet(isPresented: $showingAddBlock) {
            AddBlockSheet(
                scheduleEngine: scheduleEngine,
                weekStart: weekStart,
                dayOfWeek: dayOfWeek,
                startMinutes: newBlockStart,
                endMinutes: newBlockEnd,
                categories: categories
            ) {
                refreshBlocks()
            }
        }
    }

    private func refreshBlocks() {
        blocks = scheduleEngine.blocksForDay(weekStart: weekStart, dayOfWeek: dayOfWeek)
    }
}

// MARK: - Block visual

struct ScheduleBlockView: View {
    let block: ScheduledBlock
    let categoryName: String
    let color: String
    let hourHeight: CGFloat
    let startHour: Int

    private var topOffset: CGFloat {
        let (h, m) = block.startHourMinute
        let minutesFromStart = CGFloat((h - startHour) * 60 + m)
        return minutesFromStart / 60.0 * hourHeight
    }

    private var blockHeight: CGFloat {
        max(CGFloat(block.durationMinutes) / 60.0 * hourHeight, 24)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(categoryName)
                .font(.caption.bold())
                .foregroundStyle(.white)
            if block.objectiveType == "description" && !block.descriptionText.isEmpty {
                Text(block.descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
            if block.objectiveType == "checklist" {
                let items = block.checklistItems
                ForEach(items.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Image(systemName: items[i].completed ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                        Text(items[i].text)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: blockHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: color) ?? .blue)
        )
        .offset(y: topOffset)
    }
}

// MARK: - Add Block Sheet

struct AddBlockSheet: View {
    let scheduleEngine: ScheduleEngine
    let weekStart: Date
    let dayOfWeek: Int
    let startMinutes: Int
    let endMinutes: Int
    let categories: [Category]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Category?
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var objectiveType = "description"
    @State private var descriptionText = ""
    @State private var checklistItems: [ScheduledBlock.ChecklistItem] = []
    @State private var newItemText = ""
    @State private var error: String?

    init(scheduleEngine: ScheduleEngine, weekStart: Date, dayOfWeek: Int, startMinutes: Int, endMinutes: Int, categories: [Category], onDone: @escaping () -> Void) {
        self.scheduleEngine = scheduleEngine
        self.weekStart = weekStart
        self.dayOfWeek = dayOfWeek
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.categories = categories
        self.onDone = onDone

        // Convert minutes to Date with time components
        let cal = Calendar.current
        let start = cal.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: Date()) ?? Date()
        let end = cal.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: Date()) ?? Date()
        self._startTime = State(initialValue: start)
        self._endTime = State(initialValue: end)
        self._selectedCategory = State(initialValue: categories.first)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Scheduled Block")
                .font(.title2.bold())

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
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

            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)

            Picker("Objective Type", selection: $objectiveType) {
                Text("Description").tag("description")
                Text("Checklist").tag("checklist")
            }
            .pickerStyle(.segmented)

            if objectiveType == "description" {
                TextField("What's the plan?", text: $descriptionText, axis: .vertical)
                    .lineLimit(3)
                    .textFieldStyle(.roundedBorder)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(checklistItems.indices, id: \.self) { i in
                        HStack {
                            Text("• \(checklistItems[i].text)")
                                .font(.caption)
                            Spacer()
                            Button { checklistItems.remove(at: i) } label: {
                                Image(systemName: "xmark.circle").font(.caption)
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add item", text: $newItemText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addChecklistItem() }
                        Button("Add") { addChecklistItem() }
                            .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Block") { createBlock() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCategory == nil)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func addChecklistItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        checklistItems.append(.init(text: trimmed, completed: false))
        newItemText = ""
    }

    private func createBlock() {
        guard let cat = selectedCategory else { return }
        guard let block = scheduleEngine.createBlock(
            category: cat,
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime
        ) else {
            error = "Cannot create block — overlaps with an existing block."
            return
        }

        if objectiveType == "description" {
            block.descriptionText = descriptionText
        } else {
            block.checklistItems = checklistItems
        }

        onDone()
        dismiss()
    }
}
