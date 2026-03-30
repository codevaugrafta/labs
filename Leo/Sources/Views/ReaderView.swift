import SwiftUI
import WebKit

// Lightweight reference-type bridge so ReaderView can call back into the WKWebView
// coordinator without needing to hold a strong retain cycle or use a global.
final class ReaderCoordinatorBridge: ObservableObject {
    weak var coordinator: FoliateReaderView.Coordinator?
}

struct ReaderView: View {
    let book: Book
    let onPreparePDFBookView: (Book) -> Void
    let onRetryPDFBookView: (Book) -> Void
    @State private var theme: ReadingTheme = .light
    @State private var readerFailureMessage: String?
    @State private var familiarityTracker: FamiliarityTracker?
    @State private var lastReadAloudSnippet: String = ""
    @StateObject private var sessionEngine = ReadingSessionEngine()
    @StateObject private var ttsEngine = TTSEngine()
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var runtime: LeoRuntime

    @AppStorage("leo.fontSize") private var readingFontSize = 18.0
    @AppStorage("leo.lineHeight") private var readingLineHeight = 1.7
    @AppStorage("leo.showPinyin") private var readingShowPinyin = false
    @AppStorage("leo.showHighlights") private var readingShowHighlights = true
    @AppStorage("leo.textDirection") private var readingTextDirection = "horizontal"
    @AppStorage("leo.pageStyle") private var readingPageStyle = "clean"
    @AppStorage("leo.pdf.layoutMode") private var storedPDFLayoutMode = PDFPageLayoutMode.continuous.rawValue
    @AppStorage("leo.pdf.scrollAxis") private var storedPDFScrollAxis = PDFScrollAxis.vertical.rawValue
    @AppStorage("leo.pdf.fitPolicy") private var storedPDFFitPolicy = PDFPageFitPolicy.fitPage.rawValue
    @AppStorage("leo.pdf.explainerDismissed") private var pdfExplainerDismissed = false
    @State private var showReadingChromePopover = false
    @State private var showPDFLayoutPopover = false
    @State private var chromeVisible = true
    @State private var chromeHideTimer: Timer?
    @State private var pdfLayoutMode: PDFPageLayoutMode = .continuous
    @State private var pdfScrollAxis: PDFScrollAxis = .vertical
    @State private var pdfFitPolicy: PDFPageFitPolicy = .fitPage
    @State private var activePDFMode: PDFReadingMode = .originalPDF

    // Reading progress (0–1) updated from foliate relocate events
    @State private var readingFraction: Double = 0

    // TOC state
    @State private var showTOCPanel = false
    @State private var tocItems: [TOCItem] = []
    @StateObject private var coordinatorBridge = ReaderCoordinatorBridge()

    // Search state
    @State private var showSearchBar = false
    @State private var searchQuery = ""
    @FocusState private var searchFieldFocused: Bool

    /// UI tests: when `LEO_UI_TEST_SHOW_LOOKUP` is set, surface dictionary text for AX (not from WKWebView).
    @State private var uiTestDictionarySummary: String?
    @State private var uiTestLocatorSummary: String?
    @State private var uiTestRelocationCount = 0
    @State private var uiTestPDFPageSummary: String?

    // MARK: - View Builder Sub-expressions

