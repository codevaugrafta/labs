import Foundation
import PDFKit

/// Extracts text content from native-text PDF files.
/// Uses Apple's PDFKit for rendering and text extraction.
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

    /// Parse a PDF file into structured content.
    func parse(fileURL: URL) throws -> PDFContent {
        guard let document = PDFDocument(url: fileURL) else {
            throw PDFParseError.cannotOpen
        }

        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            ?? fileURL.deletingPathExtension().lastPathComponent

        var pages: [Page] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let text = page.string ?? ""
            pages.append(Page(id: i, text: text))
        }

        return PDFContent(
            title: title,
            pageCount: document.pageCount,
            pages: pages
        )
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
