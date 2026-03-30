import Foundation

/// Orchestrates PDF text extraction → layout → reflow EPUB on disk (on-device, no network).
struct PDFConverter: Sendable {

    struct PDFBookViewAssessment: Sendable {
        let totalPages: Int
        let usablePages: Int
        let meaningfulCharacterCount: Int
        let failureReason: String?

        var isUsable: Bool { failureReason == nil }
    }

    enum PDFConverterError: LocalizedError {
        case conversionFailed(Error)
        case lowQuality(String)

        var errorDescription: String? {
            switch self {
            case .conversionFailed(let e): e.localizedDescription
            case .lowQuality(let reason): reason
            }
        }
    }

    /// Progress 0.0...1.0 per page parsed.
    @discardableResult
    func convert(
        pdfURL: URL,
        outputEPUBURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> PDFBookViewAssessment {
        progress?(0.05)
        let parser = PDFParser()
        let content: PDFParser.PDFContent
        do {
            content = try await parser.parse(fileURL: pdfURL)
        } catch {
            throw PDFConverterError.conversionFailed(error)
        }

        progress?(0.4)
        let assessment = Self.assess(content: content)
        guard assessment.isUsable else {
            throw PDFConverterError.lowQuality(
                assessment.failureReason ?? "Leo couldn’t build a usable Book View from this PDF."
            )
        }

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
        return assessment
    }

    static func assess(content: PDFParser.PDFContent) -> PDFBookViewAssessment {
        let pages = content.pages.map(\.text)
        let totalPages = max(content.pageCount, pages.count)
        guard totalPages > 0 else {
            return PDFBookViewAssessment(
                totalPages: 0,
                usablePages: 0,
                meaningfulCharacterCount: 0,
                failureReason: "Leo couldn’t find any pages in this PDF."
            )
        }

        let usableCounts = pages.map { text in
            meaningfulCharacterCount(in: text)
        }
        let meaningfulCharacters = usableCounts.reduce(0, +)
        let usablePages = usableCounts.filter { $0 >= 6 }.count
        let placeholderPages = pages.filter(Self.isPlaceholderPage).count

        let failureReason: String?
        if placeholderPages == totalPages {
            failureReason = "Leo only found OCR placeholder output in this PDF."
        } else if meaningfulCharacters < 8 || usablePages == 0 {
            failureReason = "Leo couldn’t extract enough readable text to build Book View."
        } else {
            failureReason = nil
        }

        return PDFBookViewAssessment(
            totalPages: totalPages,
            usablePages: usablePages,
            meaningfulCharacterCount: meaningfulCharacters,
            failureReason: failureReason
        )
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

    private static func meaningfulCharacterCount(in rawText: String) -> Int {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPlaceholderPage(text) else { return 0 }
        return text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) || isChineseScalar(scalar.value) {
                count += 1
            }
        }
    }

    private static func isPlaceholderPage(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }

        let normalized = text.lowercased()
        return normalized.contains("ocr failed")
            || normalized.contains("could not render page for ocr")
    }

    private static func isChineseScalar(_ value: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
    }
}
