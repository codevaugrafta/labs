import Foundation
import PDFKit
import Vision
import AppKit

/// Extracts text content from PDF files.
/// Strategy: Try PDFKit text extraction first. If it returns garbage
/// (common with Chinese CIDFont PDFs), fall back to Apple Vision OCR.
/// On macOS 26+, OCR uses RecognizeDocumentsRequest for structure-aware extraction.
struct PDFParser: Sendable {

    struct PDFContent: Sendable {
        let title: String
        let pageCount: Int
        let pages: [Page]
    }

    struct Page: Sendable, Identifiable {
        let id: Int
        let text: String
    }

    func parse(fileURL: URL) throws -> PDFContent {
        guard let document = PDFDocument(url: fileURL) else {
            throw PDFParseError.cannotOpen
        }

        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            ?? fileURL.deletingPathExtension().lastPathComponent

        var pages: [Page] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            // Try PDFKit text extraction first
            let pdfkitText = page.string ?? ""

            // Check if text is usable (contains Chinese characters)
            if containsChinese(pdfkitText) && pdfkitText.count > 10 {
                pages.append(Page(id: i, text: cleanupChineseOCR(pdfkitText)))
            } else {
                // Fallback: OCR via Apple Vision
                let ocrText = ocrPage(page)
                pages.append(Page(id: i, text: cleanupChineseOCR(ocrText)))
            }
        }

        return PDFContent(
            title: title,
            pageCount: document.pageCount,
            pages: pages
        )
    }

    /// Render a PDF page to a CGImage at 2× scale for OCR accuracy.
    private func renderPageToCGImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let imageSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let image = NSImage(size: imageSize)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: imageSize))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
    }

    /// OCR a single page. Uses RecognizeDocumentsRequest on macOS 26+ for
    /// structure-aware, reading-order extraction; falls back to VNRecognizeTextRequest
    /// on earlier OS versions.
    private func ocrPage(_ page: PDFPage) -> String {
        guard let cgImage = renderPageToCGImage(page) else {
            return "(Could not render page for OCR)"
        }

        if #available(macOS 26, *) {
            // Bridge the async structured path into the synchronous caller.
            // The semaphore guarantees the Task write completes before the read,
            // so nonisolated(unsafe) suppresses the false Swift 6 data-race warning.
            nonisolated(unsafe) var result = "(OCR failed)"
            let semaphore = DispatchSemaphore(value: 0)
            let capturedImage = cgImage
            Task.detached {
                result = await ocrPageStructured(cgImage: capturedImage)
                semaphore.signal()
            }
            semaphore.wait()
            return result
        } else {
            return ocrPageLegacy(cgImage: cgImage)
        }
    }

    /// macOS 26+ — RecognizeDocumentsRequest returns a DocumentObservation whose
    /// paragraphs are already in reading order. Each paragraph's lines are joined
    /// with spaces; paragraphs are joined with double newlines so PDFLayoutAnalyzer
    /// can split them correctly.
    @available(macOS 26, *)
    private func ocrPageStructured(cgImage: CGImage) async -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "en"),
        ]
        request.textRecognitionOptions.useLanguageCorrection = true

        do {
            let observations = try await request.perform(on: cgImage)
            guard !observations.isEmpty else { return "(OCR failed)" }

            // DocumentObservation.document.paragraphs are in reading order.
            // Each Container.Text.lines is [RecognizedTextObservation].
            var paragraphs: [String] = []
            for observation in observations {
                let container = observation.document
                for para in container.paragraphs {
                    let text = para.lines
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: " ")
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !text.isEmpty {
                        paragraphs.append(text)
                    }
                }
            }

            guard !paragraphs.isEmpty else { return "(OCR failed)" }
            return paragraphs.joined(separator: "\n\n")
        } catch {
            // Fall through to legacy on any Vision error
            return ocrPageLegacy(cgImage: cgImage)
        }
    }

    /// Legacy OCR using VNRecognizeTextRequest — available on all supported OS versions.
    private func ocrPageLegacy(cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let observations = request.results else {
            return "(OCR failed)"
        }

        // Sort by position (top to bottom, left to right)
        let sorted = observations.sorted { a, b in
            let aY = 1.0 - a.boundingBox.midY
            let bY = 1.0 - b.boundingBox.midY
            if abs(aY - bY) < 0.02 { // Same line
                return a.boundingBox.minX < b.boundingBox.minX
            }
            return aY < bY
        }

        return sorted
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Post-process OCR text: remove spaces between CJK characters (OCR artifacts),
    /// strip isolated page numbers, normalize whitespace.
    private func cleanupChineseOCR(_ text: String) -> String {
        var result = text
        // Remove spaces between CJK characters ("不 能" → "不能")
        let cjkSpace = #"([\u4E00-\u9FFF\u3400-\u4DBF])\s+([\u4E00-\u9FFF\u3400-\u4DBF])"#
        for _ in 0..<5 {
            let before = result
            result = result.replacingOccurrences(of: cjkSpace, with: "$1$2", options: .regularExpression)
            if result == before { break }
        }
        // Remove isolated page numbers (lines that are just 1-4 digits)
        let lines = result.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return true }
            return !(Int(t) != nil && t.count <= 4)
        }
        result = filtered.joined(separator: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}

enum PDFParseError: LocalizedError {
    case cannotOpen

    var errorDescription: String? {
        switch self {
        case .cannotOpen: "Cannot open PDF file"
        }
    }
}
