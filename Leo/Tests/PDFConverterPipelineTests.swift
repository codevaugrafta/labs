import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Leo

/// Programmatic PDFs with real text operators (PDFKit string extraction), plus pipeline golden checks.
@Suite("PDF converter pipeline")
struct PDFConverterPipelineTests {

    /// `CGContext` PDF creation is not reliably thread-safe across parallel tests; serialize fixtures.
    private static let pdfFixtureLock = NSLock()

    /// One “page” string → one PDF page; use `\n` for multiple lines on the same page.
    static func makeTextPDF(pages: [String]) throws -> URL {
        Self.pdfFixtureLock.lock()
        defer { Self.pdfFixtureLock.unlock() }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-pdf-pipeline-\(UUID().uuidString).pdf")
        let pageSize = CGSize(width: 612, height: 792)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            struct E: Error {}
            throw E()
        }

        for pageText in pages {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)

            var y: CGFloat = 72
            // Helvetica has no CJK glyphs; use a system Chinese font so PDFKit string extraction matches input.
            let fontName =
                (pageText.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
                ? "PingFang SC" as CFString
                : "Helvetica" as CFString
            for line in pageText.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(line)
                let font = CTFontCreateWithName(fontName, 14, nil)
                let attr = CFAttributedStringCreate(
                    nil,
                    s as CFString,
                    [kCTFontAttributeName: font] as CFDictionary
                )!
                let ctLine = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: 72, y: y)
                CTLineDraw(ctLine, ctx)
                y += 22
            }
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// Committed raster PDF (`gen-smoke-pdf.swift`); exercises PDFParser → Vision OCR path reliably (CTLine PDFs often lack a usable `PDFPage.string` in tests).
    @Test("PDFParser reads smoke fixture (OCR path)")
    func parserSmokeFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../XcodeUX/LeoUITests/Fixtures/smoke.pdf")
            .standardizedFileURL
        #expect(FileManager.default.fileExists(atPath: url.path), "Run Leo/scripts/gen-smoke-pdf.swift if missing.")

        let content = try PDFParser().parse(fileURL: url)
        #expect(content.pages.count >= 1)
        let joined = content.pages.map(\.text).joined(separator: "\n")
        #expect(joined.localizedCaseInsensitiveContains("leo"))

        let assessment = PDFConverter.assess(content: content)
        #expect(assessment.isUsable)
        #expect(assessment.failureReason == nil)
        #expect(assessment.meaningfulCharacterCount > 0)
    }

    @Test("PDFLayoutAnalyzer strips repeated header and footer across pages")
    func layoutStripsRepeatedEdges() throws {
        let pages = (0..<4).map { i in
            "RUNNING HEAD\nBody line alpha \(i).\nFooter 9"
        }
        let content = PDFParser.PDFContent(
            title: "T",
            pageCount: pages.count,
            pages: pages.enumerated().map { PDFParser.Page(id: $0.offset, text: $0.element) }
        )
        let analyzed = PDFLayoutAnalyzer().analyze(content: content)
        #expect(!analyzed.paragraphs.joined(separator: " ").contains("RUNNING HEAD"))
        #expect(!analyzed.paragraphs.joined(separator: " ").contains("Footer 9"))
        #expect(analyzed.paragraphs.contains { $0.contains("Body line alpha 0") })
        #expect(analyzed.paragraphs.contains { $0.contains("Body line alpha 3") })
    }

    @Test("ReflowBookBuilder escapes XML in paragraph text")
    func xmlEscaping() {
        let html = ReflowBookBuilder.chapterXHTML(
            title: "T",
            paragraphs: ["a < b && c > d"],
            lang: "en"
        )
        #expect(html.contains("a &lt; b &amp;&amp; c &gt; d"))
        #expect(!html.contains("a < b"))
    }

    @Test("EPUBWriter writes a loadable EPUB bundle")
    func epubWriterZip() throws {
        let epub = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-test-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: epub) }

        let chapter = ReflowBookBuilder.chapterXHTML(
            title: "Sample",
            paragraphs: ["Hello EPUB.", "第二行。"],
            lang: "zh-Hans"
        )
        let nav = ReflowBookBuilder.navXHTML(
            chapterHref: "chapter001.xhtml",
            chapterLabel: "Content",
            bookTitle: "Sample",
            lang: "zh-Hans"
        )
        try EPUBWriter().writeEPUB(
            title: "Sample",
            chapterFileName: "chapter001.xhtml",
            chapterXHTML: chapter,
            navXHTML: nav,
            language: "zh-Hans",
            outputURL: epub
        )

        #expect(FileManager.default.fileExists(atPath: epub.path))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-l", epub.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(listing.contains("OEBPS/content.opf"))
        #expect(listing.contains("chapter001.xhtml"))
        #expect(listing.contains("mimetype"))
    }

    @Test("PDFConverter produces EPUB with expected body snippets")
    func endToEndConvert() throws {
        let pdf = try Self.makeTextPDF(pages: [
            "标题旁注\n本体第一节。",
            "标题旁注\n本体第二节。",
        ])
        let epub = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-e2e-\(UUID().uuidString).epub")
        defer {
            try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: epub)
        }

        let assessment = try PDFConverter().convert(pdfURL: pdf, outputEPUBURL: epub)
        #expect(assessment.isUsable)
        #expect(assessment.usablePages == 2)
        #expect(FileManager.default.fileExists(atPath: epub.path))

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-unzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-qq", "-o", epub.path, "-d", tmp.path]
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)

        let xhtmlPath = tmp.appendingPathComponent("OEBPS/chapter001.xhtml").path
        let xhtml = try String(contentsOfFile: xhtmlPath, encoding: .utf8)
        #expect(xhtml.contains("本体第一节"))
        #expect(xhtml.contains("本体第二节"))
        try? FileManager.default.removeItem(at: tmp)
    }

    @Test("PDFConverter quality gate accepts native text content")
    func qualityGateAcceptsNativeText() {
        let content = PDFParser.PDFContent(
            title: "Native",
            pageCount: 2,
            pages: [
                PDFParser.Page(id: 0, text: "第一章\n这是正文。"),
                PDFParser.Page(id: 1, text: "第二章\n还有正文。"),
            ]
        )

        let assessment = PDFConverter.assess(content: content)

        #expect(assessment.isUsable)
        #expect(assessment.failureReason == nil)
        #expect(assessment.usablePages == 2)
        #expect(assessment.meaningfulCharacterCount > 0)
    }

    @Test("PDFConverter quality gate accepts OCR output with real text")
    func qualityGateAcceptsOCRText() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../XcodeUX/LeoUITests/Fixtures/smoke.pdf")
            .standardizedFileURL

        let content = try PDFParser().parse(fileURL: url)
        let assessment = PDFConverter.assess(content: content)

        #expect(assessment.isUsable)
        #expect(assessment.failureReason == nil)
        #expect(assessment.meaningfulCharacterCount > 0)
    }

    @Test("PDFConverter quality gate rejects placeholder-only content")
    func qualityGateRejectsLowContent() throws {
        let content = PDFParser.PDFContent(
            title: "LowQuality",
            pageCount: 2,
            pages: [
                PDFParser.Page(id: 0, text: "(OCR failed)"),
                PDFParser.Page(id: 1, text: "(Could not render page for OCR)"),
            ]
        )
        let assessment = PDFConverter.assess(content: content)
        #expect(!assessment.isUsable)
        #expect(assessment.failureReason != nil)

        let pdf = try Self.makeTextPDF(pages: [
            "",
            "",
        ])
        defer { try? FileManager.default.removeItem(at: pdf) }

        let epub = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-low-quality-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: epub) }

        do {
            _ = try PDFConverter().convert(pdfURL: pdf, outputEPUBURL: epub)
            Issue.record("Expected PDFConverter to reject placeholder-only content")
        } catch let error as PDFConverter.PDFConverterError {
            switch error {
            case .lowQuality(let reason):
                #expect(
                    reason.localizedCaseInsensitiveContains("readable text")
                    || reason.localizedCaseInsensitiveContains("placeholder")
                )
            case .conversionFailed:
                Issue.record("Expected low-quality rejection, not conversion failure")
            }
        }
    }
}
