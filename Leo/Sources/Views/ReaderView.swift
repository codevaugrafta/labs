import SwiftUI
import WebKit

struct ReaderView: View {
    let book: Book
    @State private var content: EPUBParser.EPUBContent?
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
                if let content {
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
            DictionaryEngine.shared.load()
            FrequencyEngine.shared.load()
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
        let url = URL(fileURLWithPath: book.filePath)
        guard FileManager.default.fileExists(atPath: book.filePath) else {
            error = "File not found: \(book.filePath)"
            return
        }

        do {
            let parser = EPUBParser()
            content = try parser.parse(fileURL: url)
            book.lastOpenedAt = Date()
            if let title = content?.title, book.title != title {
                book.title = title
            }
            if let author = content?.author, book.author != author, author != "Unknown" {
                book.author = author
            }
        } catch {
            self.error = error.localizedDescription
        }
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
        context.coordinator.currentChapterId = chapter.id
        loadChapter(in: webView)
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
        webView.loadHTMLString(styledHTML, baseURL: basePath)
    }

    private func injectReaderStyles(into html: String) -> String {
        let css = """
        <style>
            :root {
                --bg: \(theme.cssBackground);
                --fg: \(theme.cssForeground);
            }
            * { box-sizing: border-box; }
            html, body {
                background: var(--bg) !important;
                color: var(--fg) !important;
                font-family: -apple-system, "Noto Sans SC", "PingFang SC", sans-serif;
                font-size: 18px;
                line-height: 1.8;
                margin: 0;
                padding: 40px 60px;
                max-width: 720px;
                margin-left: auto;
                margin-right: auto;
                cursor: default;
                -webkit-user-select: none;
                user-select: none;
            }
            p { margin-bottom: 1em; text-align: justify; }
            h1, h2, h3 { color: var(--fg); margin-top: 1.5em; }
            img { max-width: 100%; height: auto; }
            a { color: inherit; }
            .leo-char {
                cursor: pointer;
                border-radius: 1px;
                transition: background 0.1s;
            }
            .leo-char:hover {
                background: rgba(255, 165, 0, 0.15);
            }
            .leo-char.selected {
                background: rgba(255, 165, 0, 0.3);
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

        /// Given a context string and the index of the clicked character,
        /// use NLTagger to find the word boundary containing that character.
        private func resolveWord(in context: String, at charIndex: Int) -> String {
            let tokens = parser.segmentWords(context)

            // Find which token contains the clicked character index
            var offset = 0
            for token in tokens where token.type == .word {
                let tokenLength = token.text.count
                if charIndex >= offset && charIndex < offset + tokenLength {
                    return token.text
                }
                offset += tokenLength
            }

            // Fallback: try dictionary lookup with decreasing window sizes
            // from the clicked position
            let chars = Array(context)
            guard charIndex < chars.count else {
                return String(chars.last ?? Character(" "))
            }

            // Try 4, 3, 2, 1 character windows starting at clicked position
            for length in stride(from: min(4, chars.count - charIndex), through: 1, by: -1) {
                let end = min(charIndex + length, chars.count)
                let candidate = String(chars[charIndex..<end])
                if DictionaryEngine.shared.contains(candidate) {
                    return candidate
                }
            }

            // Try windows starting before the clicked position
            for start in stride(from: max(0, charIndex - 3), through: charIndex, by: 1) {
                for length in stride(from: min(4, chars.count - start), through: 2, by: -1) {
                    let end = min(start + length, chars.count)
                    if end <= charIndex { continue } // must include clicked char
                    let candidate = String(chars[start..<end])
                    if DictionaryEngine.shared.contains(candidate) {
                        return candidate
                    }
                }
            }

            // Ultimate fallback: single character
            return String(chars[charIndex])
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
}
