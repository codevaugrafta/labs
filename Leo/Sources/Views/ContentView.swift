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
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: LeoRuntime
    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]
    @Query private var allSRSCards: [FSRSCard]
    @Query private var allVocabEntries: [VocabularyEntry]
    @AppStorage("leo.readingTheme") private var theme: ReadingTheme = .light
    /// When true, re-opens the last-read book in its own window on launch.
    @AppStorage("leo.resumeLastBookOnLaunch") private var resumeLastBookOnLaunch = false
    @State private var showAnkiImporter = false
    @State private var ankiImportMessage: String?
    @State private var showReview = false
    @State private var showVocabulary = false
    @State private var showStats = false
    @State private var pdfConvertError: String?
    @State private var bookImportError: String?
    @State private var pdfPreparationTasks: [UUID: Task<Void, Never>] = [:]
    @State private var coverBackfillRunning = false
    /// Tracks whether we have already opened the resume window this launch (prevents re-opening on subsequent @Query refreshes).
    @State private var didAutoResumeOnLaunch = false
    @State private var selectedBook: Book? = nil

    // MARK: - Theme

    /// Books that could get a cover thumbnail but do not have one yet, OR whose cached cover file has gone missing or is corrupt.
    private var pendingCoverExtractionCount: Int {
        books.filter {
            guard epubPathForCover($0) != nil else { return false }
            guard let path = $0.coverImagePath else { return true }
            if !FileManager.default.fileExists(atPath: path) { return true }
            return !EPUBCoverExtractor.isValidImageFile(at: path)
        }.count
    }

    private var dueSRSCount: Int {
        let now = Date()
        return allSRSCards.filter { $0.dueDate <= now }.count
    }

    private var themeBackground: Color { theme.leoContentBackground }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                books: books,
                selectedBook: Binding(
                    get: { nil },
                    set: { book in
                        guard let book else { return }
                        openWindow(value: book.id)
                    }
                ),
                onImport: presentBookImportPanel,
                onReview: { showReview = true },
                onVocabulary: { showVocabulary = true },
                onStats: { showStats = true },
                onDelete: deleteBook,
                onPreparePDFBookView: { preparePDFBookViewIfNeeded($0, userInitiated: true) }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            if books.isEmpty {
                EmptyLibraryView(onImport: presentBookImportPanel)
                    .background(themeBackground)
            } else {
                LibraryBookPickerView(
                    books: books,
                    continueBook: preferredSelection,
                    themeBackground: themeBackground,
                    onSelectBook: { book in openWindow(value: book.id) },
                    onImport: presentBookImportPanel,
                    dueCardCount: dueSRSCount,
                    totalVocabCount: allVocabEntries.filter({ $0.state != .unknown }).count
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("leo.library.root")
        .frame(minWidth: 800, minHeight: 600)
        // Bring this window to front when the reader's toolbar/FAB "Library" button is tapped.
        .onReceive(NotificationCenter.default.publisher(for: .leoShowLibrary)) { _ in
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoShowVocabulary)) { _ in
            showVocabulary = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoShowReview)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            showReview = true
        }
        .fileImporter(
            isPresented: $showAnkiImporter,
            allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleAnkiImport(result)
        }
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
            kickCoverBackfillChain()
            autoResumeLastBookIfNeeded()
        }
        .onChange(of: books.map(\.id)) { _, _ in
            migrateLegacyPDFBooksIfNeeded()
            kickCoverBackfillChain()
        }
        .modifier(ContentViewAlerts(
            ankiImportMessage: $ankiImportMessage,
            pdfConvertError: $pdfConvertError,
            bookImportError: $bookImportError
        ))
        .background(MainWindowChromeConfigurator(librarySidebarRevealed: true))
    }

    // MARK: - Launch auto-resume

    /// If `resumeLastBookOnLaunch` is on, open the most recently read book's reader window once per launch.
    private func autoResumeLastBookIfNeeded() {
        guard !didAutoResumeOnLaunch else { return }
        guard resumeLastBookOnLaunch else { return }
        guard let book = preferredSelection else { return }
        didAutoResumeOnLaunch = true
        openWindow(value: book.id)
    }

    // MARK: - Anki import

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

    // MARK: - UI test helpers

    /// UI tests only: `LEO_UI_TEST_BOOK_PATH` = absolute path to an EPUB/PDF to copy into the library and
    /// open in a reader window (no file picker).
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
            preparePDFBookViewIfNeeded(existing)
            openWindow(value: existing.id)
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
        if format == .epub {
            extractAndAssignCover(for: book)
        }
        preparePDFBookViewIfNeeded(book)
        openWindow(value: book.id)
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

    // MARK: - Import panel

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
                if existing.coverImagePath == nil {
                    extractAndAssignCover(for: existing)
                }
                preparePDFBookViewIfNeeded(existing)
                openWindow(value: existing.id)
                return
            }
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
        if format == .epub {
            extractAndAssignCover(for: book)
        }
        preparePDFBookViewIfNeeded(book)
        openWindow(value: book.id)
    }

    // MARK: - PDF preparation

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
                    try await PDFConverter().convert(pdfURL: pdfURL, outputEPUBURL: outputURL)
                }.value
                await MainActor.run {
                    book.derivedEPUBPath = outputURL.path
                    book.pdfPreparationStatus = .ready
                    book.pdfPreparationError = nil
                    LocalServer.shared.registerBook(id: book.id.uuidString, filePath: outputURL.path)
                    extractAndAssignCover(for: book)
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
            await MainActor.run { () -> Void in
                pdfPreparationTasks.removeValue(forKey: bookID)
            }
        }
    }

    // MARK: - Delete

    private func deleteBook(_ book: Book) {
        let bookTitle = book.title
        pdfPreparationTasks[book.id]?.cancel()
        pdfPreparationTasks.removeValue(forKey: book.id)

        EPUBCoverExtractor.removeCachedCoverFile(at: book.coverImagePath)

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
        // Remove from database
        modelContext.delete(book)
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] Failed to save after deleting '\(bookTitle)': \(error)")
        }
    }

    // MARK: - Library helpers

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

    // MARK: - EPUB covers

    private func epubPathForCover(_ book: Book) -> String? {
        switch book.format {
        case .epub:
            guard FileManager.default.fileExists(atPath: book.filePath) else { return nil }
            return book.filePath
        case .pdf:
            guard let derived = book.derivedEPUBPath,
                  FileManager.default.fileExists(atPath: derived) else { return nil }
            return derived
        }
    }

    private func extractAndAssignCover(for book: Book) {
        guard let epubPath = epubPathForCover(book) else { return }
        guard let newPath = EPUBCoverExtractor.extractCover(
            epubPath: epubPath,
            bookID: book.id,
            coversDirectory: runtime.coversDirectory
        ) else { return }
        applyExtractedCoverPath(newPath, for: book)
    }

    /// Writes cover path on the main actor after work has run off the main thread (backfill only).
    private func applyExtractedCoverPath(_ newPath: String, for book: Book) {
        if let old = book.coverImagePath, old != newPath {
            EPUBCoverExtractor.removeCachedCoverFile(at: old)
        }
        book.coverImagePath = newPath
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo] Failed to save cover path for '\(book.title)': \(error)")
        }
    }

    /// Runs EPUB extraction off the main actor so `unzip` + IO never blocks the UI; guards stale `Book` before saving.
    /// Also handles the case where `coverImagePath` was set in a prior session but the file has since been deleted or is corrupt.
    private func extractAndAssignCoverOffMainThread(for book: Book) async {
        guard let epubPath = epubPathForCover(book) else { return }
        // Allow re-extraction if the cached file no longer exists on disk or is not a valid image.
        let needsExtraction: Bool
        if let existingPath = book.coverImagePath {
            needsExtraction = !FileManager.default.fileExists(atPath: existingPath)
                || !EPUBCoverExtractor.isValidImageFile(at: existingPath)
        } else {
            needsExtraction = true
        }
        guard needsExtraction else { return }
        let bookID = book.id
        let coversDirectory = runtime.coversDirectory
        let newPath = await Task.detached(priority: .utility) {
            EPUBCoverExtractor.extractCover(
                epubPath: epubPath,
                bookID: bookID,
                coversDirectory: coversDirectory
            )
        }.value
        guard let newPath else { return }
        guard let resolved = books.first(where: { $0.id == bookID }) else { return }
        // Re-check on main actor: skip only if the file is now present and valid (a concurrent extraction may have won).
        let stillNeeded: Bool
        if let currentPath = resolved.coverImagePath {
            stillNeeded = !FileManager.default.fileExists(atPath: currentPath)
                || !EPUBCoverExtractor.isValidImageFile(at: currentPath)
        } else {
            stillNeeded = true
        }
        guard stillNeeded else { return }
        applyExtractedCoverPath(newPath, for: resolved)
    }

    /// Single bounded pass over books missing covers. Never recurses: if extraction fails, count stays flat and we do not spin forever.
    private func kickCoverBackfillChain() {
        guard !coverBackfillRunning else { return }
        guard pendingCoverExtractionCount > 0 else { return }
        coverBackfillRunning = true
        let snapshot = books.filter {
            guard epubPathForCover($0) != nil else { return false }
            guard let path = $0.coverImagePath else { return true }
            if !FileManager.default.fileExists(atPath: path) { return true }
            return !EPUBCoverExtractor.isValidImageFile(at: path)
        }
        Task { @MainActor in
            defer { coverBackfillRunning = false }
            for book in snapshot {
                await extractAndAssignCoverOffMainThread(for: book)
            }
        }
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

    private var dueCardCount: Int {
        dueCards.filter { $0.dueDate <= Date() }.count
    }

    var body: some View {
        List(selection: $selectedBook) {
            Section {
                Button(action: onReview) {
                    HStack {
                        Label("Review Cards", systemImage: "rectangle.stack")
                        Spacer()
                        if dueCardCount > 0 {
                            Text("\(dueCardCount)")
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Vocabulary", systemImage: "character.book.closed")
                            Spacer()
                        }
                        Text("\(vocabulary.filter({ $0.state != .unknown }).count) words · \(dueCardCount) due")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leo.sidebar.vocabulary")

                Button(action: onStats) {
                    Label("Reading Stats", systemImage: "chart.bar")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leo.sidebar.stats")
            }

            Section {
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
            } header: {
                Text("Library")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("leo.library.sidebar")
        .navigationTitle(Bundle.main.leoComposerSidebarTitle)
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
    @Bindable var book: Book
    let metadataLine: String
    let isSelected: Bool

    private var coverThumbnail: NSImage? {
        guard let path = book.coverImagePath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let coverThumbnail {
                    Image(nsImage: coverThumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: book.format == .epub ? "book.fill" : "doc.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 40)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Text(metadataLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptyLibraryView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "books.vertical")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tertiary)

                // Title + subtitle
                VStack(spacing: 8) {
                    Text("Your library is empty")
                        .font(.title2.weight(.semibold))
                    Text("Import an EPUB or PDF to start reading in Chinese")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Import Book…", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityIdentifier("leo.library.import")

                // Curated suggestion
                VStack(spacing: 10) {
                    Text("Looking for a starting point?")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 12) {
                        ForEach(EmptyLibraryView.suggestions, id: \.title) { book in
                            BookSuggestionChip(title: book.title, author: book.author, level: book.level)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("leo.library.empty")
    }

    private static let suggestions: [(title: String, author: String, level: String)] = [
        (title: "活着", author: "余华", level: "Intermediate"),
        (title: "骆驼祥子", author: "老舍", level: "Intermediate"),
        (title: "边城", author: "沈从文", level: "Advanced"),
    ]
}

private struct BookSuggestionChip: View {
    let title: String
    let author: String
    let level: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .serif))
            Text(author)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(level)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
