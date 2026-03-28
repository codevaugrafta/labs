import Foundation
import Swifter

/// Embedded localhost HTTP server for serving web content to WKWebView.
/// Solves: Web Crypto secure context, ES6 module CORS, WKWebView sandbox issues.
final class LocalServer: @unchecked Sendable {
    static let shared = LocalServer()

    private var server: HttpServer?
    private(set) var port: UInt16 = 0
    private var webRoot: String = ""
    private var bookPaths: [String: String] = [:]

    private init() {}

    func start(webResourcesPath: String) {
        guard server == nil else { return }
        webRoot = webResourcesPath

        let httpServer = HttpServer()

        // Catch-all: serve web resources for any path starting with /web/
        httpServer.notFoundHandler = { request in
            let path = request.path

            // Handle /web/ paths — serve files from the web resources directory
            if path.hasPrefix("/web/") {
                let relativePath = String(path.dropFirst("/web/".count))
                let filePath = webResourcesPath + "/" + relativePath

                guard FileManager.default.fileExists(atPath: filePath),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                    return .notFound
                }

                let ext = (filePath as NSString).pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "html": mimeType = "text/html; charset=utf-8"
                case "js", "mjs": mimeType = "application/javascript; charset=utf-8"
                case "css": mimeType = "text/css; charset=utf-8"
                case "json": mimeType = "application/json; charset=utf-8"
                case "woff2": mimeType = "font/woff2"
                case "woff": mimeType = "font/woff"
                case "ttf": mimeType = "font/ttf"
                case "svg": mimeType = "image/svg+xml"
                case "png": mimeType = "image/png"
                case "jpg", "jpeg": mimeType = "image/jpeg"
                default: mimeType = "application/octet-stream"
                }

                return HttpResponse.raw(200, "OK", [
                    "Content-Type": mimeType,
                    "Access-Control-Allow-Origin": "*",
                ]) { writer in
                    try writer.write(data)
                }
            }

            return .notFound
        }

        // Book files by ID
        httpServer["/book/:id"] = { [weak self] request in
            guard let bookId = request.params[":id"],
                  let filePath = self?.bookPaths[bookId],
                  let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                return .notFound
            }
            let ext = (filePath as NSString).pathExtension.lowercased()
            let mimeType = ext == "epub" ? "application/epub+zip" : "application/pdf"
            return HttpResponse.raw(200, "OK", [
                "Content-Type": mimeType,
                "Access-Control-Allow-Origin": "*",
            ]) { writer in
                try writer.write(data)
            }
        }

        // Start on available port
        for tryPort: UInt16 in 8700...8750 {
            do {
                try httpServer.start(tryPort, forceIPv4: true, priority: .userInitiated)
                server = httpServer
                port = tryPort
                NSLog("[Leo Server] Started on http://127.0.0.1:\(port)")
                return
            } catch {
                continue
            }
        }
        NSLog("[Leo Server] ERROR: Could not find available port")
    }

    func registerBook(id: String, filePath: String) {
        bookPaths[id] = filePath
    }

    var readerURL: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/web/reader.html")
    }

    func bookURL(id: String) -> URL? {
        guard port > 0, bookPaths[id] != nil else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/book/\(id)")
    }

    func stop() {
        server?.stop()
        server = nil
        NSLog("[Leo Server] Stopped")
    }
}
