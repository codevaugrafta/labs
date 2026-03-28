import SwiftUI
import WebKit

/// EPUB reader powered by foliate-js via localhost HTTP server.
/// This replaces the broken custom EPUBParser + WKWebView loadHTMLString approach.
struct FoliateReaderView: NSViewRepresentable {
    let bookFilePath: String
    let bookId: String
    let theme: ReadingTheme
    let onWordTapped: (String, String, Int, CGFloat, CGFloat) -> Void // word, context, charIndex, x, y

    func makeCoordinator() -> Coordinator {
        Coordinator(onWordTapped: onWordTapped)
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
        weak var webView: WKWebView?
        var bookId: String = ""
        var currentTheme: String = "light"
        private var pageLoaded = false

        init(onWordTapped: @escaping (String, String, Int, CGFloat, CGFloat) -> Void) {
            self.onWordTapped = onWordTapped
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
                DispatchQueue.main.async {
                    self.onWordTapped(char, context, charIndex, x, y)
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
