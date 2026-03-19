import SwiftUI
import SwiftData

struct AddEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimeEntryEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Category> { $0.deletedAt == nil && !$0.isArchived },
           sort: \Category.sortOrder)
    private var categories: [Category]

    @State private var selectedCategory: Category?
    @State private var startDate = Date().addingTimeInterval(-3600)
    @State private var endDate = Date()
    @State private var note = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Time Entry")
                .font(.title2.bold())

            // Category picker
            Picker("Category", selection: $selectedCategory) {
                Text("Select...").tag(nil as Category?)
                ForEach(categories) { cat in
                    HStack {
                        Circle()
                            .fill(Color(hex: cat.color) ?? .blue)
                            .frame(width: 10, height: 10)
                        Text(cat.name)
                    }
                    .tag(cat as Category?)
                }
            }

            DatePicker("Start", selection: $startDate)
            DatePicker("End", selection: $endDate, in: startDate...)

            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Entry") {
                    guard let cat = selectedCategory else { return }
                    engine.addRetroactiveEntry(
                        category: cat,
                        startedAt: startDate,
                        endedAt: endDate,
                        note: note.isEmpty ? nil : note
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCategory == nil)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