    @ViewBuilder
    private var readerContent: some View {
        if showsOriginalPDF {
            PDFReaderView(
                filePath: book.filePath,
                initialPageIndex: book.safePdfLastPageIndex,
                layoutMode: pdfLayoutMode,
                scrollAxis: pdfScrollAxis,
                fitPolicy: pdfFitPolicy,
                onPageChanged: persistPDFPage
            )
        } else if let failureMessage = activeFailureMessage {
            ReaderFailureView(
                message: failureMessage,
                onRetry: retryReader
            )
        } else if let foliateFilePath = currentFoliateFilePath {
            FoliateReaderView(
                bookFilePath: foliateFilePath,
                bookId: book.id.uuidString,
                theme: theme,
                initialLocator: book.locator,
                readingChrome: LeoReadingChromePreferences(
                    fontSize: readingFontSize,
                    lineHeight: readingLineHeight,
                    textDirection: readingTextDirection,
                    showPinyin: readingShowPinyin,
                    showHighlights: readingShowHighlights,
                    pageStyle: readingPageStyle
                ),
                onRelocate: persistLocation,
                onLoadSuccess: handleReaderLoadSuccess,
                onLoadError: handleReaderLoadError,
                onWordTapped: handleWordTap,
                onPopupAction: handlePopupAction,
                familiarityForWord: { word in
                    familiarityTracker?.state(for: word) ?? .unknown
                },
                hasReviewCardForWord: { word in
                    let fsrs = FSRSEngine(modelContext: modelContext)
                    return fsrs.card(for: word) != nil
                },
                onTOCLoaded: { items in
                    tocItems = items
                },
                onCoordinatorReady: { coord in
                    coordinatorBridge.coordinator = coord
                }
            )
        } else {
            ReaderFailureView(
                message: book.pdfPreparationError ?? "Leo couldn’t open Book View for this PDF yet.",
                onRetry: { onRetryPDFBookView(book) }
            )
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if usesFoliateReader && readingFraction > 0 {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: geo.size.width * readingFraction, height: 2)
                    .animation(.easeOut(duration: 0.3), value: readingFraction)
            }
            .frame(height: 2)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var uiTestProbes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = uiTestDictionarySummary, usesFoliateReader {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("leo.reader.dictionarySmoke")
                    .accessibilityLabel(summary)
                    .accessibilityValue(summary)
            }

            if let locatorSummary = uiTestLocatorSummary, usesFoliateReader {
                Text(locatorSummary)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .id(locatorSummary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("leo.reader.locatorProbe")
                    .accessibilityLabel(locatorSummary)
                    .accessibilityValue(locatorSummary)
            }

            if let pdfPageSummary = uiTestPDFPageSummary, showsOriginalPDF {
                Text(pdfPageSummary)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("leo.reader.pdfPageProbe")
                    .accessibilityLabel(pdfPageSummary)
                    .accessibilityValue(pdfPageSummary)
            }
        }
        .padding(.top, 4)
        .zIndex(10_000)
    }

