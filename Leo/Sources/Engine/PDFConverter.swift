import Foundation

/// Orchestrates PDF text extraction → layout → reflow EPUB on disk (on-device, no network).
struct PDFConverter: Sendable {

    enum PDFConverterError: LocalizedError {
        case conversionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .conversionFailed(let e): e.localizedDescription
            }
        }
    }

    /// Progress 0.0...1.0 per page parsed.
    func convert(
        pdfURL: URL,
        outputEPUBURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        progress?(0.05)
        let parser = PDFParser()
        let content: PDFParser.PDFContent
        do {
            content = try parser.parse(fileURL: pdfURL)
        } catch {
            throw PDFConverterError.conversionFailed(error)
        }

        progress?(0.4)
        let analyzed = PDFLayoutAnalyzer().analyze(content: content)
        progress?(0.85)
        guard !analyzed.paragraphs.isEmpty else {
            throw EPUBWriter.EPUBWriterError.emptyManuscript
        }

        let chapter = ReflowBookBuilder.chapterXHTML(
            title: analyzed.title,
            paragraphs: analyzed.paragraphs,
            lang: analyzed.primaryLanguageTag
        )
        let nav = ReflowBookBuilder.navXHTML(
            chapterHref: "chapter001.xhtml",
            chapterLabel: "Content",
            bookTitle: analyzed.title,
            lang: analyzed.primaryLanguageTag
        )

        try EPUBWriter().writeEPUB(
            title: analyzed.title,
            chapterFileName: "chapter001.xhtml",
            chapterXHTML: chapter,
            navXHTML: nav,
            language: analyzed.primaryLanguageTag,
            outputURL: outputEPUBURL
        )
        progress?(1.0)
    }

    /// Stable filename under `booksDirectory`: `{safeTitle}-leo-reflow.epub`
    static func suggestedOutputURL(booksDirectory: URL, title: String) -> URL {
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = safe.isEmpty ? "book" : safe
        return booksDirectory.appendingPathComponent("\(stem)-leo-reflow.epub")
    }

    /// Picks `…-leo-reflow.epub` or `…-leo-reflow-2.epub`, etc., if the base name already exists.
    static func uniqueSuggestedOutputURL(booksDirectory: URL, title: String) -> URL {
        let fm = FileManager.default
        var url = suggestedOutputURL(booksDirectory: booksDirectory, title: title)
        var n = 1
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = safe.isEmpty ? "book" : safe
        while fm.fileExists(atPath: url.path) {
            n += 1
            url = booksDirectory.appendingPathComponent("\(stem)-leo-reflow-\(n).epub")
        }
        return url
    }
}
