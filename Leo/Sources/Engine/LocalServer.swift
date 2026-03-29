import Foundation
import Swifter

/// Embedded localhost HTTP server for serving web content to WKWebView.
/// Solves: Web Crypto secure context, ES6 module CORS, WKWebView sandbox issues.
final class LocalServer: @unchecked Sendable {
    struct StartResult: Equatable {
        let port: UInt16
        let readerURL: URL
    }

    enum LocalServerError: LocalizedError {
        case missingReaderBundle(String)
        case failedToBind(String)
        case invalidAssignedPort

        var errorDescription: String? {
            switch self {
            case .missingReaderBundle(let path):
                "Leo couldn’t load reader resources from \(path). Rebuild the app bundle and try again."
            case .failedToBind(let details):
                "Leo couldn’t start its embedded reader server: \(details)"
            case .invalidAssignedPort:
                "Leo’s embedded reader server started without a usable loopback port."
            }
        }
    }

    static let shared = LocalServer()

    private var server: HttpServer?
    private(set) var port: UInt16 = 0
    private var webRoot: String = ""
    private var bookPaths: [String: String] = [:]

    private init() {}

    @discardableResult
    func start(webResourcesPath: String, forceRestart: Bool = false) throws -> StartResult {
        if forceRestart {
            stop()
        }

        if let readerURL, server != nil {
            return StartResult(port: port, readerURL: readerURL)
        }

        guard FileManager.default.fileExists(atPath: webResourcesPath + "/reader.html") else {
            throw LocalServerError.missingReaderBundle(webResourcesPath)
        }

        webRoot = webResourcesPath

        let httpServer = HttpServer()
        // Swifter defaults to INADDR_ANY when listen address is nil — bind loopback only.
        httpServer.listenAddressIPv4 = "127.0.0.1"

        // Catch-all: serve web resources for any path starting with /web/
        httpServer.notFoundHandler = { [weak self] request in
            guard let self else { return HttpResponse.notFound }
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

                return HttpResponse.raw(200, "OK", self.responseHeaders(contentType: mimeType)) { writer in
                    try writer.write(data)
                }
            }

            return HttpResponse.notFound
        }

        // Book files by ID
        httpServer["/book/:id"] = { [weak self] request in
            guard let self,
                  let bookId = request.params[":id"],
                  let filePath = self.bookPaths[bookId],
                  let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                return .notFound
            }
            let ext = (filePath as NSString).pathExtension.lowercased()
            let mimeType = ext == "epub" ? "application/epub+zip" : "application/pdf"
            return HttpResponse.raw(200, "OK", self.responseHeaders(contentType: mimeType)) { writer in
                try writer.write(data)
            }
        }

        do {
            try httpServer.start(0, forceIPv4: true, priority: .userInitiated)
            let assignedPort = try httpServer.port()
            guard assignedPort > 0, let port = UInt16(exactly: assignedPort) else {
                httpServer.stop()
                throw LocalServerError.invalidAssignedPort
            }

            server = httpServer
            self.port = port
            NSLog("[Leo Server] Started on http://127.0.0.1:\(port)")
            guard let readerURL else {
                throw LocalServerError.invalidAssignedPort
            }
            return StartResult(port: port, readerURL: readerURL)
        } catch let error as LocalServerError {
            throw error
        } catch {
            httpServer.stop()
            throw LocalServerError.failedToBind(error.localizedDescription)
        }
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
        port = 0
        NSLog("[Leo Server] Stopped")
    }

    /// CORS: restrict to this app’s WebView origin (loopback + bound port). Omit header if port not ready.
    private func responseHeaders(contentType: String) -> [String: String] {
        var headers: [String: String] = ["Content-Type": contentType]
        if port > 0 {
            headers["Access-Control-Allow-Origin"] = "http://127.0.0.1:\(port)"
        }
        return headers
    }
}
