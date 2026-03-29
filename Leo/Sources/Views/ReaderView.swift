import SwiftUI
import WebKit
import PDFKit

struct ReaderView: View {
    let book: Book
    @State private var theme: ReadingTheme = .light
    @State private var readerFailureMessage: String?
    @State private var familiarityTracker: FamiliarityTracker?
    @State private var lastReadAloudSnippet: String = ""
    @StateObject private var sessionEngine = ReadingSessionEngine()
    @StateObject private var ttsEngine = TTSEngine()
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var runtime: LeoRuntime

    @AppStorage("leo.fontSize") private var readingFontSize = 18.0
    @AppStorage("leo.lineHeight") private var readingLineHeight = 1.8
    @AppStorage("leo.showPinyin") private var readingShowPinyin = false
    @AppStorage("leo.showHighlights") private var readingShowHighlights = true
    @AppStorage("leo.textDirection") private var readingTextDirection = "horizontal"
    @State private var showReadingChromePopover = false
    /// UI tests: when `LEO_UI_TEST_SHOW_LOOKUP` is set, surface dictionary text for AX (not from WKWebView).
    @State private var uiTestDictionarySummary: String?
    @State private var uiTestLocatorSummary: String?
    @State private var uiTestRelocationCount = 0

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if book.format == .pdf {
                    PDFReaderView(filePath: book.filePath)
                } else if let failureMessage = activeFailureMessage {
                    ReaderFailureView(
                        message: failureMessage,
                        onRetry: retryReader
                    )
                } else {
                    FoliateReaderView(
                        bookFilePath: book.filePath,
                        bookId: book.id.uuidString,
                        theme: theme,
                        initialLocator: book.locator,
                        readingChrome: LeoReadingChromePreferences(
                            fontSize: readingFontSize,
                            lineHeight: readingLineHeight,
                            textDirection: readingTextDirection,
                            showPinyin: readingShowPinyin,
                            showHighlights: readingShowHighlights
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
                        }
                    )
                }
            }

            if book.format == .pdf {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap-to-define and read-aloud use the EPUB reader. PDF is view-only here — convert to reflowable EPUB to use them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Convert to EPUB for Reading…") {
                        NotificationCenter.default.post(name: .leoRequestPDFConvert, object: book.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityIdentifier("leo.reader.pdfViewOnlyBanner")
            }

        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if let summary = uiTestDictionarySummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("leo.reader.dictionarySmoke")
                        .accessibilityLabel(summary)
                }

                if let locatorSummary = uiTestLocatorSummary {
                    Text(locatorSummary)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .id(locatorSummary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("leo.reader.locatorProbe")
                        .accessibilityLabel(locatorSummary)
                        .accessibilityValue(locatorSummary)
                }
            }
            .padding(.top, 4)
            .zIndex(10_000)
        }
        .toolbar {
            // Theme picker
            ToolbarItem(placement: .automatic) {
                Picker("Theme", selection: $theme) {
                    ForEach(ReadingTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("leo.toolbar.theme")
            }

            if book.format != .pdf {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showReadingChromePopover.toggle()
                    } label: {
                        Label("Reading layout", systemImage: "textformat.size")
                    }
                    .accessibilityIdentifier("leo.toolbar.readingLayout")
                    .popover(isPresented: $showReadingChromePopover, arrowEdge: .bottom) {
                        ReadingPreferencesForm(
                            fontSize: $readingFontSize,
                            lineHeight: $readingLineHeight,
                            textDirection: $readingTextDirection,
                            showPinyin: $readingShowPinyin,
                            showHighlights: $readingShowHighlights
                        )
                        .padding()
                        .frame(minWidth: 320, minHeight: 280)
                    }
                }
            }

            // Reading session timer
            if book.format != .pdf {
                ToolbarItemGroup(placement: .automatic) {
                    if ttsEngine.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    if ttsEngine.isPlaying {
                        Button(action: { ttsEngine.pause() }) {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        Button(action: {
                            ttsEngine.stop()
                        }) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button(action: { Task { await playReadAloud() } }) {
                            Label("Read aloud", systemImage: "speaker.wave.2")
                        }
                        .disabled(lastReadAloudSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let err = ttsEngine.error {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                if sessionEngine.isActive {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundStyle(.orange)
                        Text(sessionEngine.formattedTime)
                            .font(.system(.body, design: .monospaced))
                        Button(action: { sessionEngine.stopSession() }) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .accessibilityIdentifier("leo.reader.sessionActive")
                } else {
                    Button(action: { sessionEngine.startSession(bookTitle: book.title) }) {
                        Label("Start Session", systemImage: "play.circle")
                    }
                }
            }
        }
        .task {
            // Single load pass — concurrent load() calls corrupt DictionaryEngine's `loaded` flag.
            await Task.detached(priority: .userInitiated) {
                DictionaryEngine.shared.load()
                FrequencyEngine.shared.load()
            }.value
            familiarityTracker = FamiliarityTracker(modelContext: modelContext)
            sessionEngine.configure(modelContext: modelContext)
            markBookOpened()

            if ProcessInfo.processInfo.environment["LEO_UI_TEST_SHOW_LOOKUP"] == "1", book.format != .pdf {
                let word = ProcessInfo.processInfo.environment["LEO_UI_TEST_LOOKUP_WORD"] ?? "你好"
                let entries = DictionaryEngine.shared.lookup(word)
                let def = entries.first?.definitions.first ?? ""
                uiTestDictionarySummary = "\(word): \(String(def.prefix(120)))"
            }

            if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_LOCATOR"] == "1",
               let locator = book.locator {
                uiTestRelocationCount = 1
                uiTestLocatorSummary = locatorSummary(for: locator, relocationCount: uiTestRelocationCount)
            } else if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_LOCATOR"] == "1" {
                uiTestRelocationCount = 0
                uiTestLocatorSummary = "count=0 fraction=0.000 cfi=pending"
            }
        }
    }

    private var activeFailureMessage: String? {
        readerFailureMessage ?? runtime.readerServerState.failureMessage
    }

    // Called by the coordinator immediately after resolving the tapped word.
    // Used to record the encounter in the familiarity tracker / session engine.
    // The popup itself is rendered in JS — we don't show any SwiftUI state here.
    private func handleWordTap(_ char: String, context: String, charIndex: Int, x: CGFloat, y: CGFloat) {
        NSLog("[Leo UI] Word tap received: char=\(char), context=\(context.prefix(20)), idx=\(charIndex)")

        // The coordinator already resolved the word and is calling showPopup() in JS.
        // We just record the encounter here for familiarity tracking.
        let parser = ChineseParser()
        let word = parser.resolveWordAtPosition(context: context, charIndex: charIndex)
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

    // Called when the user taps "I know this" or "Add to review" inside the JS popup.
    private func handlePopupAction(_ action: FoliateReaderView.PopupAction, word: String) {
        NSLog("[Leo UI] Popup action: \(action) for '\(word)'")
        switch action {
        case .markKnown:
            familiarityTracker?.markAsKnown(word)
        case .addToSRS:
            familiarityTracker?.markAsLearning(word)
            let fsrs = FSRSEngine(modelContext: modelContext)
            if fsrs.card(for: word) == nil {
                _ = fsrs.createCard(for: word)
            }
        }
    }

    private func persistLocation(_ locator: BookLocator) {
        let previousLocator = book.locator
        let previousFraction = previousLocator?.fraction ?? -1
        let shouldSave =
            previousLocator?.cfi != locator.cfi
            || abs(previousFraction - locator.fraction) >= 0.002
            || book.lastOpenedAt == nil

        guard shouldSave else { return }

        book.locator = locator
        book.lastOpenedAt = locator.updatedAt
        try? modelContext.save()

        if ProcessInfo.processInfo.environment["LEO_UI_TEST_CAPTURE_LOCATOR"] == "1" {
            uiTestRelocationCount += 1
            uiTestLocatorSummary = locatorSummary(for: locator, relocationCount: uiTestRelocationCount)
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

    private func markBookOpened() {
        let now = Date()
        if let lastOpenedAt = book.lastOpenedAt,
           abs(lastOpenedAt.timeIntervalSince(now)) < 1 {
            return
        }
        book.lastOpenedAt = now
        try? modelContext.save()
    }

    private func locatorSummary(for locator: BookLocator, relocationCount: Int) -> String {
        "count=\(relocationCount) fraction=\(String(format: "%.3f", locator.fraction)) cfi=\(String(locator.cfi.prefix(72)))"
    }
}

// MARK: - PDF Reader (Apple PDFKit — native, works for Chinese visual rendering)

struct PDFReaderView: NSViewRepresentable {
    let filePath: String

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor

        if let document = PDFDocument(url: URL(fileURLWithPath: filePath)) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {}
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
