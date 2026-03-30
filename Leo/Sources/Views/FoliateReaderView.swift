import SwiftUI
import WebKit

/// Represents a single entry in the book's table of contents.
struct TOCItem: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let href: String
    let depth: Int
}

/// Values mirrored from Settings → Reading (`@AppStorage`), pushed into foliate `reader.js`.
struct LeoReadingChromePreferences: Equatable {
    var fontSize: Double
    var lineHeight: Double
    var textDirection: String
    var showHighlights: Bool
    /// `"clean"` — no shadows or texture (default); `"page"` — book-page shadows + paper texture.
    var pageStyle: String
    /// Foliate spread mode: `"none"` (single column), `"auto"` (two columns when wide), `"both"` (always two columns).
    var spreadMode: String

    static let defaultPrefs = LeoReadingChromePreferences(
        fontSize: 18,
        lineHeight: 1.7,
        textDirection: "horizontal",
        showHighlights: true,
        pageStyle: "clean",
        spreadMode: "both"
    )
}

/// EPUB reader powered by foliate-js via localhost HTTP server.
/// Dictionary lookups are shown as a floating HTML popup rendered inside the WKWebView,
/// positioned near the tapped word. No SwiftUI overlay is needed.
struct FoliateReaderView: NSViewRepresentable {
    let bookFilePath: String
    let bookId: String
    let theme: ReadingTheme
    let initialLocator: BookLocator?
    let readingChrome: LeoReadingChromePreferences
    let onRelocate: (BookLocator) -> Void
    let onLoadSuccess: () -> Void
    let onLoadError: (String) -> Void

    /// Called when the user taps a word. The coordinator performs a dictionary lookup
    /// and renders the popup directly in JS. This closure receives the resolved word,
    /// entries, and coordinates so that ReaderView can keep its session/familiarity state.
    let onWordTapped: (String, String, Int, CGFloat, CGFloat) -> Void

    /// Called when the user presses "I know this" or "Add to review" inside the JS popup.
    /// The ReaderView uses this to drive FamiliarityTracker / FSRSEngine.
    /// `context` is the sentence in which the word was tapped, forwarded to FSRSEngine for sentence-based flashcards.
    let onPopupAction: (_ action: PopupAction, _ word: String, _ context: String) -> Void

    /// Maps a resolved word to its familiarity for the JS popup badge.
    let familiarityForWord: (String) -> FamiliarityState

    /// Indicates whether the word already has an FSRS review card.
    let hasReviewCardForWord: (String) -> Bool

    /// Optional callback invoked when the TOC is fetched from JS.
    var onTOCLoaded: (([TOCItem]) -> Void)?

    /// Optional callback that delivers the Coordinator to the caller once the WKWebView is set up.
    var onCoordinatorReady: ((Coordinator) -> Void)?

    enum PopupAction {
        case markKnown
        case addToSRS
        case setFamiliarity(FamiliarityState)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialLocator: initialLocator,
            onRelocate: onRelocate,
            onLoadSuccess: onLoadSuccess,
            onLoadError: onLoadError,
            onWordTapped: onWordTapped,
            onPopupAction: onPopupAction,
            familiarityForWord: familiarityForWord,
            hasReviewCardForWord: hasReviewCardForWord,
            onTOCLoaded: onTOCLoaded,
            shouldAutoAdvanceForUITest: ProcessInfo.processInfo.environment["LEO_UI_TEST_AUTO_ADVANCE_PAGE"] == "1"
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Register message handler for JS → Swift communication
        config.userContentController.add(context.coordinator, name: "leoReader")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Enable Safari Web Inspector for debugging
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // Register the EPUB file with the server
        LocalServer.shared.registerBook(id: bookId, filePath: bookFilePath)

        // Load the reader page from localhost
        if let readerURL = LocalServer.shared.readerURL {
            NSLog("[Leo Foliate] Loading reader from: \(readerURL)")
            webView.load(URLRequest(url: readerURL))
        } else {
            NSLog("[Leo Foliate] ERROR: Server not running, no reader URL")
            DispatchQueue.main.async {
                context.coordinator.onLoadError("Leo couldn’t connect to the embedded reader server. Retry the reader and try again.")
            }
        }

