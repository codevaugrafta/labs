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
    var showPinyin: Bool
    var showHighlights: Bool

    static let defaultPrefs = LeoReadingChromePreferences(
        fontSize: 18,
        lineHeight: 1.7,
        textDirection: "horizontal",
        showPinyin: false,
        showHighlights: true
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
    let onPopupAction: (_ action: PopupAction, _ word: String) -> Void

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
        let onPopupAction: (PopupAction, String) -> Void
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
            onPopupAction: @escaping (PopupAction, String) -> Void,
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
                encoded = try JSONSerialization.data(withJSONObject: href)
                guard let str = String(data: encoded, encoding: .utf8) else {
                    NSLog("[Leo Bridge] goToTocItem: failed to decode JSON bytes as UTF-8 for href '\(href)'")
                    return
                }
                literal = str
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
                maybeAdvanceForUITest()

            case "wordTap":
                guard let context = payload["context"] as? String,
                      let charIndex = payload["charIndex"] as? Int,
                      let x = payload["x"] as? CGFloat,
                      let y = payload["y"] as? CGFloat else {
                    return
                }
                let char = payload["char"] as? String ?? ""
                NSLog("[Leo Bridge] Word tap: char=\(char), context=\(context.prefix(20))..., idx=\(charIndex)")

                // Resolve word + look up dictionary on the calling thread (already main via WK)
                let parser = ChineseParser()
                let word = parser.resolveWordAtPosition(context: context, charIndex: charIndex)
                let entries = DictionaryEngine.shared.lookup(word)
                let freqData = FrequencyEngine.shared.lookup(word)
                let grammarPatterns = GrammarEngine.shared.lookup(word: word)

                NSLog("[Leo Bridge] Resolved word='\(word)', \(entries.count) entries")

                // Notify ReaderView so it can update familiarity tracker / session
                DispatchQueue.main.async {
                    self.onWordTapped(char, context, charIndex, x, y)
                }

                // Build popup data and call showPopup() in JS
                let familiarity = self.familiarityForWord(word)
                let pinyinForPopup = self.latestReading.showPinyin
                    ? (entries.first?.pinyinDisplay ?? "")
                    : ""
                showPopupInJS(
                    word: word,
                    pinyin: pinyinForPopup,
                    context: context,
                    entries: entries,
                    freqData: freqData,
                    familiarity: familiarity,
                    grammarPatterns: grammarPatterns,
                    x: x,
                    y: y
                )

            case "popupAction":
                let action = payload["action"] as? String ?? ""
                let word = payload["word"] as? String ?? ""
                NSLog("[Leo Bridge] Popup action: \(action) for '\(word)'")
                DispatchQueue.main.async {
                    switch action {
                    case "markKnown": self.onPopupAction(.markKnown, word)
                    case "addToSRS":  self.onPopupAction(.addToSRS, word)
                    default: break
                    }
                }

            case "relocate":
                let cfi = payload["cfi"] as? String ?? ""
                let fraction = payload["fraction"] as? Double ?? 0
                NSLog("[Leo Bridge] Relocate: \(Int(fraction * 100))%, cfi=\(cfi.prefix(30))...")
                guard !cfi.isEmpty else { return }
                let locator = BookLocator(cfi: cfi, fraction: fraction, updatedAt: Date())
                DispatchQueue.main.async {
                    self.onRelocate(locator)
                }

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

        // MARK: - In-JS popup

        private func showPopupInJS(
            word: String,
            pinyin: String,
            context: String,
            entries: [DictionaryEngine.Entry],
            freqData: FrequencyEngine.FrequencyData,
            familiarity: FamiliarityState,
            grammarPatterns: [GrammarEngine.GrammarPattern]?,
            x: CGFloat,
            y: CGFloat
        ) {
            let definitions = entries.prefix(2).flatMap { $0.definitions.prefix(4) }
            let alreadyInReview = hasReviewCardForWord(word)
            var popupData: [String: Any] = [
                "word": word,
                "pinyin": pinyin,
                "definitions": Array(definitions),
                "frequencyTier": freqData.tier.rawValue,
                "frequencyColor": freqData.tier.color,
                "familiarityLabel": familiarity.label,
                "canMarkKnown": familiarity != .known,
                "alreadyInReview": alreadyInReview,
            ]
            if let hsk = freqData.hskLevel {
                popupData["hskLevel"] = hsk
            }
            // Include up to 2 matching grammar patterns in popup data
            if let patterns = grammarPatterns, !patterns.isEmpty {
                let grammarPayload: [[String: Any]] = patterns.prefix(2).map { p in
                    [
                        "title": p.title,
                        "level": p.level,
                        "structure": p.structure,
                        "description": String(p.description.prefix(200)),
                    ]
                }
                popupData["grammar"] = grammarPayload
            }

            let jsonStr: String
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: popupData)
                guard let str = String(data: jsonData, encoding: .utf8) else {
                    NSLog("[Leo Bridge] showPopupInJS: popup JSON not valid UTF-8 for word '\(word)'")
                    return
                }
                jsonStr = str
            } catch {
                NSLog("[Leo Bridge] showPopupInJS: failed to serialize popup data for word '\(word)': \(error)")
                return
            }

            let js = "showPopup(\(x), \(y), \(jsonStr))"
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js) { _, error in
                    if let error {
                        NSLog("[Leo Bridge] showPopup JS error: \(error)")
                    }
                }
            }

            scheduleContextualLookup(word: word, sentence: context)
        }

        private func scheduleContextualLookup(word: String, sentence: String) {
            guard let apiKey = LeoKeychainHelper().getSecret(for: .openRouter),
                  !apiKey.isEmpty else { return }

            let model = UserDefaults.standard.string(forKey: "leo.lookupModel") ?? "qwen/qwen-2.5-72b-instruct"
            Task { [weak self] in
                do {
                    let text = try await OpenRouterLookupService.fetchContextualMeaning(
                        word: word,
                        sentence: sentence,
                        apiKey: apiKey,
                        model: model
                    )
                    let jsLiteral: String
                    do {
                        let encoded = try JSONSerialization.data(withJSONObject: text)
                        guard let str = String(data: encoded, encoding: .utf8) else {
                            NSLog("[Leo Bridge] scheduleContextualLookup: context JSON not valid UTF-8 for word '\(word)'")
                            return
                        }
                        jsLiteral = str
                    } catch {
                        NSLog("[Leo Bridge] scheduleContextualLookup: failed to serialize context for word '\(word)': \(error)")
                        return
                    }
                    await MainActor.run {
                        self?.webView?.evaluateJavaScript("updatePopupContext(\(jsLiteral))") { _, error in
                            if let error {
                                NSLog("[Leo Bridge] updatePopupContext error: \(error)")
                            }
                        }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.webView?.evaluateJavaScript("window.nextPage()") { _, error in
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
            let themeData: [String: String] = switch latestTheme {
            case .light: ["bg": "#FFFFFF", "fg": "#1A1A1A"]
            case .dark: ["bg": "#1E1E1E", "fg": "#D4D4D4"]
            case .sepia: ["bg": "#F5EDDC", "fg": "#4A3520"]
            }
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
                "showPinyin": latestReading.showPinyin,
                "showHighlights": latestReading.showHighlights,
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

            let js = "setTheme(\(themeStr)); applyReadingPreferences(\(prefsStr));"
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
