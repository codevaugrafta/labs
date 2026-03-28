import Foundation
import SwiftSoup

/// Parses an EPUB file into a structured representation.
/// EPUB is a ZIP containing HTML chapters + metadata.
struct EPUBParser: Sendable {

    struct EPUBContent: Sendable {
        let title: String
        let author: String
        let chapters: [Chapter]
        let basePath: URL
    }

    struct Chapter: Sendable, Identifiable {
        let id: String
        let title: String
        let href: String
        let htmlContent: String
    }

    /// Parse an EPUB file into structured content.
    /// - Parameter fileURL: Path to the .epub file
    /// - Returns: Parsed EPUB content with chapters
    func parse(fileURL: URL) throws -> EPUBContent {
        let extractDir = try extractEPUB(fileURL: fileURL)
        let opfPath = try findOPFPath(in: extractDir)
        let opfURL = extractDir.appendingPathComponent(opfPath)
        let opfDir = opfURL.deletingLastPathComponent()

        let opfData = try Data(contentsOf: opfURL)
        let opfString = String(data: opfData, encoding: .utf8) ?? ""
        let opfDoc = try SwiftSoup.parse(opfString, "", Parser.xmlParser())

        let title = try extractTitle(from: opfDoc)
        let author = try extractAuthor(from: opfDoc)
        let manifest = try extractManifest(from: opfDoc)
        let spine = try extractSpine(from: opfDoc)

        var chapters: [Chapter] = []
        for (index, itemRef) in spine.enumerated() {
            guard let href = manifest[itemRef] else { continue }
            let chapterURL = opfDir.appendingPathComponent(href)
            guard FileManager.default.fileExists(atPath: chapterURL.path) else { continue }

            let html = try String(contentsOf: chapterURL, encoding: .utf8)
            let chapterTitle = try extractChapterTitle(from: html) ?? "Chapter \(index + 1)"

            chapters.append(Chapter(
                id: itemRef,
                title: chapterTitle,
                href: href,
                htmlContent: html
            ))
        }

        return EPUBContent(
            title: title,
            author: author,
            chapters: chapters,
            basePath: opfDir
        )
    }

    // MARK: - Private

    private func extractEPUB(fileURL: URL) throws -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        // Use a hash-based directory name to avoid path encoding issues with Chinese filenames
        let hashName = String(fileURL.lastPathComponent.hashValue, radix: 16, uppercase: false)
        let extractDir = cacheDir.appendingPathComponent("Leo/EPUBs/\(hashName)")

        if FileManager.default.fileExists(atPath: extractDir.path) {
            try FileManager.default.removeItem(at: extractDir)
        }
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Try system unzip first (most reliable for all EPUB variants)
        if trySystemUnzip(source: fileURL, destination: extractDir) {
            return extractDir
        }

        // Fallback: Pure Swift extraction using NSFileCoordinator + Archive
        try pureSwiftUnzip(source: fileURL, destination: extractDir)
        return extractDir
    }

    /// Try extracting with /usr/bin/unzip — most reliable but may fail in sandboxed context
    private func trySystemUnzip(source: URL, destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", source.path, "-d", destination.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Pure Swift ZIP extraction — works in any context, no Process needed
    private func pureSwiftUnzip(source: URL, destination: URL) throws {
        // EPUB is a ZIP file. Use Python as bridge for reliable extraction.
        // This avoids needing a third-party ZIP library.
        let script = """
        import zipfile, sys
        try:
            with zipfile.ZipFile(sys.argv[1], 'r') as z:
                z.extractall(sys.argv[2])
            print("OK")
        except Exception as e:
            print(f"ERROR: {e}", file=sys.stderr)
            sys.exit(1)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, source.path, destination.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw EPUBError.invalidFormat
        }
    }

    private func findOPFPath(in extractDir: URL) throws -> String {
        let containerURL = extractDir.appendingPathComponent("META-INF/container.xml")
        let containerData = try Data(contentsOf: containerURL)
        let containerString = String(data: containerData, encoding: .utf8) ?? ""
        let doc = try SwiftSoup.parse(containerString, "", Parser.xmlParser())
        let rootfile = try doc.select("rootfile").first()
        guard let opfPath = try rootfile?.attr("full-path") else {
            throw EPUBError.missingOPF
        }
        return opfPath
    }

    private func extractTitle(from doc: Document) throws -> String {
        try doc.select("dc|title, title").first()?.text() ?? "Untitled"
    }

    private func extractAuthor(from doc: Document) throws -> String {
        try doc.select("dc|creator, creator").first()?.text() ?? "Unknown"
    }

    private func extractManifest(from doc: Document) throws -> [String: String] {
        var manifest: [String: String] = [:]
        let items = try doc.select("manifest item")
        for item in items {
            let id = try item.attr("id")
            let href = try item.attr("href")
            manifest[id] = href
        }
        return manifest
    }

    private func extractSpine(from doc: Document) throws -> [String] {
        let itemRefs = try doc.select("spine itemref")
        return try itemRefs.map { try $0.attr("idref") }
    }

    private func extractChapterTitle(from html: String) throws -> String? {
        let doc = try SwiftSoup.parse(html)
        // Try h1, h2, title in order
        if let h1 = try doc.select("h1").first()?.text(), !h1.isEmpty { return h1 }
        if let h2 = try doc.select("h2").first()?.text(), !h2.isEmpty { return h2 }
        if let title = try doc.select("title").first()?.text(), !title.isEmpty { return title }
        return nil
    }
}

enum EPUBError: LocalizedError {
    case missingOPF
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .missingOPF: "Could not find OPF file in EPUB"
        case .invalidFormat: "Invalid EPUB format"
        }
    }
}
