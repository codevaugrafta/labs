import Foundation
import SwiftData

struct BookLocator: Codable, Equatable {
    let cfi: String
    let fraction: Double
    let updatedAt: Date
}

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var filePath: String
    var format: BookFormat
    var lastLocator: Data?
    var addedAt: Date
    var lastOpenedAt: Date?
    /// Legacy compatibility only. Older Leo builds rewrote PDF books into EPUBs and stored the source PDF here.
    var originalPDFPath: String?
    var derivedEPUBPath: String?
    var pdfPreparationStatusRaw: String?
    var pdfPreparationError: String?
    var preferredPDFModeRaw: String?
    var pdfLastPageIndex: Int?
    var pdfFitPolicyRaw: String?

    init(
        title: String,
        author: String,
        filePath: String,
        format: BookFormat
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.filePath = filePath
        self.format = format
        self.lastLocator = nil
        self.addedAt = Date()
        self.lastOpenedAt = nil
        self.originalPDFPath = nil
        self.derivedEPUBPath = nil
        self.pdfPreparationStatusRaw = (format == .pdf ? PDFBookPreparationStatus.idle : .ready).rawValue
        self.pdfPreparationError = nil
        self.preferredPDFModeRaw = PDFReadingMode.originalPDF.rawValue
        self.pdfLastPageIndex = 0
        self.pdfFitPolicyRaw = PDFPageFitPolicy.fitPage.rawValue
    }
}

enum BookFormat: String, Codable {
    case epub
    case pdf
}

extension Book {
    var pdfPreparationStatus: PDFBookPreparationStatus {
        get { PDFBookPreparationStatus(rawValue: pdfPreparationStatusRaw ?? "") ?? .idle }
        set { pdfPreparationStatusRaw = newValue.rawValue }
    }

    var preferredPDFMode: PDFReadingMode {
        get { PDFReadingMode(rawValue: preferredPDFModeRaw ?? "") ?? .originalPDF }
        set { preferredPDFModeRaw = newValue.rawValue }
    }

    var pdfFitPolicy: PDFPageFitPolicy {
        get { PDFPageFitPolicy(rawValue: pdfFitPolicyRaw ?? "") ?? .fitPage }
        set { pdfFitPolicyRaw = newValue.rawValue }
    }

    var safePdfLastPageIndex: Int {
        get { pdfLastPageIndex ?? 0 }
        set { pdfLastPageIndex = newValue }
    }

    var hasPreparedBookView: Bool {
        guard let derivedEPUBPath else { return false }
        return !derivedEPUBPath.isEmpty
    }

    var bookViewPath: String? {
        switch format {
        case .epub:
            return filePath
        case .pdf:
            return derivedEPUBPath
        }
    }

    var sourcePDFPath: String? {
        switch format {
        case .epub:
            return originalPDFPath
        case .pdf:
            return filePath
        }
    }

    var isLegacyConvertedPDF: Bool {
        format == .epub && originalPDFPath != nil && derivedEPUBPath == nil
    }

    @discardableResult
    func migrateLegacyConvertedPDFIfNeeded() -> Bool {
        guard isLegacyConvertedPDF,
              let sourcePDFPath = originalPDFPath,
              !sourcePDFPath.isEmpty else {
            return false
        }

        derivedEPUBPath = filePath
        filePath = sourcePDFPath
        format = .pdf
        originalPDFPath = nil
        pdfPreparationStatus = .ready
        preferredPDFMode = .bookView
        return true
    }

    var locator: BookLocator? {
        get {
            guard let lastLocator else { return nil }
            do {
                return try JSONDecoder().decode(BookLocator.self, from: lastLocator)
            } catch {
                NSLog("[Leo Book] Failed to decode BookLocator for '\(title)': \(error)")
                return nil
            }
        }
        set {
            do {
                lastLocator = try newValue.map { try JSONEncoder().encode($0) }
            } catch {
                NSLog("[Leo Book] Failed to encode BookLocator for '\(title)': \(error)")
                // lastLocator is left unchanged — prefer stale position over silent data loss
            }
        }
    }
}