        context.coordinator.webView = webView
        context.coordinator.bookId = bookId
        context.coordinator.latestTheme = theme
        context.coordinator.latestReading = readingChrome
        context.coordinator.initialLocator = initialLocator
        onCoordinatorReady?(context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.latestTheme = theme
        context.coordinator.latestReading = readingChrome
        context.coordinator.initialLocator = initialLocator

        // If book changed, reload
        if context.coordinator.bookId != bookId {
            context.coordinator.pageLoaded = false
            context.coordinator.didAutoAdvanceForUITest = false
            context.coordinator.bookId = bookId
            LocalServer.shared.registerBook(id: bookId, filePath: bookFilePath)
            if let readerURL = LocalServer.shared.readerURL {
                webView.load(URLRequest(url: readerURL))
            }
            return
        }

        let themeStr = theme.rawValue
        let chromeChanged =
            context.coordinator.lastPushedTheme != themeStr
            || context.coordinator.lastPushedChrome != readingChrome
        if chromeChanged, context.coordinator.pageLoaded {
            context.coordinator.pushReaderChrome(webView: webView)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var initialLocator: BookLocator?
        let onRelocate: (BookLocator) -> Void
        let onLoadSuccess: () -> Void
        let onLoadError: (String) -> Void
        let onWordTapped: (String, String, Int, CGFloat, CGFloat) -> Void
        let onPopupAction: (PopupAction, String, String) -> Void
        let familiarityForWord: (String) -> FamiliarityState
        let hasReviewCardForWord: (String) -> Bool
        let onTOCLoaded: (([TOCItem]) -> Void)?
        let shouldAutoAdvanceForUITest: Bool
        weak var webView: WKWebView?
        var bookId: String = ""
        var latestTheme: ReadingTheme = .light
        var latestReading: LeoReadingChromePreferences = .defaultPrefs
        var lastPushedTheme: String?
        var lastPushedChrome: LeoReadingChromePreferences?
        var pageLoaded = false
        var didAutoAdvanceForUITest = false

        init(
            initialLocator: BookLocator?,
            onRelocate: @escaping (BookLocator) -> Void,
            onLoadSuccess: @escaping () -> Void,
            onLoadError: @escaping (String) -> Void,
            onWordTapped: @escaping (String, String, Int, CGFloat, CGFloat) -> Void,
            onPopupAction: @escaping (PopupAction, String, String) -> Void,
            familiarityForWord: @escaping (String) -> FamiliarityState,
            hasReviewCardForWord: @escaping (String) -> Bool,
            onTOCLoaded: (([TOCItem]) -> Void)?,
            shouldAutoAdvanceForUITest: Bool
        ) {
            self.initialLocator = initialLocator
            self.onRelocate = onRelocate
            self.onLoadSuccess = onLoadSuccess
            self.onLoadError = onLoadError
            self.onWordTapped = onWordTapped
            self.onPopupAction = onPopupAction
            self.familiarityForWord = familiarityForWord
            self.hasReviewCardForWord = hasReviewCardForWord
            self.onTOCLoaded = onTOCLoaded
            self.shouldAutoAdvanceForUITest = shouldAutoAdvanceForUITest
        }

        /// Fetches the TOC from JS and delivers it via `onTOCLoaded`.
        /// Called by ReaderView when the user opens the TOC panel.
        func requestTOC() {
            guard let wv = webView else { return }
            wv.evaluateJavaScript("JSON.stringify(window.getTableOfContents())") { [weak self] result, error in
                guard let self else { return }
                if let error {
                    NSLog("[Leo Bridge] requestTOC error: \(error)")
                    return
                }
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8) else {
                    NSLog("[Leo Bridge] requestTOC: unexpected result \(String(describing: result))")
                    return
                }
                let rawItems: [[String: Any]]
                do {
                    guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                        NSLog("[Leo Bridge] requestTOC: JSON root is not an array of objects")
                        return
                    }
                    rawItems = parsed
                } catch {
                    NSLog("[Leo Bridge] requestTOC: failed to parse TOC JSON: \(error)")
                    return
                }
                let items = rawItems.compactMap { d -> TOCItem? in
                    guard let label = d["label"] as? String,
                          let href = d["href"] as? String else { return nil }
                    let depth = d["depth"] as? Int ?? 0
                    return TOCItem(label: label, href: href, depth: depth)
                }
                DispatchQueue.main.async {
                    self.onTOCLoaded?(items)
                }
            }
        }

