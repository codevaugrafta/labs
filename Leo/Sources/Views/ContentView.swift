import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

extension Notification.Name {
    /// Delivers picked `URL` from `NSOpenPanel` to `ContentView` (avoids escaping `self` in sheet callbacks).
    fileprivate static let leoBookImportPickedURL = Notification.Name("leoBookImportPickedURL")
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var runtime: LeoRuntime
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]
    @State private var selectedBook: Book?
    @State private var showAnkiImporter = false
    @State private var ankiImportMessage: String?
    @State private var showReview = false
    @State private var showVocabulary = false
    @State private var pdfConvertError: String?
    @State private var isConvertingPDF = false
    @State private var bookImportError: String?

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                books: books,
                selectedBook: $selectedBook,
                onImport: presentBookImportPanel,
                onReview: { showReview = true },
                onVocabulary: { showVocabulary = true },
                onDelete: deleteBook,
                onConvertPDFToEPUB: convertPDFBookToReflowEPUB
            )
        } detail: {
            if let book = selectedBook {
                ReaderView(book: book)
                    .id(book.id) // Force fresh view when switching books
            } else {
                EmptyLibraryView(onImport: presentBookImportPanel)
            }
        }
        .accessibilityIdentifier("leo.root.split")
        .fileImporter(
            isPresented: $showAnkiImporter,
            allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleAnkiImport(result)
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
            presentBookImportPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoBookImportPickedURL)) { note in
            guard let url = note.object as? URL else { return }
            importBook(fromPickedURL: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoImportAnki)) { _ in
            showAnkiImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoRequestPDFConvert)) { note in
            guard let id = note.object as? UUID,
                  let book = books.first(where: { $0.id == id }) else { return }
            convertPDFBookToReflowEPUB(book)
        }
        // Stable task id so a @Query refresh does not cancel import mid-flight (UI tests).
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_BOOK_PATH"] ?? "") {
            await importEnvironmentTestBookIfNeeded()
        }
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_SEED_FSRS_CARD"] ?? "") {
            await seedUITestFSRSCardIfNeeded()
        }
        .onAppear {
            syncSelectionWithLibrary()
        }
        .onChange(of: books.map(\.id)) { _, _ in
            syncSelectionWithLibrary()
        }
        .alert("Anki import", isPresented: Binding(
            get: { ankiImportMessage != nil },
            set: { if !$0 { ankiImportMessage = nil } }
        )) {
            Button("OK", role: .cancel) { ankiImportMessage = nil }
        } message: {
            if let ankiImportMessage {
                Text(ankiImportMessage)
            }
        }
        .alert("Convert PDF", isPresented: Binding(
            get: { pdfConvertError != nil },
            set: { if !$0 { pdfConvertError = nil } }
        )) {
            Button("OK", role: .cancel) { pdfConvertError = nil }
        } message: {
            if let pdfConvertError {
                Text(pdfConvertError)
            }
        }
        .alert("Import Book", isPresented: Binding(
            get: { bookImportError != nil },
            set: { if !$0 { bookImportError = nil } }
        )) {
            Button("OK", role: .cancel) { bookImportError = nil }
        } message: {
            if let bookImportError {
                Text(bookImportError)
            }
        }
        .overlay {
            if isConvertingPDF {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    ProgressView("Converting PDF…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .allowsHitTesting(true)
            }
        }
    }

    private func handleAnkiImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let importResult = try AnkiExporter().importDeck(from: url)
                let tracker = FamiliarityTracker(modelContext: modelContext)
                tracker.applyImportedStates(importResult.wordStates)
                ankiImportMessage = "Imported \(importResult.totalCards) cards into vocabulary familiarity."
            } catch {
                ankiImportMessage = error.localizedDescription
            }
        case .failure(let error):
            ankiImportMessage = error.localizedDescription
        }
    }

    /// UI tests only: `LEO_UI_TEST_BOOK_PATH` = absolute path to an EPUB/PDF to copy into the library and select (no file picker).
    @MainActor
    private func importEnvironmentTestBookIfNeeded() async {
        guard let raw = ProcessInfo.processInfo.environment["LEO_UI_TEST_BOOK_PATH"], !raw.isEmpty else { return }
        let source = URL(fileURLWithPath: (raw as NSString).standardizingPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            NSLog("[Leo] LEO_UI_TEST_BOOK_PATH missing file: \(source.path)")
            return
        }
        let fileName = source.lastPathComponent
        if let existing = books.first(where: { $0.filePath.hasSuffix(fileName) }) {
            selectedBook = existing
            return
        }
        let destination = runtime.booksDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            NSLog("[Leo] UI test book copy failed: \(error.localizedDescription)")
            return
        }
        let format: BookFormat = source.pathExtension.lowercased() == "pdf" ? .pdf : .epub
        let title = cleanTitle(from: source.deletingPathExtension().lastPathComponent)
        let book = Book(title: title, author: "", filePath: destination.path, format: format)
        modelContext.insert(book)
        try? modelContext.save()
        selectedBook = book
    }

    /// UI tests: ensure a due FSRS card so Review shows a real card (not empty state).
    @MainActor
    private func seedUITestFSRSCardIfNeeded() async {
        guard ProcessInfo.processInfo.environment["LEO_UI_TEST_SEED_FSRS_CARD"] == "1" else { return }
        let word = ProcessInfo.processInfo.environment["LEO_UI_TEST_FSRS_WORD"] ?? "你好"
        let engine = FSRSEngine(modelContext: modelContext)
        if let existing = engine.card(for: word) {
            existing.dueDate = Date(timeIntervalSince1970: 0)
            existing.state = .review
            try? modelContext.save()
            return
        }
        let card = FSRSCard(word: word)
        card.dueDate = Date(timeIntervalSince1970: 0)
        card.state = .review
        card.stability = 2.5
        card.difficulty = 5.0
        card.reviewCount = 1
        modelContext.insert(card)
        try? modelContext.save()
    }

    /// Uses `NSOpenPanel` so book import is reliable with a single SwiftUI `.fileImporter` (Anki) on this screen.
    private func presentBookImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epub, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Import Book"
        panel.prompt = "Import"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .leoBookImportPickedURL, object: url)
            }
        }
    }

    /// Non-sandboxed builds often get `false` from `startAccessingSecurityScopedResource()`; still copy if file is readable.
    @MainActor
    private func importBook(fromPickedURL url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent

        // True duplicate: same filename and file still on disk for that book.
        if let existing = books.first(where: { ($0.filePath as NSString).lastPathComponent == fileName }) {
            if FileManager.default.fileExists(atPath: existing.filePath) {
                selectedBook = existing
                return
            }
            if selectedBook?.id == existing.id { selectedBook = nil }
            modelContext.delete(existing)
            do { try modelContext.save() } catch {
                bookImportError = "Could not clear stale book entry: \(error.localizedDescription)"
                return
            }
        }

        do {
            try FileManager.default.createDirectory(at: runtime.booksDirectory, withIntermediateDirectories: true)
        } catch {
            bookImportError = "Could not create library folder: \(error.localizedDescription)"
            return
        }

        let destination = runtime.booksDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            bookImportError = "Could not copy file into library: \(error.localizedDescription)"
            return
        }

        let format: BookFormat = url.pathExtension.lowercased() == "pdf" ? .pdf : .epub
        let title = cleanTitle(from: url.deletingPathExtension().lastPathComponent)
        let book = Book(
            title: title,
            author: "",
            filePath: destination.path,
            format: format
        )
        modelContext.insert(book)
        do {
            try modelContext.save()
        } catch {
            bookImportError = "Could not save library: \(error.localizedDescription)"
            return
        }
        selectedBook = book
    }

    /// Reflows PDF text into a derived EPUB for Foliate (dictionary, FSRS, TTS). Keeps the original PDF path on the model.
    private func convertPDFBookToReflowEPUB(_ book: Book) {
        guard book.format == .pdf else { return }
        let pdfPath = book.filePath
        let pdfURL = URL(fileURLWithPath: pdfPath)
        guard FileManager.default.fileExists(atPath: pdfPath) else {
            pdfConvertError = "The PDF file is missing on disk."
            return
        }

        try? FileManager.default.createDirectory(at: runtime.booksDirectory, withIntermediateDirectories: true)
        let outURL = PDFConverter.uniqueSuggestedOutputURL(booksDirectory: runtime.booksDirectory, title: book.title)
        let bookRef = book

        isConvertingPDF = true
        // PDFKit + Vision OCR expect main-thread work; `Task.detached` often fails or hangs conversion.
        Task { @MainActor in
            defer { isConvertingPDF = false }
            do {
                try PDFConverter().convert(pdfURL: pdfURL, outputEPUBURL: outURL)
                bookRef.originalPDFPath = pdfPath
                bookRef.filePath = outURL.path
                bookRef.format = .epub
                bookRef.lastLocator = nil
                LocalServer.shared.registerBook(id: bookRef.id.uuidString, filePath: bookRef.filePath)
                try modelContext.save()
                selectedBook = bookRef
            } catch {
                pdfConvertError = error.localizedDescription
            }
        }
    }

    private func deleteBook(_ book: Book) {
        // Remove derived + source if we track it
        try? FileManager.default.removeItem(atPath: book.filePath)
        if let original = book.originalPDFPath, original != book.filePath {
            try? FileManager.default.removeItem(atPath: original)
        }
        // Deselect if selected
        if selectedBook == book {
            selectedBook = remainingSelectionCandidate(afterDeleting: book)
        }
        // Remove from database
        modelContext.delete(book)
        try? modelContext.save()
    }

    private func syncSelectionWithLibrary() {
        guard !books.isEmpty else {
            selectedBook = nil
            return
        }

        if let selectedBook,
           books.contains(where: { $0.id == selectedBook.id }) {
            return
        }

        selectedBook = preferredSelection
    }

    private var preferredSelection: Book? {
        books.max { lhs, rhs in
            effectiveOpenDate(for: lhs) < effectiveOpenDate(for: rhs)
        }
    }

    private func remainingSelectionCandidate(afterDeleting book: Book) -> Book? {
        books
            .filter { $0.id != book.id }
            .max { lhs, rhs in
                effectiveOpenDate(for: lhs) < effectiveOpenDate(for: rhs)
            }
    }

    private func effectiveOpenDate(for book: Book) -> Date {
        book.lastOpenedAt ?? book.addedAt
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
    let onConvertPDFToEPUB: (Book) -> Void
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
                .accessibilityIdentifier("leo.sidebar.review")

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
                .accessibilityIdentifier("leo.sidebar.vocabulary")
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
                    LibraryBookRow(
                        book: book,
                        metadataLine: bookMetadataLine(for: book),
                        isSelected: selectedBook?.id == book.id
                    )
                    .tag(book)
                    .accessibilityIdentifier("leo.library.book.\(book.id.uuidString)")
                    .contextMenu {
                        if book.format == .pdf {
                            Button {
                                onConvertPDFToEPUB(book)
                            } label: {
                                Label("Convert to EPUB for Reading…", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
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
        .accessibilityIdentifier("leo.library.sidebar")
        .toolbar {
            ToolbarItem {
                Button(action: onImport) {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("leo.sidebar.importToolbar")
                .help("Import Book (Cmd+O)")
            }
        }
        .navigationTitle("Leo")
    }

    private func bookMetadataLine(for book: Book) -> String {
        let formatLabel = book.format == .pdf ? "PDF" : "EPUB"
        if let lastOpenedAt = book.lastOpenedAt {
            let relative = RelativeDateTimeFormatter().localizedString(for: lastOpenedAt, relativeTo: Date())
            return "\(formatLabel) · Last opened \(relative)"
        }

        let added = RelativeDateTimeFormatter().localizedString(for: book.addedAt, relativeTo: Date())
        return "\(formatLabel) · Added \(added)"
    }
}

private struct LibraryBookRow: View {
    let book: Book
    let metadataLine: String
    let isSelected: Bool

    private var iconName: String {
        book.format == .pdf ? "doc.fill" : "book.closed.fill"
    }

    var body: some View {
        HStack {
            Image(systemName: iconName)
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
                Text(metadataLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
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
            .accessibilityIdentifier("leo.library.import")
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
        .accessibilityIdentifier("leo.library.empty")
    }
}