    @ViewBuilder
    private var searchBarOverlay: some View {
        if showSearchBar && usesFoliateReader {
            SearchBarView(
                query: $searchQuery,
                isFocused: $searchFieldFocused,
                onSubmit: {
                    let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if q.isEmpty {
                        coordinatorBridge.coordinator?.clearBookSearch()
                    } else {
                        coordinatorBridge.coordinator?.searchInBook(q)
                    }
                },
                onClear: {
                    searchQuery = ""
                    coordinatorBridge.coordinator?.clearBookSearch()
                },
                onDismiss: {
                    showSearchBar = false
                    searchQuery = ""
                    coordinatorBridge.coordinator?.clearBookSearch()
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(20_000)
        }
    }

    @ViewBuilder
    private var floatingToolbar: some View {
        if chromeVisible {
            HStack(spacing: 20) {
                if usesFoliateReader {
                    Picker("", selection: $theme) {
                        ForEach(ReadingTheme.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    .accessibilityIdentifier("leo.toolbar.theme")
                }

                Spacer()

                if usesFoliateReader {
                    Button {
                        coordinatorBridge.coordinator?.requestTOC()
                        showTOCPanel.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("leo.toolbar.toc")
                    .popover(isPresented: $showTOCPanel, arrowEdge: .bottom) {
                        TOCPanelView(items: tocItems) { href in
                            showTOCPanel = false
                            coordinatorBridge.coordinator?.goToTocItem(href)
                        }
                    }

                    Button {
                        showReadingChromePopover.toggle()
                    } label: {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("leo.toolbar.readingLayout")
                    .popover(isPresented: $showReadingChromePopover, arrowEdge: .bottom) {
                        ReadingPreferencesForm(
                            fontSize: $readingFontSize,
                            lineHeight: $readingLineHeight,
                            textDirection: $readingTextDirection,
                            showPinyin: $readingShowPinyin,
                            showHighlights: $readingShowHighlights,
                            pageStyle: $readingPageStyle
                        )
                        .padding()
                        .frame(minWidth: 320, minHeight: 280)
                    }
                }

                overflowMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.top, 6)
            .padding(.horizontal, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(15_000)
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            if usesFoliateReader {
                if ttsEngine.isPlaying {
                    Button { ttsEngine.pause() } label: {
                        Label("Pause Reading Aloud", systemImage: "pause.fill")
                    }
                    Button { ttsEngine.stop() } label: {
                        Label("Stop Reading Aloud", systemImage: "stop.fill")
                    }
                } else {
                    Button { Task { await playReadAloud() } } label: {
                        Label("Read Aloud", systemImage: "speaker.wave.2")
                    }
                    .disabled(lastReadAloudSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()

                if sessionEngine.isActive {
                    Button { sessionEngine.stopSession() } label: {
                        Label("Stop Session (\(sessionEngine.formattedTime))", systemImage: "stop.circle")
                    }
                    .accessibilityIdentifier("leo.reader.sessionActive")
                } else {
                    Button { sessionEngine.startSession(bookTitle: book.title) } label: {
                        Label("Start Reading Session", systemImage: "play.circle")
                    }
                }
            } else if book.format == .pdf {
                Button {
                    showPDFLayoutPopover.toggle()
                } label: {
                    Label("PDF Layout", systemImage: "rectangle.split.3x1")
                }
                .accessibilityIdentifier("leo.toolbar.pdfLayout")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
        .frame(width: 24)
        .accessibilityIdentifier("leo.toolbar.overflow")
        .popover(isPresented: $showPDFLayoutPopover, arrowEdge: .bottom) {
            PDFLayoutPreferencesForm(
                layoutMode: $pdfLayoutMode,
                scrollAxis: $pdfScrollAxis,
                fitPolicy: $pdfFitPolicy
            )
            .padding()
            .frame(minWidth: 360, minHeight: 240)
        }
    }

    @ViewBuilder
    private var floatingActionButtons: some View {
        if chromeVisible {
            FloatingActionButtons(
                onLibrary: {
                    NotificationCenter.default.post(name: .leoShowLibrary, object: nil)
                },
                onVocabulary: {
                    NotificationCenter.default.post(name: .leoShowVocabulary, object: nil)
                },
                onSettings: {
                    showReadingChromePopover.toggle()
                }
            )
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottomTrailing)))
            .zIndex(14_000)
        }
    }

    // MARK: - Theme Background

    private var themeBackground: Color {
        switch theme {
        case .light: Color(red: 0.984, green: 0.984, blue: 0.984)  // #FBFBFB
        case .sepia: Color(red: 0.973, green: 0.945, blue: 0.890)  // #F8F1E3
        case .dark:  Color(red: 0.071, green: 0.071, blue: 0.071)  // #121212
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            readerContent
                .ignoresSafeArea(.all, edges: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(themeBackground)
        .overlay(alignment: .bottom) { progressBar }
        .overlay(alignment: .topLeading) { uiTestProbes }
        .overlay(alignment: .top) { searchBarOverlay }
        .animation(.easeInOut(duration: 0.18), value: showSearchBar)
        .overlay(alignment: .top) { floatingToolbar }
        .overlay(alignment: .bottomTrailing) { floatingActionButtons }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: chromeVisible)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if location.y < 60 {
                    withAnimation { chromeVisible = true }
                    resetChromeTimer()
                }
            case .ended:
                resetChromeTimer()
            }
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .onAppear { resetChromeTimer() }
        .task(id: book.id) {
            // Single load pass — concurrent load() calls corrupt DictionaryEngine's `loaded` flag.
            await Task.detached(priority: .userInitiated) {
                DictionaryEngine.shared.load()
                FrequencyEngine.shared.load()
                GrammarEngine.shared.load()
                DecompositionEngine.shared.load()
            }.value
            familiarityTracker = FamiliarityTracker(modelContext: modelContext)
            sessionEngine.configure(modelContext: modelContext)
            configurePDFPresentationFromStoredState()
            markBookOpened()
            if book.format == .pdf {
                onPreparePDFBookView(book)
            }
            refreshUITestState()
        }
        .onChange(of: activePDFMode) { _, newValue in
            guard book.format == .pdf else { return }
            book.preferredPDFMode = newValue
            saveBookState(context: "preferred PDF mode")
            refreshUITestState()
        }
        .onChange(of: pdfLayoutMode) { _, newValue in
            storedPDFLayoutMode = newValue.rawValue
        }
        .onChange(of: pdfScrollAxis) { _, newValue in
            storedPDFScrollAxis = newValue.rawValue
        }
        .onChange(of: pdfFitPolicy) { _, newValue in
            storedPDFFitPolicy = newValue.rawValue
            guard book.format == .pdf else { return }
            book.pdfFitPolicy = newValue
            saveBookState(context: "PDF fit policy")
            refreshUITestState()
        }
        .onChange(of: book.pdfPreparationStatusRaw) { _, _ in
            if bookViewReady {
                // Auto-switch to Book View once it's ready (no user toggle needed)
                activePDFMode = .bookView
            } else if !bookViewReady && activePDFMode == .bookView {
                activePDFMode = .originalPDF
            }
            refreshUITestState()
        }
        .onChange(of: ttsEngine.currentWordRange) { _, newRange in
            guard usesFoliateReader else { return }
            if let range = newRange {
                coordinatorBridge.coordinator?.highlightSpeakingRange(
                    text: lastReadAloudSnippet,
                    range: range
                )
            } else {
                coordinatorBridge.coordinator?.clearSpeakingHighlight()
            }
        }
        .onChange(of: ttsEngine.isPlaying) { _, playing in
            guard usesFoliateReader, !playing else { return }
            coordinatorBridge.coordinator?.clearSpeakingHighlight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoPlayTTS)) { note in
            guard let word = note.object as? String, !word.isEmpty else { return }
            Task { await playWordTTS(word: word) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoToggleTOC)) { _ in
            guard usesFoliateReader else { return }
            coordinatorBridge.coordinator?.requestTOC()
            showTOCPanel.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoTogglePinyin)) { _ in
            readingShowPinyin.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoToggleSearch)) { _ in
            guard usesFoliateReader else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                showSearchBar.toggle()
            }
            if showSearchBar {
                searchFieldFocused = true
            } else {
                searchQuery = ""
                coordinatorBridge.coordinator?.clearBookSearch()
            }
        }
    }

    private var activeFailureMessage: String? {
        readerFailureMessage ?? runtime.readerServerState.failureMessage
    }

    private var currentFoliateFilePath: String? {
        if book.format == .pdf {
            return bookViewReady && activePDFMode == .bookView ? book.bookViewPath : nil
        }
        return book.filePath
    }

    private var bookViewReady: Bool {
        guard book.format == .pdf,
              book.pdfPreparationStatus == .ready,
              let path = book.bookViewPath else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    private var showsOriginalPDF: Bool {
        book.format == .pdf && (activePDFMode == .originalPDF || !bookViewReady)
    }

    private var usesFoliateReader: Bool {
        book.format != .pdf || (bookViewReady && activePDFMode == .bookView)
    }

    // Called by the coordinator when the reader bridge reports a tap.
    // Use the same expression resolution path as the floating panel so
    // familiarity and review state track the unit the user actually sees.
    private func handleWordTap(_ char: String, context: String, charIndex: Int, x: CGFloat, y: CGFloat) {
        NSLog("[Leo UI] Word tap received: char=\(char), context=\(context.prefix(20)), idx=\(charIndex)")

        let parser = ChineseParser()
        let word = parser.resolveExpressionAtPosition(context: context, charIndex: charIndex)
        let entries = DictionaryEngine.shared.lookup(word)
        let pinyin = entries.first?.pinyinDisplay ?? ""
        let def = entries.first?.definitions.first ?? ""
        familiarityTracker?.recordEncounter(word, pinyin: pinyin, definition: def)
        lastReadAloudSnippet = context

        NSLog("[Leo UI] Encounter recorded for '\(word)'")
    }

    private func playReadAloud() async {
        let text = lastReadAloudSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await ttsEngine.generate(text: text)
        if ttsEngine.error == nil {
            ttsEngine.play()
        }
    }

    /// Triggered by the floating dictionary panel's Listen button via `.leoPlayTTS`.
    private func playWordTTS(word: String) async {
        await ttsEngine.generate(text: word)
        if ttsEngine.error == nil {
            ttsEngine.play()
        }
    }

    // Called when the user taps "I know this", "Add to review", or a familiarity state button in the floating panel.
    private func handlePopupAction(_ action: FoliateReaderView.PopupAction, word: String, context: String) {
        NSLog("[Leo UI] Popup action: \(action) for '\(word)'")
        switch action {
        case .markKnown:
            familiarityTracker?.markAsKnown(word)
        case .addToSRS:
            familiarityTracker?.markAsLearning(word)
            let fsrs = FSRSEngine(modelContext: modelContext)
            if fsrs.card(for: word) == nil {
                let sentenceContext = context.isEmpty ? nil : context
                _ = fsrs.createCard(for: word, context: sentenceContext)
            }
        case .setFamiliarity(let newState):
            familiarityTracker?.resetState(word, to: newState)
        }
    }

    private func persistLocation(_ locator: BookLocator) {
        let previousLocator = book.locator
        let previousFraction = previousLocator?.fraction ?? -1
        let isUITestLocatorCapture = ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_LOCATOR"] == "1"
        let minimumFractionDelta = isUITestLocatorCapture ? 0.0001 : 0.002
        let shouldSave =
            previousLocator?.cfi != locator.cfi
            || abs(previousFraction - locator.fraction) >= minimumFractionDelta
            || book.lastOpenedAt == nil

        // Always update the SwiftUI progress bar (even if we skip disk save)
        readingFraction = min(max(locator.fraction, 0), 1)

        guard shouldSave else { return }

        book.locator = locator
        book.lastOpenedAt = locator.updatedAt
        saveBookState(context: "EPUB reading position")

        if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_LOCATOR"] == "1" {
            uiTestRelocationCount += 1
            uiTestLocatorSummary = locatorSummary(for: locator, relocationCount: uiTestRelocationCount)
        }
    }

    private func persistPDFPage(_ pageIndex: Int) {
        guard book.format == .pdf else { return }
        let normalizedPageIndex = max(0, pageIndex)
        let shouldSave = book.safePdfLastPageIndex != normalizedPageIndex || book.lastOpenedAt == nil
        guard shouldSave else {
            if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_PDF_PAGE"] == "1" {
                uiTestPDFPageSummary = pdfPageSummary(for: normalizedPageIndex)
            }
            return
        }

        book.safePdfLastPageIndex = normalizedPageIndex
        book.lastOpenedAt = Date()
        saveBookState(context: "PDF page position")

        if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_PDF_PAGE"] == "1" {
            uiTestPDFPageSummary = pdfPageSummary(for: normalizedPageIndex)
        }
    }

    private func handleReaderLoadSuccess() {
        readerFailureMessage = nil
        runtime.clearReaderFailureIfPossible()
    }

    private func handleReaderLoadError(_ message: String) {
        guard !message.isEmpty else { return }
        readerFailureMessage = message
        runtime.markReaderFailure(message)
    }

    private func retryReader() {
        readerFailureMessage = nil
        runtime.startEmbeddedReader(forceRestart: true)
    }

    private func configurePDFPresentationFromStoredState() {
        guard book.format == .pdf else { return }
        pdfLayoutMode = PDFPageLayoutMode(rawValue: storedPDFLayoutMode) ?? .continuous
        pdfScrollAxis = PDFScrollAxis(rawValue: storedPDFScrollAxis) ?? .vertical

        let storedFitPolicy = PDFPageFitPolicy(rawValue: storedPDFFitPolicy) ?? .fitPage
        let shouldUseStoredFitPolicy = book.lastOpenedAt == nil && book.safePdfLastPageIndex == 0
        pdfFitPolicy = shouldUseStoredFitPolicy ? storedFitPolicy : book.pdfFitPolicy

        activePDFMode = (book.preferredPDFMode == .bookView && bookViewReady) ? .bookView : .originalPDF
        if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_PDF_PAGE"] == "1" {
            uiTestPDFPageSummary = pdfPageSummary(for: book.safePdfLastPageIndex)
        }
    }

    private func selectPDFMode(_ mode: PDFReadingMode) {
        guard book.format == .pdf else { return }
        if mode == .bookView && !bookViewReady {
            return
        }
        activePDFMode = mode
    }

    private func refreshUITestState() {
        if ProcessInfo.processInfo.environment["LEO_UI_TEST_SHOW_LOOKUP"] == "1", usesFoliateReader {
            let word = ProcessInfo.processInfo.environment["LEO_UI_TEST_LOOKUP_WORD"] ?? "你好"
            let entries = DictionaryEngine.shared.lookup(word)
            let def = entries.first?.definitions.first ?? ""
            uiTestDictionarySummary = "\(word): \(String(def.prefix(120)))"
        } else {
            uiTestDictionarySummary = nil
        }

        if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_LOCATOR"] == "1", usesFoliateReader {
            if let locator = book.locator {
                uiTestRelocationCount = max(uiTestRelocationCount, 1)
                uiTestLocatorSummary = locatorSummary(for: locator, relocationCount: uiTestRelocationCount)
            } else {
                uiTestRelocationCount = 0
                uiTestLocatorSummary = "count=0 fraction=0.000 cfi=pending"
            }
        } else {
            uiTestLocatorSummary = nil
            uiTestRelocationCount = 0
        }

        if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_PDF_PAGE"] == "1", showsOriginalPDF {
            uiTestPDFPageSummary = pdfPageSummary(for: book.safePdfLastPageIndex)
        } else if !showsOriginalPDF {
            uiTestPDFPageSummary = nil
        }
    }

    private func markBookOpened() {
        let now = Date()
        if let lastOpenedAt = book.lastOpenedAt,
           abs(lastOpenedAt.timeIntervalSince(now)) < 1 {
            return
        }
        book.lastOpenedAt = now
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo ReaderView] Failed to save lastOpenedAt for '\(book.title)': \(error)")
        }
    }

    private func locatorSummary(for locator: BookLocator, relocationCount: Int) -> String {
        "count=\(relocationCount) fraction=\(String(format: "%.3f", locator.fraction)) cfi=\(String(locator.cfi.prefix(72)))"
    }

    private func pdfPageSummary(for pageIndex: Int) -> String {
        "page=\(pageIndex + 1) fit=\(pdfFitPolicy.rawValue)"
    }

    private func resetChromeTimer() {
        chromeHideTimer?.invalidate()
        chromeHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation { self.chromeVisible = false }
            }
        }
    }

    private func saveBookState(context: String) {
        do {
            try modelContext.save()
        } catch {
            NSLog("[Leo ReaderView] Failed to save \(context) for '\(book.title)': \(error)")
        }
    }
}

