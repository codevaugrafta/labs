import Foundation
import Testing
@testable import Leo

@Suite("EPUB cover extraction")
struct EPUBCoverExtractorTests {
    /// 1×1 transparent PNG (minimal valid file).
    private static let tinyPNG: Data = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
    ])

    @Test("Extracts cover from minimal EPUB (cover-image property)")
    func extractsCoverFromMinimalEPUB() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("leo-cover-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let epubURL = try Self.buildMinimalEPUB(in: base)
        let coversDir = base.appendingPathComponent("Covers", isDirectory: true)
        let id = UUID()

        let path = EPUBCoverExtractor.extractCover(
            epubPath: epubURL.path,
            bookID: id,
            coversDirectory: coversDir,
            fileManager: fm
        )

        #expect(path != nil)
        guard let coverPath = path else { return }
        #expect(fm.fileExists(atPath: coverPath))
        #expect(coverPath.hasSuffix(".png"))
        let attrs = try fm.attributesOfItem(atPath: coverPath)
        let size = attrs[.size] as? UInt64 ?? 0
        #expect(size > 0)
    }

    @Test("EPUB 2 meta name=cover resolves href")
    func extractsCoverFromEPUB2StyleMeta() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("leo-cover-epub2-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let epubURL = try Self.buildEPUB2StyleCoverMeta(in: base)
        let coversDir = base.appendingPathComponent("Covers", isDirectory: true)
        let path = EPUBCoverExtractor.extractCover(
            epubPath: epubURL.path,
            bookID: UUID(),
            coversDirectory: coversDir,
            fileManager: fm
        )
        #expect(path != nil)
        guard let coverPath = path else { return }
        #expect(fm.fileExists(atPath: coverPath))
    }

    // MARK: - Fixture builders

    private static func buildMinimalEPUB(in base: URL) throws -> URL {
        let work = base.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        try Data("application/epub+zip".utf8).write(to: work.appendingPathComponent("mimetype"))
        let meta = work.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try container.write(to: meta.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let oebps = work.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
        try tinyPNG.write(to: oebps.appendingPathComponent("cover.png"))

        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title></head><body><p>x</p></body></html>
        """
        try chapter.write(to: oebps.appendingPathComponent("chapter.xhtml"), atomically: true, encoding: .utf8)

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>T</dc:title>
            <dc:language>en</dc:language>
            <dc:identifier id="bookid">id</dc:identifier>
          </metadata>
          <manifest>
            <item id="img" href="cover.png" media-type="image/png" properties="cover-image"/>
            <item id="h" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="h"/></spine>
        </package>
        """
        try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        let epubOut = base.appendingPathComponent("minimal.epub")
        try zipEPUB(staging: work, output: epubOut)
        return epubOut
    }

    private static func buildEPUB2StyleCoverMeta(in base: URL) throws -> URL {
        let work = base.appendingPathComponent("staging2", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        try Data("application/epub+zip".utf8).write(to: work.appendingPathComponent("mimetype"))
        let meta = work.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try container.write(to: meta.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        let oebps = work.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
        let images = oebps.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try tinyPNG.write(to: images.appendingPathComponent("front.png"))

        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title></head><body><p>x</p></body></html>
        """
        try chapter.write(to: oebps.appendingPathComponent("chapter.xhtml"), atomically: true, encoding: .utf8)

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>T</dc:title>
            <dc:language>en</dc:language>
            <dc:identifier id="bookid">id</dc:identifier>
            <meta name="cover" content="covid"/>
          </metadata>
          <manifest>
            <item id="covid" href="images/front.png" media-type="image/png"/>
            <item id="h" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="h"/></spine>
        </package>
        """
        try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        let epubOut = base.appendingPathComponent("epub2meta.epub")
        try zipEPUB(staging: work, output: epubOut)
        return epubOut
    }

    private static func zipEPUB(staging work: URL, output epubOut: URL) throws {
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = work
        zip.arguments = ["-q", "-r", epubOut.path, "mimetype", "META-INF", "OEBPS"]
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
    }
}
