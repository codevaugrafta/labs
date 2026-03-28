import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]
    @State private var selectedBook: Book?
    @State private var showFilePicker = false
    @State private var showReview = false
    @State private var showVocabulary = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                books: books,
                selectedBook: $selectedBook,
                onImport: { showFilePicker = true },
                onReview: { showReview = true },
                onVocabulary: { showVocabulary = true },
                onDelete: deleteBook
            )
        } detail: {
            if let book = selectedBook {
                ReaderView(book: book)
            } else {
                EmptyLibraryView(onImport: { showFilePicker = true })
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.epub, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showReview) {
            ReviewView()
                .frame(minWidth: 500, minHeight: 450)
        }
        .sheet(isPresented: $showVocabulary) {
            VocabularyView()
                .frame(minWidth: 500, minHeight: 450)
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoImportBook)) { _ in
            showFilePicker = true
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        // Check for duplicate imports
        let fileName = url.lastPathComponent
        if books.contains(where: { $0.filePath.hasSuffix(fileName) }) {
            return // Already imported
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let booksDir = appSupport.appendingPathComponent("Leo/Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let destination = booksDir.appendingPathComponent(fileName)

        // Remove existing file if somehow present
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try? FileManager.default.copyItem(at: url, to: destination)

        let format: BookFormat = url.pathExtension.lowercased() == "pdf" ? .pdf : .epub
        let title = cleanTitle(from: url.deletingPathExtension().lastPathComponent)
        let book = Book(
            title: title,
            author: "",
            filePath: destination.path,
            format: format
        )
        modelContext.insert(book)
        selectedBook = book
    }

    private func deleteBook(_ book: Book) {
        // Remove the file
        try? FileManager.default.removeItem(atPath: book.filePath)
        // Deselect if selected
        if selectedBook == book {
            selectedBook = nil
        }
        // Remove from database
        modelContext.delete(book)
    }

    /// Clean up ugly filenames into readable titles
    private func cleanTitle(from filename: String) -> String {
        var title = filename
        // Remove leading numbers/underscores (e.g., "156552_活着" → "活着")
        title = title.replacingOccurrences(of: "^[0-9_]+", with: "", options: .regularExpression)
        // Remove URL encoding artifacts
        title = title.removingPercentEncoding ?? title
        // Trim
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? filename : title
    }
}

struct LibrarySidebar: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    let onImport: () -> Void
    let onReview: () -> Void
    let onVocabulary: () -> Void
    let onDelete: (Book) -> Void
    @Query private var vocabulary: [VocabularyEntry]
    @Query private var dueCards: [FSRSCard]

    var body: some View {
        List(selection: $selectedBook) {
            Section {
                Button(action: onReview) {
                    HStack {
                        Label("Review Cards", systemImage: "rectangle.stack")
                        Spacer()
                        let due = dueCards.filter { $0.dueDate <= Date() }.count
                        if due > 0 {
                            Text("\(due)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)

                Button(action: onVocabulary) {
                    HStack {
                        Label("Vocabulary", systemImage: "character.book.closed")
                        Spacer()
                        Text("\(vocabulary.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Vocabulary") {
                let known = vocabulary.filter { $0.state == .known }.count
                let learning = vocabulary.filter { $0.state == .learning || $0.state == .familiar }.count
                let tapped = vocabulary.filter { $0.state == .seen }.count
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(known)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("Known")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(learning)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.yellow)
                        Text("Learning")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tapped)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Tapped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Library") {
                Button(action: onImport) {
                    Label("Import Book", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                ForEach(books) { book in
                    HStack {
                        Image(systemName: book.format == .pdf ? "doc.fill" : "book.closed.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(book.title)
                                .font(.body)
                                .lineLimit(2)
                            if !book.author.isEmpty {
                                Text(book.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(book)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(book)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: onImport) {
                    Image(systemName: "plus")
                }
                .help("Import Book (Cmd+O)")
            }
        }
        .navigationTitle("Leo")
    }
}

struct EmptyLibraryView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Open a book to start reading")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Import Book") {
                onImport()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}