// MARK: - Reading Theme

enum ReadingTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case sepia

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .sepia: "Sepia"
        }
    }
}

private struct ReaderFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text("Leo couldn’t open the embedded reader")
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry Reader", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier("leo.reader.failure")
    }
}

private struct PDFBookStatusBanner: View {
    let status: PDFBookPreparationStatus
    let activeMode: PDFReadingMode
    let bookViewReady: Bool
    let explanationDismissed: Bool
    let failureMessage: String?
    let onDismissExplanation: () -> Void
    let onPrepare: () -> Void
    let onRetry: () -> Void
    let onOpenBookView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !explanationDismissed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Original PDF keeps the real pages. Book View gives you Leo’s dictionary, TTS, and reading tools.")
                        .font(.caption)
                    Button("Got it", action: onDismissExplanation)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .accessibilityIdentifier("leo.reader.pdfExplainer")
            }

            switch status {
            case .idle:
                HStack(spacing: 8) {
                    Text("Book View is available on this PDF once Leo prepares it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Prepare Book View", action: onPrepare)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("leo.reader.prepareBookView")
                }

            case .preparing:
                EmptyView()

            case .ready:
                if bookViewReady && activeMode != .bookView {
                    HStack(spacing: 8) {
                        Button("Open Book View", action: onOpenBookView)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityIdentifier("leo.reader.openBookView")
                    }
                }

            case .failed:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Book View unavailable")
                        .font(.caption.weight(.semibold))
                    if let failureMessage, !failureMessage.isEmpty {
                        Text(failureMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Retry Book View", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("leo.reader.retryBookView")
                }
                .accessibilityIdentifier("leo.reader.bookViewUnavailable")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityIdentifier("leo.reader.pdfModeBanner")
    }
}

