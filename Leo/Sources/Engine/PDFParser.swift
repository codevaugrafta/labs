import Foundation
import PDFKit
import Vision
import AppKit

/// Extracts text content from PDF files.
/// Strategy: Try PDFKit text extraction first. If it returns garbage
/// (common with Chinese CIDFont PDFs), fall back to Apple Vision OCR.
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
                pages.append(Page(id: i, text: pdfkitText))
            } else {
                // Fallback: OCR via Apple Vision
                let ocrText = ocrPage(page)
                pages.append(Page(id: i, text: ocrText))
            }
        }

        return PDFContent(
            title: title,
            pageCount: document.pageCount,
            pages: pages
        )
    }

    /// Use Apple Vision to OCR a PDF page — excellent Chinese support
    private func ocrPage(_ page: PDFPage) -> String {
        // Render page to image
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // 2x for better OCR accuracy
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
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return "(Could not render page for OCR)"
        }

        // Run Vision OCR
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
