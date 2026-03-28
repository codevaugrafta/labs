import SwiftUI
import WebKit
import PDFKit

struct ReaderView: View {
    let book: Book
    @State private var content: EPUBParser.EPUBContent?
    @State private var pdfPages: [String]? // extracted text per page
    @State private var currentChapterIndex = 0
    @State private var error: String?
    @State private var theme: ReadingTheme = .light
    @State private var selectedWord: String?
    @State private var wordEntries: [DictionaryEngine.Entry] = []
    @State private var wordFamiliarity: FamiliarityState = .unknown
    @State private var wordFrequency: FrequencyEngine.FrequencyData?
    @State private var popupPosition: CGPoint = .zero
    @State private var familiarityTracker: FamiliarityTracker?
    @StateObject private var sessionEngine = ReadingSessionEngine()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if book.format == .pdf {
                    // Native PDF rendering — fast, reliable, supports Chinese
                    PDFReaderView(filePath: book.filePath)
                } else if let content {
                    VStack(spacing: 0) {
                        EPUBWebView(
                            chapter: content.chapters[currentChapterIndex],
                            basePath: content.basePath,
                            theme: theme,
                            onWordTapped: handleWordTap
                        )

                        ChapterNavigationBar(
                            currentIndex: currentChapterIndex,
                            totalChapters: content.chapters.count,
                            chapterTitle: content.chapters[currentChapterIndex].title,
                            onPrevious: { currentChapterIndex = max(0, currentChapterIndex - 1) },
                            onNext: { currentChapterIndex = min(content.chapters.count - 1, currentChapterIndex + 1) }
                        )
                    }
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Failed to open book")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    ProgressView("Opening...")
                }
            }

            // Floating word popup
            if let word = selectedWord {
                WordPopupView(
                    word: word,
                    entries: wordEntries,
                    familiarityState: wordFamiliarity,
                    frequencyData: wordFrequency ?? FrequencyEngine.shared.lookup(word),
                    onDismiss: { selectedWord = nil },
                    onMarkKnown: {
                        familiarityTracker?.markAsKnown(word)
                        selectedWord = nil
                    },
                    onAddToSRS: {
                        familiarityTracker?.markAsLearning(word)
                        let fsrs = FSRSEngine(modelContext: modelContext)
                        if fsrs.card(for: word) == nil {
                            _ = fsrs.createCard(for: word)
                        }
                        selectedWord = nil
                    }
                )
                .position(x: popupPosition.x, y: popupPosition.y)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: selectedWord)
            }
        }
        .toolbar {
            // Reading session timer
            ToolbarItem(placement: .automatic) {
                if sessionEngine.isActive {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundStyle(.orange)
                        Text(sessionEngine.formattedTime)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                        Button(action: {
                            sessionEngine.stopSession()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop reading session (Cmd+R)")
                    }
                } else {
                    Button(action: {
                        sessionEngine.startSession(bookTitle: book.title)
                    }) {
                        Label("Start Session", systemImage: "play.circle")
                    }
                    .help("Start reading session (Cmd+R)")
                }
            }

            // Theme picker
            ToolbarItem(placement: .automatic) {
                Picker("Theme", selection: $theme) {
                    ForEach(ReadingTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .task {
            // Load dictionary on background thread — takes 4+ seconds for 120K entries
            Task.detached(priority: .userInitiated) {
                DictionaryEngine.shared.load()
                FrequencyEngine.shared.load()
            }
            familiarityTracker = FamiliarityTracker(modelContext: modelContext)
            sessionEngine.configure(modelContext: modelContext)
            await openBook()
        }
        .onTapGesture {
            // Dismiss popup on background tap
            if selectedWord != nil { selectedWord = nil }
        }
    }

    private func handleWordTap(_ word: String, x: CGFloat, y: CGFloat) {
        let entries = DictionaryEngine.shared.lookup(word)
        wordEntries = entries
        wordFamiliarity = familiarityTracker?.state(for: word) ?? .unknown
        wordFrequency = FrequencyEngine.shared.lookup(word)

        // Record encounter
        let pinyin = entries.first?.pinyinDisplay ?? ""
        let def = entries.first?.definitions.first ?? ""
        familiarityTracker?.recordEncounter(word, pinyin: pinyin, definition: def)

        selectedWord = word
        popupPosition = CGPoint(x: min(x + 180, 500), y: y + 80)
    }

    private func openBook() async {
        let filePath = book.filePath
        let format = book.format
        NSLog("[Leo] Opening book: \(filePath) format=\(format)")

        guard FileManager.default.fileExists(atPath: filePath) else {
            error = "File not found: \(filePath)"
            NSLog("[Leo] ERROR: File not found")
            return
        }

        book.lastOpenedAt = Date()

        let url = URL(fileURLWithPath: filePath)

        if format == .pdf {
            // PDF uses native PDFView — no parsing needed
            NSLog("[Leo] PDF book selected — using native PDFView")
            return
        } else {
            NSLog("[Leo] Parsing EPUB on background thread...")
            // Use GCD — Process.waitUntilExit() blocks cooperative threads
            let parsed: EPUBParser.EPUBContent? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let parser = EPUBParser()
                        let result = try parser.parse(fileURL: url)
                        NSLog("[Leo] EPUB parsed: \(result.chapters.count) chapters")
                        continuation.resume(returning: result)
                    } catch {
                        NSLog("[Leo] EPUB ERROR: \(error)")
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let parsed {
                content = parsed
                if !parsed.title.isEmpty {
                    book.title = parsed.title
                }
                if !parsed.author.isEmpty && parsed.author != "Unknown" {
                    book.author = parsed.author
                }
            } else {
                self.error = "Failed to open EPUB"
            }
        }
    }

    /// Convert extracted PDF page text into styled HTML for the reader view
    private func pdfPageToHTML(_ pages: [String], page: Int) -> String {
        guard page >= 0, page < pages.count else { return "<p>Empty page</p>" }
        let text = pages[page]
        // Split into paragraphs (double newline) and wrap in <p> tags
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br/>"))</p>" }
            .joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8"><title>Page \(page + 1)</title></head>
        <body>\(paragraphs.isEmpty ? "<p>(No text extracted from this page)</p>" : paragraphs)</body>
        </html>
        """
    }
}

// MARK: - EPUB Web View with Word Tap Support

struct EPUBWebView: NSViewRepresentable {
    let chapter: EPUBParser.Chapter
    let basePath: URL
    let theme: ReadingTheme
    let onWordTapped: (String, CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWordTapped: onWordTapped)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Add message handler for word taps from JavaScript
        let handler = context.coordinator
        config.userContentController.add(handler, name: "wordTap")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        // Warm up WKWebView (first load can take 10-15 seconds without this)
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        context.coordinator.currentChapterId = chapter.id
        // Small delay to let warmup complete, then load actual content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.loadChapter(in: webView)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentChapterId != chapter.id {
            context.coordinator.currentChapterId = chapter.id
            loadChapter(in: webView)
        }
        // Apply theme changes via JS
        let themeJS = """
        document.documentElement.style.setProperty('--bg', '\(theme.cssBackground)');
        document.documentElement.style.setProperty('--fg', '\(theme.cssForeground)');
        document.body.style.background = '\(theme.cssBackground)';
        document.body.style.color = '\(theme.cssForeground)';
        """
        webView.evaluateJavaScript(themeJS)
    }

    private func loadChapter(in webView: WKWebView) {
        let styledHTML = injectReaderStyles(into: chapter.htmlContent)

        // Write styled HTML INTO the EPUB extraction directory so images/CSS resolve.
        // loadFileURL is more reliable than loadHTMLString for file-based content.
        let styledFile = basePath.appendingPathComponent("_leo_styled.html")
        try? styledHTML.write(to: styledFile, atomically: true, encoding: .utf8)

        // Allow read access to the entire extraction directory (for images, CSS, fonts)
        webView.loadFileURL(styledFile, allowingReadAccessTo: basePath)
    }

    private func injectReaderStyles(into html: String) -> String {
        let css = """
        <style>
            :root {
                --bg: \(theme.cssBackground);
                --fg: \(theme.cssForeground);
                --accent: \(theme.cssAccent);
            }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html {
                background: var(--bg) !important;
                color: var(--fg) !important;
                scroll-behavior: smooth;
            }
            body {
                background: var(--bg) !important;
                color: var(--fg) !important;
                font-family: "PingFang SC", "Noto Sans SC", "Hiragino Sans GB",
                             "Source Han Sans CN", -apple-system, sans-serif;
                font-size: 18px;
                line-height: 2.0;
                letter-spacing: 0.02em;
                padding: 48px 64px;
                max-width: 700px;
                margin: 0 auto;
                cursor: default;
                -webkit-user-select: none;
                user-select: none;
                -webkit-font-smoothing: antialiased;
                text-rendering: optimizeLegibility;
            }
            p {
                margin-bottom: 1.2em;
                text-align: justify;
                text-indent: 2em;
            }
            p:first-child { text-indent: 0; }
            h1, h2, h3 {
                color: var(--fg);
                margin-top: 2em;
                margin-bottom: 0.8em;
                text-indent: 0;
                text-align: center;
                font-weight: 600;
            }
            h1 { font-size: 1.5em; }
            h2 { font-size: 1.3em; }
            h3 { font-size: 1.1em; }
            img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
            a { color: inherit; text-decoration: none; }
            /* Clean up EPUB inline styles that fight with our theme */
            span[style] { font-size: inherit !important; font-family: inherit !important; }
            .leo-char {
                cursor: pointer;
                border-radius: 2px;
                transition: background 0.12s ease;
                padding: 0 1px;
            }
            .leo-char:hover {
                background: rgba(255, 165, 0, 0.18);
            }
            .leo-char.selected {
                background: rgba(255, 165, 0, 0.35);
                border-radius: 3px;
            }
        </style>
        """

        let script = """
        <script>
        // Chinese character detection
        function isChinese(char) {
            const code = char.charCodeAt(0);
            return (code >= 0x4E00 && code <= 0x9FFF)
                || (code >= 0x3400 && code <= 0x4DBF)
                || (code >= 0xF900 && code <= 0xFAFF);
        }

        // Wrap each Chinese character in its own span.
        // Swift handles word-level grouping via NLTagger when a character is clicked.
        function segmentText(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent;
                if (!text.trim()) return;

                const frag = document.createDocumentFragment();
                let nonChineseBuffer = '';

                for (let i = 0; i < text.length; i++) {
                    const ch = text[i];
                    if (isChinese(ch)) {
                        // Flush non-Chinese buffer
                        if (nonChineseBuffer) {
                            frag.appendChild(document.createTextNode(nonChineseBuffer));
                            nonChineseBuffer = '';
                        }
                        // Each Chinese character gets its own span
                        const span = document.createElement('span');
                        span.className = 'leo-char';
                        span.dataset.offset = i.toString();
                        span.textContent = ch;
                        span.addEventListener('click', handleCharClick);
                        frag.appendChild(span);
                    } else {
                        nonChineseBuffer += ch;
                    }
                }
                if (nonChineseBuffer) {
                    frag.appendChild(document.createTextNode(nonChineseBuffer));
                }

                node.parentNode.replaceChild(frag, node);
            } else if (node.nodeType === Node.ELEMENT_NODE && !['SCRIPT', 'STYLE'].includes(node.tagName)) {
                Array.from(node.childNodes).forEach(segmentText);
            }
        }

        function handleCharClick(e) {
            const clickedChar = e.target.textContent;
            const rect = e.target.getBoundingClientRect();

            // Gather surrounding context: walk siblings to build a Chinese text window
            // This gives Swift enough context to segment the word properly
            let contextBefore = '';
            let contextAfter = '';
            let charIndex = 0;

            // Collect up to 10 chars before
            let prev = e.target.previousSibling;
            let beforeChars = [];
            while (prev && beforeChars.length < 10) {
                if (prev.classList && prev.classList.contains('leo-char')) {
                    beforeChars.unshift(prev.textContent);
                } else if (prev.nodeType === Node.TEXT_NODE) {
                    break;
                }
                prev = prev.previousSibling;
            }
            contextBefore = beforeChars.join('');

            // Collect up to 10 chars after
            let next = e.target.nextSibling;
            let afterChars = [];
            while (next && afterChars.length < 10) {
                if (next.classList && next.classList.contains('leo-char')) {
                    afterChars.push(next.textContent);
                } else if (next.nodeType === Node.TEXT_NODE) {
                    break;
                }
                next = next.nextSibling;
            }
            contextAfter = afterChars.join('');

            charIndex = contextBefore.length;
            const fullContext = contextBefore + clickedChar + contextAfter;

            // Remove previous selection
            document.querySelectorAll('.leo-char.selected').forEach(el => el.classList.remove('selected'));
            e.target.classList.add('selected');

            // Send character + context to Swift for word-level resolution
            window.webkit.messageHandlers.wordTap.postMessage({
                char: clickedChar,
                context: fullContext,
                charIndex: charIndex,
                x: rect.left,
                y: rect.bottom
            });

            e.stopPropagation();
        }

        // Run segmentation after DOM is ready
        document.addEventListener('DOMContentLoaded', function() {
            segmentText(document.body);
        });
        if (document.readyState !== 'loading') {
            segmentText(document.body);
        }
        </script>
        """

        let injection = css + script

        if html.contains("<head>") {
            return html.replacingOccurrences(of: "<head>", with: "<head>\(injection)")
        } else if html.contains("<html>") {
            return html.replacingOccurrences(of: "<html>", with: "<html><head>\(injection)</head>")
        } else {
            return "\(injection)\(html)"
        }
    }

    // MARK: - Coordinator for JS message handling

    class Coordinator: NSObject, WKScriptMessageHandler {
        let onWordTapped: (String, CGFloat, CGFloat) -> Void
        var currentChapterId: String = ""
        private let parser = ChineseParser()

        init(onWordTapped: @escaping (String, CGFloat, CGFloat) -> Void) {
            self.onWordTapped = onWordTapped
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "wordTap",
                  let body = message.body as? [String: Any],
                  let context = body["context"] as? String,
                  let charIndex = body["charIndex"] as? Int,
                  let x = body["x"] as? CGFloat,
                  let y = body["y"] as? CGFloat else {
                return
            }

            // Use NLTagger to find the word containing the clicked character
            let word = resolveWord(in: context, at: charIndex)

            DispatchQueue.main.async {
                self.onWordTapped(word, x, y)
            }
        }

        /// Resolve the word at the clicked character position.
        /// Delegates to ChineseParser's dictionary-informed resolution.
        private func resolveWord(in context: String, at charIndex: Int) -> String {
            parser.resolveWordAtPosition(context: context, charIndex: charIndex)
        }
    }
}

// MARK: - Chapter Navigation

struct ChapterNavigationBar: View {
    let currentIndex: Int
    let totalChapters: Int
    let chapterTitle: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .disabled(currentIndex == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Spacer()

            Text(chapterTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(currentIndex + 1) / \(totalChapters)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(currentIndex == totalChapters - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
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

    var cssBackground: String {
        switch self {
        case .light: "#FFFFFF"
        case .dark: "#1A1A1A"
        case .sepia: "#F5EDDC"
        }
    }

    var cssForeground: String {
        switch self {
        case .light: "#1A1A1A"
        case .dark: "#E5E5E5"
        case .sepia: "#4A3520"
        }
    }

    var cssAccent: String {
        switch self {
        case .light: "#E67E22"
        case .dark: "#F39C12"
        case .sepia: "#D35400"
        }
    }
}

// MARK: - PDF Reader (Apple PDFKit)

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

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // PDF view handles its own state
    }
}
