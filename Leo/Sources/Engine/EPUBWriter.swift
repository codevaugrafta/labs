import Foundation

/// Writes a minimal valid EPUB 3 (reflowable) using `/usr/bin/zip` on a staging directory.
struct EPUBWriter: Sendable {

    enum EPUBWriterError: LocalizedError {
        case emptyManuscript
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyManuscript: "No extractable text from PDF"
            case .zipFailed(let msg): msg
            }
        }
    }

    /// - Parameters:
    ///   - title: dc:title
    ///   - chapterFileName: e.g. `chapter001.xhtml`
    ///   - chapterXHTML: full document
    ///   - navXHTML: navigation document with `properties="nav"` in manifest
    ///   - language: dc:language
    ///   - outputURL: final `.epub` path (file replaced if present)
    func writeEPUB(
        title: String,
        chapterFileName: String,
        chapterXHTML: String,
        navXHTML: String,
        language: String,
        outputURL: URL
    ) throws {
        guard !chapterXHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EPUBWriterError.emptyManuscript
        }

        let id = "book-\(UUID().uuidString)"
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("leo-epub-\(UUID().uuidString)", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let metaInf = staging.appendingPathComponent("META-INF", isDirectory: true)
        let oebps = staging.appendingPathComponent("OEBPS", isDirectory: true)
        try fm.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)

        try "application/epub+zip".write(to: staging.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)

        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try container.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let escTitle = title.xmlEscaped
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="BookId">\(id.xmlEscaped)</dc:identifier>
            <dc:title>\(escTitle)</dc:title>
            <dc:language>\(language.xmlEscaped)</dc:language>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
            <item id="main" href="\(chapterFileName.xmlEscaped)" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="main"/>
          </spine>
        </package>
        """
        try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        try chapterXHTML.write(to: oebps.appendingPathComponent(chapterFileName), atomically: true, encoding: .utf8)
        try navXHTML.write(to: oebps.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)

        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        try zipEPUB(stagingDir: staging, outputURL: outputURL)
        try? fm.removeItem(at: staging)
    }

    private func zipEPUB(stagingDir: URL, outputURL: URL) throws {
        let proc1 = Process()
        proc1.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc1.arguments = ["-0Xq", outputURL.path, "mimetype"]
        proc1.currentDirectoryURL = stagingDir
        try proc1.run()
        proc1.waitUntilExit()
        if proc1.terminationStatus != 0 { throw EPUBWriterError.zipFailed("zip mimetype failed") }

        let proc2 = Process()
        proc2.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc2.arguments = ["-Xrq", outputURL.path, "META-INF", "OEBPS"]
        proc2.currentDirectoryURL = stagingDir
        try proc2.run()
        proc2.waitUntilExit()
        if proc2.terminationStatus != 0 { throw EPUBWriterError.zipFailed("zip bundle failed") }
    }
}
