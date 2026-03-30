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
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var selectedBook: Book?
    @State private var showAnkiImporter = false
    @State private var ankiImportMessage: String?
    @State private var showReview = false
    @State private var showVocabulary = false
    @State private var showStats = false
    @State private var pdfConvertError: String?
    @State private var bookImportError: String?
    @State private var pdfPreparationTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - View Builder Sub-expressions

    @ViewBuilder
    private var sidebarContent: some View {
        LibrarySidebar(
            books: books,
            selectedBook: $selectedBook,
            onImport: presentBookImportPanel,
            onReview: { showReview = true },
            onVocabulary: { showVocabulary = true },
            onStats: { showStats = true },
            onDelete: deleteBook,
            onPreparePDFBookView: { preparePDFBookViewIfNeeded($0, userInitiated: true) }
        )
        // Liquid Glass styling on macOS 26+; fall back to ultra-thin material.
        .background {
            if #available(macOS 26, *) {
                // glassEffect is the macOS 26 Liquid Glass API
                Color.clear.glassEffect(.regular)
            } else {
                Color(nsColor: .windowBackgroundColor).opacity(0.85)
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let book = selectedBook {
                ReaderView(
                    book: book,
                    onPreparePDFBookView: { preparePDFBookViewIfNeeded($0) },
                    onRetryPDFBookView: { preparePDFBookViewIfNeeded($0, forceRetry: true, userInitiated: true) }
                )
                .id(book.id) // Force fresh view when switching books
                .ignoresSafeArea()
            } else {
                EmptyLibraryView(onImport: presentBookImportPanel)
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .accessibilityIdentifier("leo.root.split")
        // ⌃⌘S: toggle library sidebar overlay
        .onKeyPress(.init("s"), phases: .down) { press in
            guard press.modifiers.contains(.control) && press.modifiers.contains(.command) else {
                return .ignored
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
            return .handled
        }
        // Hover on left 20px edge reveals the sidebar
        .onContinuousHover { phase in
            if case .active(let location) = phase, location.x < 20 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    columnVisibility = .all
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoShowLibrary)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoShowVocabulary)) { _ in
            showVocabulary = true
        }
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
        .sheet(isPresented: $showStats) {
            ReadingStatsView()
                .frame(minWidth: 460, minHeight: 400)
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
            preparePDFBookViewIfNeeded(book, forceRetry: false, userInitiated: true)
        }
        // Stable task id so a @Query refresh does not cancel import mid-flight (UI tests).
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_BOOK_PATH"] ?? "") {
            await importEnvironmentTestBookIfNeeded()
        }
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_SEED_FSRS_CARD"] ?? "") {
            await seedUITestFSRSCardIfNeeded()
        }
        .onAppear {
            migrateLegacyPDFBooksIfNeeded()
            syncSelectionWithLibrary()
            preparePDFBookViewIfNeeded(selectedBook)
        }
        .onChange(of: books.map(\.id)) { _, _ in
            migrateLegacyPDFBooksIfNeeded()
            syncSelectionWithLibrary()
        }
        .onChange(of: selectedBook?.id) { _, _ in
            preparePDFBookViewIfNeeded(selectedBook)
        }
        .modifier(ContentViewAlerts(
            ankiImportMessage: $ankiImportMessage,
            pdfConvertError: $pdfConvertError,
            bookImportError: $bookImportError
        ))
    }

    private func handleAnkiImport(_ result: Result<[URL], Error>) {
        let message: String
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let importResult = try AnkiExporter().importDeck(from: url)
                let tracker = FamiliarityTracker(modelContext: modelContext)
                tracker.applyImportedStates(importResult.wordStates)
                message = "Imported \(importResult.totalCards) cards into vocabulary familiarity."
            } catch {
                message = error.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
        ankiImportMessage = message
        // Also notify Settings tab (if open) so it can show the result inline.
        NotificationCenter.default.post(name: .leoAnkiImportResult, object: message)
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
        if let existing = existingBook(matchingLibraryFilename: fileName) {
            selectedBook = existing
            preparePDFBookViewIfNeeded(existing)
            return
        }
        let destination = runtime.booksDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Pre-copy cleanup — non-critical; copy below will fail with its own error if needed
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
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] UI test: failed to save book '\(title)': \(error)")
        }
        selectedBook = book
        preparePDFBookViewIfNeeded(book)
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
            do {
                try modelContext.save()
            } catch {
                NSLog("[Leo] UI test: failed to update FSRS card for '\(word)': \(error)")
            }
            return
        }
        let card = FSRSCard(word: word)
        card.dueDate = Date(timeIntervalSince1970: 0)
        card.state = .review
        card.stability = 2.5
        card.difficulty = 5.0
        card.reviewCount = 1
        modelContext.insert(card)
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] UI test: failed to save FSRS card for '\(word)': \(error)")
        }
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
        if let existing = existingBook(matchingLibraryFilename: fileName) {
            if FileManager.default.fileExists(atPath: existing.filePath) {
                selectedBook = existing
                preparePDFBookViewIfNeeded(existing)
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
            // Pre-copy cleanup — non-critical; copy below will fail with its own error if needed
            do {
                try FileManager.default.removeItem(at: destination)
            } catch {
                NSLog("[Leo] Failed to remove existing file at destination before copy: \(error)")
            }
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
        preparePDFBookViewIfNeeded(book)
    }

    /// Reflows PDF text into a derived EPUB for Foliate (dictionary, FSRS, TTS) without replacing the source PDF.
    private func preparePDFBookViewIfNeeded(
        _ book: Book?,
        forceRetry: Bool = false,
        userInitiated: Bool = false
    ) {
        guard let book else { return }

        if book.migrateLegacyConvertedPDFIfNeeded() {
            do {
                try modelContext.save()
            } catch {
                NSLog("[Leo] Failed to save legacy PDF migration for '\(book.title)': \(error)")
            }
        }

        guard book.format == .pdf else { return }
        guard pdfPreparationTasks[book.id] == nil else { return }

        if let derivedEPUBPath = book.derivedEPUBPath,
           !FileManager.default.fileExists(atPath: derivedEPUBPath) {
            book.derivedEPUBPath = nil
            book.pdfPreparationStatus = .idle
            book.pdfPreparationError = nil
        }

        if book.pdfPreparationStatus == .preparing && !forceRetry {
            NSLog("[Leo] Resuming incomplete Book View preparation for '\(book.title)'")
        }

        if book.pdfPreparationStatus == .failed && !forceRetry && !userInitiated {
            return
        }

        if let derivedEPUBPath = book.derivedEPUBPath,
           FileManager.default.fileExists(atPath: derivedEPUBPath),
           !forceRetry {
            if book.pdfPreparationStatus != .ready || book.pdfPreparationError != nil {
                book.pdfPreparationStatus = .ready
                book.pdfPreparationError = nil
                do {
                    try modelContext.save()
                } catch {
                    NSLog("[Leo] Failed to save ready Book View state for '\(book.title)': \(error)")
                }
            }
            return
        }

        guard let pdfPath = book.sourcePDFPath,
              FileManager.default.fileExists(atPath: pdfPath) else {
            let message = "The source PDF is missing on disk."
            book.pdfPreparationStatus = .failed
            book.pdfPreparationError = message
            if userInitiated {
                pdfConvertError = message
            }
            do {
                try modelContext.save()
            } catch {
                NSLog("[Leo] Failed to save missing PDF error for '\(book.title)': \(error)")
            }
            return
        }

        try? FileManager.default.createDirectory(at: runtime.booksDirectory, withIntermediateDirectories: true)
        let outputURL: URL
        if let existing = book.derivedEPUBPath {
            outputURL = URL(fileURLWithPath: existing)
        } else {
            outputURL = PDFConverter.uniqueSuggestedOutputURL(booksDirectory: runtime.booksDirectory, title: book.title)
        }

        book.pdfPreparationStatus = .preparing
        book.pdfPreparationError = nil
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] Failed to save preparing state for '\(book.title)': \(error)")
        }

        let bookID = book.id
        let pdfURL = URL(fileURLWithPath: pdfPath)
        pdfPreparationTasks[bookID] = Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try PDFConverter().convert(pdfURL: pdfURL, outputEPUBURL: outputURL)
                }.value
                await MainActor.run {
                    book.derivedEPUBPath = outputURL.path
                    book.pdfPreparationStatus = .ready
                    book.pdfPreparationError = nil
                    LocalServer.shared.registerBook(id: book.id.uuidString, filePath: outputURL.path)
                    do {
                        try modelContext.save()
                    } catch {
                        NSLog("[Leo] Failed to save Book View ready state for '\(book.title)': \(error)")
                    }
                }
            } catch {
                await MainActor.run {
                    book.pdfPreparationStatus = .failed
                    book.pdfPreparationError = error.localizedDescription
                    if forceRetry && userInitiated {
                        pdfConvertError = error.localizedDescription
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        NSLog("[Leo] Failed to save Book View failure for '\(book.title)': \(error)")
                    }
                }
            }
            await MainActor.run {
                pdfPreparationTasks.removeValue(forKey: bookID)
            }
        }
    }

    private func deleteBook(_ book: Book) {
        let bookTitle = book.title
        pdfPreparationTasks[book.id]?.cancel()
        pdfPreparationTasks.removeValue(forKey: book.id)

        if FileManager.default.fileExists(atPath: book.filePath) {
            do {
                try FileManager.default.removeItem(atPath: book.filePath)
            } catch {
                NSLog("[Leo] Could not remove book file for '\(bookTitle)': \(error)")
            }
        }
        if let derivedEPUBPath = book.derivedEPUBPath, derivedEPUBPath != book.filePath {
            do {
                try FileManager.default.removeItem(atPath: derivedEPUBPath)
            } catch {
                NSLog("[Leo] Could not remove derived Book View EPUB for '\(bookTitle)': \(error)")
            }
        }
        if let original = book.originalPDFPath, original != book.filePath {
            do {
                try FileManager.default.removeItem(atPath: original)
            } catch {
                NSLog("[Leo] Could not remove legacy original PDF for '\(bookTitle)': \(error)")
            }
        }
        // Deselect if selected
        if selectedBook == book {
            selectedBook = remainingSelectionCandidate(afterDeleting: book)
        }
        // Remove from database
        modelContext.delete(book)
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] Failed to save after deleting '\(bookTitle)': \(error)")
        }
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

    private func migrateLegacyPDFBooksIfNeeded() {
        var didMigrate = false
        for book in books where book.migrateLegacyConvertedPDFIfNeeded() {
            didMigrate = true
        }

        guard didMigrate else { return }
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] Failed to save legacy PDF migrations: \(error)")
        }
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

    private func existingBook(matchingLibraryFilename fileName: String) -> Book? {
        let normalizedFileName = (fileName as NSString).lastPathComponent
        let inMemoryMatches = books.filter { ($0.filePath as NSString).lastPathComponent == normalizedFileName }
        if let existing = inMemoryMatches.max(by: { effectiveOpenDate(for: $0) < effectiveOpenDate(for: $1) }) {
            return existing
        }

        let descriptor = FetchDescriptor<Book>()
        guard let persisted = try? modelContext.fetch(descriptor) else {
            return nil
        }

        let persistedMatches = persisted.filter { ($0.filePath as NSString).lastPathComponent == normalizedFileName }
        return persistedMatches.max(by: { effectiveOpenDate(for: $0) < effectiveOpenDate(for: $1) })
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

// MARK: - Alerts ViewModifier

/// Extracted so the type checker doesn't time out on the long ContentView modifier chain.
private struct ContentViewAlerts: ViewModifier {
    @Binding var ankiImportMessage: String?
    @Binding var pdfConvertError: String?
    @Binding var bookImportError: String?

    func body(content: Content) -> some View {
        let ankiBinding = Binding<Bool>(
            get: { ankiImportMessage != nil },
            set: { if !$0 { ankiImportMessage = nil } }
        )
        let pdfBinding = Binding<Bool>(
            get: { pdfConvertError != nil },
            set: { if !$0 { pdfConvertError = nil } }
        )
        let importBinding = Binding<Bool>(
            get: { bookImportError != nil },
            set: { if !$0 { bookImportError = nil } }
        )
        content
            .alert("Anki import", isPresented: ankiBinding) {
                Button("OK", role: .cancel) { ankiImportMessage = nil }
            } message: {
                if let msg = ankiImportMessage { Text(msg) }
            }
            .alert("Convert PDF", isPresented: pdfBinding) {
                Button("OK", role: .cancel) { pdfConvertError = nil }
            } message: {
                if let msg = pdfConvertError { Text(msg) }
            }
            .alert("Import Book", isPresented: importBinding) {
                Button("OK", role: .cancel) { bookImportError = nil }
            } message: {
                if let msg = bookImportError { Text(msg) }
            }
    }
}

struct LibrarySidebar: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    let onImport: () -> Void
    let onReview: () -> Void
    let onVocabulary: () -> Void
    let onStats: () -> Void
    let onDelete: (Book) -> Void
    let onPreparePDFBookView: (Book) -> Void
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

                Button(action: onStats) {
                    Label("Reading Stats", systemImage: "chart.bar")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leo.sidebar.stats")
            }

            Section("Vocabulary") {
                let due = dueCards.filter { $0.dueDate <= Date() }.count
                Text("\(vocabulary.count) words · \(due) due")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }

            Section("Library") {
                Button(action: onImport) {
                    Label("Import Book", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.vertical, 4)

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
                                onPreparePDFBookView(book)
                            } label: {
                                Label(book.hasPreparedBookView ? "Refresh Book View" : "Prepare Book View", systemImage: "arrow.triangle.2.circlepath")
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: book.format == .epub ? "book.fill" : "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(metadataLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
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