        /// Navigates the reader to a TOC item by href.
        func goToTocItem(_ href: String) {
            let encoded: Data
            let literal: String
            do {
                encoded = try JSONSerialization.data(withJSONObject: [href])
                guard let arr = String(data: encoded, encoding: .utf8) else {
                    NSLog("[Leo Bridge] goToTocItem: failed to decode JSON bytes as UTF-8 for href '\(href)'")
                    return
                }
                literal = String(arr.dropFirst().dropLast()) // strip [ ]
            } catch {
                NSLog("[Leo Bridge] goToTocItem: failed to serialize href '\(href)': \(error)")
                return
            }
            webView?.evaluateJavaScript("window.goToTocItem(\(literal))") { _, error in
                if let error {
                    NSLog("[Leo Bridge] goToTocItem error: \(error)")
                }
            }
        }

        // MARK: - Speaking highlight (TTS karaoke)

        /// Sends the currently-spoken word range to JS so it can apply the
        /// `.leo-speaking` pulse animation. Uses the same JSON-array escaping
        /// pattern as the `highlightRange` call to avoid injection issues.
        func highlightSpeakingRange(text: String, range: NSRange) {
            guard let textJSON = try? JSONSerialization.data(withJSONObject: [text]),
                  let textArr = String(data: textJSON, encoding: .utf8) else {
                NSLog("[Leo Bridge] highlightSpeakingRange: failed to serialize text")
                return
            }
            // Extract the escaped string from the JSON array: ["escaped"] → "escaped"
            let textLiteral = String(textArr.dropFirst().dropLast())
            let js = "highlightSpeakingWord(\(textLiteral), \(range.location), \(range.length))"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Removes all speaking highlights from the JS side.
        func clearSpeakingHighlight() {
            webView?.evaluateJavaScript("clearSpeakingHighlight()", completionHandler: nil)
        }

        // MARK: - Spread mode

        /// Sets the foliate-js spread mode: "none" (single page), "auto" (2-page when wide), "both" (always 2-page).
        func setSpreadMode(_ mode: String) {
            guard let encoded = try? JSONSerialization.data(withJSONObject: [mode]),
                  let arr = String(data: encoded, encoding: .utf8) else {
                NSLog("[Leo Bridge] setSpreadMode: failed to serialize mode")
                return
            }
            let literal = String(arr.dropFirst().dropLast())
            webView?.evaluateJavaScript("setSpreadMode(\(literal))") { _, error in
                if let error {
                    NSLog("[Leo Bridge] setSpreadMode JS error: \(error)")
                }
            }
        }

        // MARK: - In-book search

        /// Triggers a full-book search for `query` using foliate-js's search API.
        /// The JS side highlights all matches and navigates to the first one.
        func searchInBook(_ query: String) {
            guard let encoded = try? JSONSerialization.data(withJSONObject: [query]),
                  let arr = String(data: encoded, encoding: .utf8) else {
                NSLog("[Leo Bridge] searchInBook: failed to serialize query")
                return
            }
            let literal = String(arr.dropFirst().dropLast())
            webView?.evaluateJavaScript("searchInBook(\(literal))") { _, error in
                if let error {
                    NSLog("[Leo Bridge] searchInBook JS error: \(error)")
                }
            }
        }

        /// Clears all search highlights from the JS side.
        func clearBookSearch() {
            webView?.evaluateJavaScript("clearSearch()") { _, error in
                if let error {
                    NSLog("[Leo Bridge] clearSearch JS error: \(error)")
                }
            }
        }

        // JS → Swift messages
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "leoReader",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let payload = body["payload"] as? [String: Any] else {
                NSLog("[Leo Bridge] Invalid message: \(message.body)")
                return
            }

            switch type {
            case "ready":
                NSLog("[Leo Bridge] JS bridge ready")
                pageLoaded = true
                guard let wv = webView else { return }
                pushReaderChrome(webView: wv)
                openCurrentBook()

            case "loaded":
                let title = payload["title"] as? String ?? ""
                let chapters = payload["chapterCount"] as? Int ?? 0
                NSLog("[Leo Bridge] Book loaded: '\(title)', \(chapters) chapters")
                DispatchQueue.main.async {
                    self.onLoadSuccess()
                }

            case "chapterLoaded":
                let index = payload["index"] as? Int ?? -1
                NSLog("[Leo Bridge] Chapter \(index) loaded")

            case "wordTap":
                guard let context = payload["context"] as? String,
                      let charIndex = payload["charIndex"] as? Int,
                      let x = payload["x"] as? CGFloat,
                      let y = payload["y"] as? CGFloat else {
                    return
                }
                let char = payload["char"] as? String ?? ""
                NSLog("[Leo Bridge] Word tap: char=\(char), context=\(context.prefix(20))..., idx=\(charIndex)")

                // Resolve expression + look up dictionary on the calling thread (already main via WK)
                // resolveExpressionAtPosition tries ExpressionDetector first (e.g. 不得不)
                // then falls back to word segmentation.
                let parser = ChineseParser()
                let word = parser.resolveExpressionAtPosition(context: context, charIndex: charIndex)
                let entries = DictionaryEngine.shared.lookup(word)
                let freqData = FrequencyEngine.shared.lookup(word)
                let grammarPatterns = GrammarEngine.shared.lookup(word: word)

                NSLog("[Leo Bridge] Resolved word='\(word)', \(entries.count) entries")

                // Notify ReaderView so it can update familiarity tracker / session
                DispatchQueue.main.async {
                    self.onWordTapped(char, context, charIndex, x, y)
                }

                // Show native floating panel — replaces the in-JS popup.
                let familiarity = self.familiarityForWord(word)
                let alreadyInReview = self.hasReviewCardForWord(word)

                // Extract the sentence containing the tapped word from the context string.
                // Uses the same boundary characters as reader.js: 。！？ and newlines.
                let contextSentence: String? = {
                    let scalars = Array(context.unicodeScalars)
                    let boundaries: Set<Unicode.Scalar> = ["。", "！", "？", "\n"]
                    var start = charIndex
                    var end = charIndex
                    while start > 0 && !boundaries.contains(scalars[start - 1]) { start -= 1 }
                    while end < scalars.count && !boundaries.contains(scalars[end]) { end += 1 }
                    guard end > start else { return nil }
                    let sentence = String(String.UnicodeScalarView(scalars[start..<end]))
                    return sentence.isEmpty ? nil : sentence
                }()

                DispatchQueue.main.async {
                    self.showNativePanel(
                        word: word,
                        entries: entries,
                        grammarPatterns: grammarPatterns,
                        freqData: freqData,
                        familiarity: familiarity,
                        alreadyInReview: alreadyInReview,
                        context: context,
                        contextSentence: contextSentence,
                        webViewX: x,
                        webViewY: y
                    )
                }

                // Tell JS to highlight the resolved expression and its containing sentence.
                // Wrap strings in arrays for JSONSerialization (requires top-level Array/Dict).
                if let contextJSON = try? JSONSerialization.data(withJSONObject: [context]),
                   let contextArr = String(data: contextJSON, encoding: .utf8),
                   let wordJSON = try? JSONSerialization.data(withJSONObject: [word]),
                   let wordArr = String(data: wordJSON, encoding: .utf8) {
                    // Extract the escaped string from the JSON array: ["escaped"] → "escaped"
                    let contextLiteral = String(contextArr.dropFirst().dropLast()) // remove [ ]
                    let wordLiteral = String(wordArr.dropFirst().dropLast())
                    let highlightJS = "highlightRange(\(contextLiteral), \(wordLiteral), \(charIndex)); " +
                        "typeof highlightSentence === 'function' && highlightSentence(\(contextLiteral), \(wordLiteral), \(charIndex))"
                    DispatchQueue.main.async {
                        self.webView?.evaluateJavaScript(highlightJS) { _, error in
                            if let error {
                                NSLog("[Leo Bridge] highlight JS error: \(error)")
                            }
                        }
                    }
                }

            case "popupAction":
                let action = payload["action"] as? String ?? ""
                let word = payload["word"] as? String ?? ""
                let sentence = payload["sentence"] as? String ?? ""
                NSLog("[Leo Bridge] Popup action: \(action) for '\(word)'")
                DispatchQueue.main.async {
                    switch action {
                    case "markKnown": self.onPopupAction(.markKnown, word, sentence)
                    case "addToSRS":  self.onPopupAction(.addToSRS, word, sentence)
                    default: break
                    }
                }

            case "relocate":
                let cfi = payload["cfi"] as? String ?? ""
                let rawFraction = payload["fraction"]
                let decodedFraction: Double
                if let fraction = rawFraction as? Double {
                    decodedFraction = fraction
                } else if let number = rawFraction as? NSNumber {
                    decodedFraction = number.doubleValue
                } else {
                    decodedFraction = 0
                }
                let fraction: Double
                if decodedFraction.isFinite {
                    fraction = min(max(decodedFraction, 0), 1)
                } else {
                    NSLog("[Leo Bridge] Relocate received non-finite fraction '\(String(describing: rawFraction))'; defaulting to 0")
                    fraction = 0
                }
                let percentage = Int((fraction * 100).rounded())
                NSLog("[Leo Bridge] Relocate: \(percentage)%%, cfi=\(cfi.prefix(30))...")
                guard !cfi.isEmpty else { return }
                let locator = BookLocator(cfi: cfi, fraction: fraction, updatedAt: Date())
                DispatchQueue.main.async {
                    self.onRelocate(locator)
                }
                maybeAdvanceForUITest()

            case "error":
                let msg = payload["message"] as? String ?? "Unknown"
                let source = payload["source"] as? String ?? ""
                NSLog("[Leo Bridge] ERROR from JS: \(msg) (source: \(source))")
                DispatchQueue.main.async {
                    self.onLoadError(msg.isEmpty ? "Leo’s reader page failed to load." : msg)
                }

            default:
                NSLog("[Leo Bridge] Unknown message type: \(type)")
            }
        }

