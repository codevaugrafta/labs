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
    @State private var showLibraryPanel = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    @State private var showAnkiImporter = false
    @State private var ankiImportMessage: String?
    @State private var showReview = false
    @State private var showVocabulary = false
    @State private var uiTestLookupSummary: String?
    @State private var pdfConvertError: String?
    @State private var bookImportError: String?
    @State private var pdfPreparationTasks: [UUID: Task<Void, Never>] = [:]

    var body: some View {
        ZStack(alignment: .topLeading) {
            DigitalVellumBackground()

            HStack(spacing: 0) {
                Spacer(minLength: libraryPanelVisible ? 240 : 0)

                Group {
                    if let book = selectedBook {
                        ReaderView(
                            book: book,
                            onPreparePDFBookView: { preparePDFBookViewIfNeeded($0) },
                            onRetryPDFBookView: { preparePDFBookViewIfNeeded($0, forceRetry: true, userInitiated: true) }
                        )
                        .id(book.id) // Force fresh view when switching books
                    } else {
                        EmptyLibraryView(onImport: presentBookImportPanel)
                    }
                }
                .frame(maxWidth: selectedBook == nil ? 720 : 1120, maxHeight: .infinity)
                .background(
                    Rectangle()
                        .fill(Color(nsColor: .textBackgroundColor).opacity(selectedBook == nil ? 0.35 : 0.84))
                        .shadow(color: .black.opacity(0.06), radius: 48, x: 0, y: 26)
                )
                .padding(.leading, libraryPanelVisible ? 48 : 72)
                .padding(.trailing, 72)
                .padding(.top, 92)
                .padding(.bottom, 40)

                Spacer(minLength: 0)
            }

            if libraryPanelVisible {
                LibrarySidebar(
                    books: books,
                    selectedBook: $selectedBook,
                    onImport: presentBookImportPanel,
                    onReview: { showReview = true },
                    onVocabulary: { showVocabulary = true },
                    onDelete: deleteBook,
                    onPreparePDFBookView: { preparePDFBookViewIfNeeded($0, userInitiated: true) }
                )
                .padding(.leading, 24)
                .padding(.top, 28)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(2)
            }

            DigitalVellumTopBar(
                selectedBook: selectedBook,
                libraryPanelVisible: libraryPanelVisible,
                onToggleLibrary: {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showLibraryPanel.toggle()
                    }
                },
                onImport: presentBookImportPanel,
                onReview: { showReview = true },
                onVocabulary: { showVocabulary = true }
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .zIndex(3)

            if isUITesting {
                DigitalVellumUITestPanel(
                    lookupSummary: uiTestLookupSummary,
                    onReview: { showReview = true },
                    onVocabulary: { showVocabulary = true }
                )
                .padding(.leading, 24)
                .padding(.top, 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(4)
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
            preparePDFBookViewIfNeeded(book, forceRetry: false, userInitiated: true)
        }
        // Stable task id so a @Query refresh does not cancel import mid-flight (UI tests).
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_BOOK_PATH"] ?? "") {
            await importEnvironmentTestBookIfNeeded()
        }
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_SEED_FSRS_CARD"] ?? "") {
            await seedUITestFSRSCardIfNeeded()
        }
        .task(id: ProcessInfo.processInfo.environment["LEO_UI_TEST_LOOKUP_WORD"] ?? "") {
            await refreshUITestLookupSummaryIfNeeded()
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
            guard selectedBook != nil,
                  ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                showLibraryPanel = false
            }
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
    }

    private var libraryPanelVisible: Bool {
        showLibraryPanel || selectedBook == nil
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.environment["LEO_UI_TEST_DATA_DIR"] != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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

    @MainActor
    private func refreshUITestLookupSummaryIfNeeded() async {
        guard ProcessInfo.processInfo.environment["LEO_UI_TEST_SHOW_LOOKUP"] == "1" else {
            uiTestLookupSummary = nil
            return
        }

        let word = ProcessInfo.processInfo.environment["LEO_UI_TEST_LOOKUP_WORD"] ?? "你好"
        let summary = await Task.detached(priority: .userInitiated) { () -> String in
            DictionaryEngine.shared.load()
            let entries = DictionaryEngine.shared.lookup(word)
            let definition = entries.first?.definitions.first ?? ""
            return "\(word): \(String(definition.prefix(120)))"
        }.value
        uiTestLookupSummary = summary
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
        pdfPreparationTasks[bookID] = Task { @MainActor in
            defer { pdfPreparationTasks.removeValue(forKey: bookID) }
            do {
                _ = try PDFConverter().convert(pdfURL: pdfURL, outputEPUBURL: outputURL)
                book.derivedEPUBPath = outputURL.path
                book.pdfPreparationStatus = .ready
                book.pdfPreparationError = nil
                LocalServer.shared.registerBook(id: book.id.uuidString, filePath: outputURL.path)
                try modelContext.save()
            } catch {
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

struct LibrarySidebar: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    let onImport: () -> Void
    let onReview: () -> Void
    let onVocabulary: () -> Void
    let onDelete: (Book) -> Void
    let onPreparePDFBookView: (Book) -> Void
    @Query private var vocabulary: [VocabularyEntry]
    @Query private var dueCards: [FSRSCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LEO")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .tracking(3)
                .foregroundStyle(.secondary)

            Text("Reading space, not dashboard.")
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                sidebarActionButton(
                    title: "Review",
                    value: dueCount > 0 ? "\(dueCount)" : nil,
                    systemImage: "rectangle.stack",
                    accessibilityID: "leo.sidebar.review",
                    action: onReview
                )
                sidebarActionButton(
                    title: "Vocabulary",
                    value: "\(vocabulary.count)",
                    systemImage: "character.book.closed",
                    accessibilityID: "leo.sidebar.vocabulary",
                    action: onVocabulary
                )
            }

            HStack(spacing: 12) {
                metricBlock(value: "\(knownCount)", label: "Known", tint: .green)
                metricBlock(value: "\(learningCount)", label: "Learning", tint: .orange)
                metricBlock(value: "\(newCount)", label: "New", tint: .red)
            }

            Button(action: onImport) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Import Book")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("leo.sidebar.importPanel")

            VStack(alignment: .leading, spacing: 8) {
                Text("Library")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(books) { book in
                            bookRowButton(for: book)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 34, x: 0, y: 20)
        .accessibilityIdentifier("leo.library.sidebar")
    }

    private var dueCount: Int {
        dueCards.filter { $0.dueDate <= Date() }.count
    }

    private var knownCount: Int {
        vocabulary.filter { $0.state == .known }.count
    }

    private var learningCount: Int {
        vocabulary.filter { $0.state == .learning || $0.state == .familiar }.count
    }

    private var newCount: Int {
        vocabulary.filter { $0.state == .unknown }.count
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

    @ViewBuilder
    private func sidebarActionButton(
        title: String,
        value: String?,
        systemImage: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private func metricBlock(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bookRowButton(for book: Book) -> some View {
        let isSelected = selectedBook?.id == book.id
        let row = LibraryBookRow(
            book: book,
            metadataLine: bookMetadataLine(for: book),
            isSelected: isSelected
        )

        Button {
            selectedBook = book
        } label: {
            row
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Rectangle()
                        .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 18) {
            Text("LEO")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .tracking(3)
                .foregroundStyle(.secondary)

            Text("Open a book to start reading")
                .font(.system(size: 34, weight: .medium, design: .serif))

            Text("Bring an EPUB or PDF into the library, then let the text take over the window.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440, alignment: .leading)

            Button("Import Book") {
                onImport()
            }
            .accessibilityIdentifier("leo.library.import")
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(56)
        .accessibilityIdentifier("leo.library.empty")
    }
}

private struct DigitalVellumBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.94, blue: 0.91),
                    Color(red: 0.985, green: 0.985, blue: 0.975),
                    Color.white,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 720, height: 720)
                .blur(radius: 120)
                .offset(x: 420, y: -260)
        }
        .ignoresSafeArea()
    }
}

private struct DigitalVellumTopBar: View {
    let selectedBook: Book?
    let libraryPanelVisible: Bool
    let onToggleLibrary: () -> Void
    let onImport: () -> Void
    let onReview: () -> Void
    let onVocabulary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            chromeButton(
                title: libraryPanelVisible ? "Hide Library" : "Library",
                systemImage: "sidebar.leading",
                accessibilityID: "leo.shell.libraryToggle",
                action: onToggleLibrary
            )
            chromeButton(
                title: "Review",
                systemImage: "rectangle.stack",
                accessibilityID: "leo.shell.review",
                action: onReview
            )
            chromeButton(
                title: "Vocabulary",
                systemImage: "character.book.closed",
                accessibilityID: "leo.shell.vocabulary",
                action: onVocabulary
            )
            chromeButton(
                title: "Import",
                systemImage: "plus",
                accessibilityID: "leo.shell.import",
                action: onImport
            )

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 2) {
                Text(selectedBook?.title ?? "Library")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .lineLimit(1)
                Text(selectedBook == nil ? "Center-stage reading canvas" : "Reading surface")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .shadow(color: .black.opacity(0.05), radius: 28, x: 0, y: 18)
    }

    @ViewBuilder
    private func chromeButton(
        title: String,
        systemImage: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct DigitalVellumUITestPanel: View {
    let lookupSummary: String?
    let onReview: () -> Void
    let onVocabulary: () -> Void

    var body: some View {
        List {
            Section("Harness") {
                Button("Review Cards", action: onReview)
                    .accessibilityIdentifier("leo.sidebar.review")

                Button("Vocabulary", action: onVocabulary)
                    .accessibilityIdentifier("leo.sidebar.vocabulary")
            }

            if let lookupSummary {
                Section("Reader") {
                    Text(lookupSummary)
                        .accessibilityIdentifier("leo.reader.dictionarySmoke")
                        .accessibilityLabel(lookupSummary)
                        .accessibilityValue(lookupSummary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 240, height: lookupSummary == nil ? 170 : 250)
    }
}
