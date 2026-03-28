import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]
    @State private var selectedBook: Book?
    @State private var showFilePicker = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                books: books,
                selectedBook: $selectedBook,
                onImport: { showFilePicker = true }
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
            allowedContentTypes: [.epub],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let booksDir = appSupport.appendingPathComponent("Leo/Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let destination = booksDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: destination)

        let book = Book(
            title: url.deletingPathExtension().lastPathComponent,
            author: "Unknown",
            filePath: destination.path,
            format: .epub
        )
        modelContext.insert(book)
        selectedBook = book
    }
}

struct LibrarySidebar: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    let onImport: () -> Void

    var body: some View {
        List(selection: $selectedBook) {
            Section("Library") {
                ForEach(books) { book in
                    HStack {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(book.title)
                                .font(.body)
                            Text(book.author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(book)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: onImport) {
                    Image(systemName: "plus")
                }
                .help("Import EPUB")
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
            Button("Import EPUB") {
                onImport()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}