        // MARK: - Native floating panel

        /// Converts WKWebView-local coordinates to screen coordinates and shows the
        /// native FloatingDictionaryPanel near the tapped word.
        private func showNativePanel(
            word: String,
            entries: [DictionaryEngine.Entry],
            grammarPatterns: [GrammarEngine.GrammarPattern]?,
            freqData: FrequencyEngine.FrequencyData,
            familiarity: FamiliarityState,
            alreadyInReview: Bool,
            context: String,
            contextSentence: String?,
            webViewX: CGFloat,
            webViewY: CGFloat
        ) {
            // Use the actual mouse position for reliable panel placement.
            // JS-reported coordinates go through iframe→outer page→WKWebView→NSView→screen
            // conversions that are fragile. NSEvent.mouseLocation is always correct.
            let screenPoint = NSEvent.mouseLocation

            let pinyin = entries.first?.pinyinDisplay ?? ""
            let definitions = entries.flatMap(\.definitions)

            var grammarTitle: String?
            var grammarLevel: String?
            if let first = grammarPatterns?.first {
                grammarTitle = first.title
                grammarLevel = first.level
            }

            let components: [String]?
            let radical: String?
            if word.count == 1, let char = word.first {
                components = DecompositionEngine.shared.decompose(char)
                radical = DecompositionEngine.shared.radicalOf(char)
            } else {
                components = nil
                radical = nil
            }

            let lookupData = DictionaryLookupData(
                word: word,
                pinyin: pinyin,
                definitions: definitions,
                hskLevel: freqData.hskLevel,
                grammarTitle: grammarTitle,
                grammarLevel: grammarLevel,
                familiarity: familiarity,
                alreadyInReview: alreadyInReview,
                components: components,
                radical: radical,
                contextSentence: contextSentence
            )

            FloatingDictionaryController.shared.show(
                data: lookupData,
                screenPoint: screenPoint,
                onKnow: { [weak self] in
                    guard let self else { return }
                    self.onPopupAction(.markKnown, word, context)
                    FloatingDictionaryController.shared.dismiss()
                },
                onReview: { [weak self] in
                    guard let self else { return }
                    self.onPopupAction(.addToSRS, word, context)
                    FloatingDictionaryController.shared.dismiss()
                },
                onListen: {
                    NotificationCenter.default.post(name: .leoPlayTTS, object: word)
                },
                onFamiliarityChange: { [weak self] newState in
                    guard let self else { return }
                    self.onPopupAction(.setFamiliarity(newState), word, context)
                }
            )

            scheduleContextualLookup(word: word, sentence: context)
        }

