import SwiftUI
import WebKit

/// EPUB reader powered by foliate-js via localhost HTTP server.
/// Dictionary lookups are shown as a floating HTML popup rendered inside the WKWebView,
/// positioned near the tapped word. No SwiftUI overlay is needed.
struct FoliateReaderView: NSViewRepresentable {
    let bookFilePath: String
    let bookId: String
    let theme: ReadingTheme

    /// Called when the user taps a word. The coordinator performs a dictionary lookup
    /// and renders the popup directly in JS. This closure receives the resolved word,
    /// entries, and coordinates so that ReaderView can keep its session/familiarity state.
    let onWordTapped: (String, String, Int, CGFloat, CGFloat) -> Void

    /// Called when the user presses "I know this" or "Add to review" inside the JS popup.
    /// The ReaderView uses this to drive FamiliarityTracker / FSRSEngine.
    let onPopupAction: (_ action: PopupAction, _ word: String) -> Void

    enum PopupAction {
        case markKnown
        case addToSRS
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWordTapped: onWordTapped, onPopupAction: onPopupAction)
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
        }

        context.coordinator.webView = webView
        context.coordinator.bookId = bookId
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // If book changed, reload
        if context.coordinator.bookId != bookId {
            context.coordinator.bookId = bookId
            LocalServer.shared.registerBook(id: bookId, filePath: bookFilePath)
            if let readerURL = LocalServer.shared.readerURL {
                webView.load(URLRequest(url: readerURL))
            }
        }

        // Apply theme changes
        if context.coordinator.currentTheme != theme.rawValue {
            context.coordinator.currentTheme = theme.rawValue
            let themeData: [String: String] = switch theme {
            case .light: ["bg": "#FFFFFF", "fg": "#1A1A1A"]
            case .dark: ["bg": "#1E1E1E", "fg": "#D4D4D4"]
            case .sepia: ["bg": "#F5EDDC", "fg": "#4A3520"]
            }
            let json = try? JSONSerialization.data(withJSONObject: themeData)
            if let json, let jsonStr = String(data: json, encoding: .utf8) {
                webView.evaluateJavaScript("setTheme(\(jsonStr))")
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onWordTapped: (String, String, Int, CGFloat, CGFloat) -> Void
        let onPopupAction: (PopupAction, String) -> Void
        weak var webView: WKWebView?
        var bookId: String = ""
        var currentTheme: String = "light"
        private var pageLoaded = false

        init(
            onWordTapped: @escaping (String, String, Int, CGFloat, CGFloat) -> Void,
            onPopupAction: @escaping (PopupAction, String) -> Void
        ) {
            self.onWordTapped = onWordTapped
            self.onPopupAction = onPopupAction
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
                openCurrentBook()

            case "loaded":
                let title = payload["title"] as? String ?? ""
                let chapters = payload["chapterCount"] as? Int ?? 0
                NSLog("[Leo Bridge] Book loaded: '\(title)', \(chapters) chapters")

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

                // Resolve word + look up dictionary on the calling thread (already main via WK)
                let parser = ChineseParser()
                let word = parser.resolveWordAtPosition(context: context, charIndex: charIndex)
                let entries = DictionaryEngine.shared.lookup(word)
                let freqData = FrequencyEngine.shared.lookup(word)

                NSLog("[Leo Bridge] Resolved word='\(word)', \(entries.count) entries")

                // Notify ReaderView so it can update familiarity tracker / session
                DispatchQueue.main.async {
                    self.onWordTapped(char, context, charIndex, x, y)
                }

                // Build popup data and call showPopup() in JS
                showPopupInJS(word: word, entries: entries, freqData: freqData, x: x, y: y)

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

            case "error":
                let msg = payload["message"] as? String ?? "Unknown"
                let source = payload["source"] as? String ?? ""
                NSLog("[Leo Bridge] ERROR from JS: \(msg) (source: \(source))")

            default:
                NSLog("[Leo Bridge] Unknown message type: \(type)")
            }
        }

        // MARK: - In-JS popup

        private func showPopupInJS(
            word: String,
            entries: [DictionaryEngine.Entry],
            freqData: FrequencyEngine.FrequencyData,
            x: CGFloat,
            y: CGFloat
        ) {
            let pinyin = entries.first?.pinyinDisplay ?? ""
            let definitions = entries.prefix(2).flatMap { $0.definitions.prefix(4) }
            var popupData: [String: Any] = [
                "word": word,
                "pinyin": pinyin,
                "definitions": Array(definitions),
                "frequencyTier": freqData.tier.rawValue,
                "frequencyColor": freqData.tier.color,
            ]
            if let hsk = freqData.hskLevel {
                popupData["hskLevel"] = hsk
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: popupData),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else {
                NSLog("[Leo Bridge] Failed to serialize popup data")
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
        }

        // MARK: - Book opening

        private func openCurrentBook() {
            guard let bookURL = LocalServer.shared.bookURL(id: bookId) else {
                NSLog("[Leo Bridge] ERROR: No URL for book \(bookId)")
                return
            }
            let js = "openBook('\(bookURL.absoluteString)')"
            NSLog("[Leo Bridge] Opening book: \(js)")
            webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    NSLog("[Leo Bridge] evaluateJavaScript error: \(error)")
                }
            }
        }

        // WKNavigationDelegate — catch load errors
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[Leo WebView] Navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[Leo WebView] Provisional navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("[Leo WebView] Page loaded successfully")
            pageLoaded = true
        }
    }
}