// MARK: - TOC Panel

private struct TOCPanelView: View {
    let items: [TOCItem]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contents")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No table of contents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            Button {
                                onSelect(item.href)
                            } label: {
                                HStack(spacing: 0) {
                                    // Indent nested entries
                                    if item.depth > 0 {
                                        Color.clear
                                            .frame(width: CGFloat(item.depth) * 16, height: 1)
                                    }
                                    Text(item.label.isEmpty ? "Untitled" : item.label)
                                        .font(item.depth == 0 ? .body : .subheadline)
                                        .fontWeight(item.depth == 0 ? .medium : .regular)
                                        .foregroundStyle(item.depth == 0 ? .primary : .secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.label)

                            if item.depth == 0 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320, minHeight: 200, idealHeight: 400)
        .accessibilityIdentifier("leo.toc.panel")
    }
}

// MARK: - Search Bar

private struct SearchBarView: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search in book…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused(isFocused)
                .onSubmit {
                    onSubmit()
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
                .accessibilityIdentifier("leo.search.field")

            if !query.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close search bar")
            .accessibilityIdentifier("leo.search.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 0))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("leo.search.bar")
    }
}

// MARK: - Floating Action Buttons

/// Three floating action buttons shown at bottom-right when chrome is visible.
/// They auto-hide with the same `chromeVisible` state as the top toolbar.
private struct FloatingActionButtons: View {
    let onLibrary: () -> Void
    let onVocabulary: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            FloatingButton(
                icon: "books.vertical",
                accessibilityLabel: "Library",
                action: onLibrary
            )
            .accessibilityIdentifier("leo.fab.library")

            FloatingButton(
                icon: "character.book.closed",
                accessibilityLabel: "Vocabulary",
                action: onVocabulary
            )
            .accessibilityIdentifier("leo.fab.vocabulary")

            FloatingButton(
                icon: "textformat.size",
                accessibilityLabel: "Reading Settings",
                action: onSettings
            )
            .accessibilityIdentifier("leo.fab.settings")
        }
    }
}

private struct FloatingButton: View {
    let icon: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