        private func scheduleContextualLookup(word: String, sentence: String) {
            guard let apiKey = LeoKeychainHelper().getSecret(for: .openRouter),
                  !apiKey.isEmpty else { return }

            let model = UserDefaults.standard.string(forKey: "leo.lookupModel") ?? "qwen/qwen-2.5-72b-instruct"
            Task { [weak self] in
                guard self != nil else { return }
                do {
                    let text = try await OpenRouterLookupService.fetchContextualMeaning(
                        word: word,
                        sentence: sentence,
                        apiKey: apiKey,
                        model: model
                    )
                    // Post notification so any subscriber (e.g. a future contextual
                    // definition pane) can consume the AI-enriched context.
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .leoContextualDefinitionReady,
                            object: nil,
                            userInfo: ["word": word, "context": text]
                        )
                    }
                } catch {
                    NSLog("[Leo Bridge] OpenRouter: \(error.localizedDescription)")
                }
            }
        }

        // MARK: - Book opening

        private func openCurrentBook() {
            guard let bookURL = LocalServer.shared.bookURL(id: bookId) else {
                NSLog("[Leo Bridge] ERROR: No URL for book \(bookId)")
                return
            }
            let requestJSON: String
            do {
                let requestData = try JSONSerialization.data(withJSONObject: [
                    "url": bookURL.absoluteString,
                    "locator": initialLocator?.cfi ?? "",
                ])
                guard let str = String(data: requestData, encoding: .utf8) else {
                    NSLog("[Leo Bridge] openCurrentBook: failed to decode request JSON as UTF-8")
                    onLoadError("Leo couldn’t prepare the selected book for reading.")
                    return
                }
                requestJSON = str
            } catch {
                NSLog("[Leo Bridge] openCurrentBook: failed to serialize book request: \(error)")
                onLoadError("Leo couldn’t prepare the selected book for reading.")
                return
            }
            let js = "openBook(\(requestJSON))"
            NSLog("[Leo Bridge] Opening book: \(js)")
            webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    NSLog("[Leo Bridge] evaluateJavaScript error: \(error)")
                    DispatchQueue.main.async {
                        self.onLoadError(error.localizedDescription)
                    }
                }
            }
        }

        private func maybeAdvanceForUITest() {
            guard shouldAutoAdvanceForUITest,
                  !didAutoAdvanceForUITest,
                  initialLocator == nil else { return }

            didAutoAdvanceForUITest = true
            let script = "window.goToFraction ? window.goToFraction(0.55) : window.nextPage()"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.webView?.evaluateJavaScript(script) { _, error in
                    if let error {
                        NSLog("[Leo Bridge] UI test auto-advance failed: \(error)")
                    }
                }
            }
        }

        // WKNavigationDelegate — catch load errors
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[Leo WebView] Navigation failed: \(error)")
            onLoadError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[Leo WebView] Provisional navigation failed: \(error)")
            onLoadError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("[Leo WebView] Page loaded successfully")
        }

        /// Push theme + Reading settings into `reader.js` (`setTheme` + `applyReadingPreferences`).
        func pushReaderChrome(webView: WKWebView) {
            // Apple Books–matched theme colors (see `ReadingTheme+Leo.swift`)
            let themeData: [String: String] = [
                "bg": latestTheme.foliateBackgroundHex,
                "fg": latestTheme.foliateForegroundHex,
            ]
            let themeStr: String
            do {
                let themeJSON = try JSONSerialization.data(withJSONObject: themeData)
                guard let str = String(data: themeJSON, encoding: .utf8) else {
                    NSLog("[Leo Bridge] pushReaderChrome: theme JSON not valid UTF-8")
                    return
                }
                themeStr = str
            } catch {
                NSLog("[Leo Bridge] pushReaderChrome: failed to serialize theme: \(error)")
                return
            }

            let prefs: [String: Any] = [
                "fontSizePt": latestReading.fontSize,
                "lineHeight": latestReading.lineHeight,
                "textDirection": latestReading.textDirection,
                "showPinyin": false,
                "showHighlights": latestReading.showHighlights,
                "pageStyle": latestReading.pageStyle,
            ]
            let prefsStr: String
            do {
                let prefsJSON = try JSONSerialization.data(withJSONObject: prefs)
                guard let str = String(data: prefsJSON, encoding: .utf8) else {
                    NSLog("[Leo Bridge] pushReaderChrome: prefs JSON not valid UTF-8")
                    return
                }
                prefsStr = str
            } catch {
                NSLog("[Leo Bridge] pushReaderChrome: failed to serialize prefs: \(error)")
                return
            }

            // Wrap the spread mode string in an array for JSONSerialization (requires top-level Array/Dict),
            // then extract the escaped string.
            let spreadLiteral: String
            if let spreadData = try? JSONSerialization.data(withJSONObject: [latestReading.spreadMode]),
               let spreadArr = String(data: spreadData, encoding: .utf8) {
                spreadLiteral = String(spreadArr.dropFirst().dropLast()) // strip [ ]
            } else {
                spreadLiteral = "\"auto\""
            }

            let js = "setTheme(\(themeStr)); applyReadingPreferences(\(prefsStr)); window.__leoSpreadMode = \(spreadLiteral); if(typeof setSpreadMode==='function') setSpreadMode(\(spreadLiteral));"
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    NSLog("[Leo Bridge] pushReaderChrome: \(error)")
                }
            }
            lastPushedTheme = latestTheme.rawValue
            lastPushedChrome = latestReading
        }
    }
}
