import Foundation
import Testing
@testable import Leo

@Suite("Leo app models")
struct LeoTests {

    @Test("Book initializes with expected defaults")
    func bookModelInit() {
        let book = Book(title: "活着", author: "余华", filePath: "/tmp/活着.epub", format: .epub)
        #expect(book.title == "活着")
        #expect(book.author == "余华")
        #expect(book.format == .epub)
        #expect(book.lastLocator == nil)
        #expect(book.derivedEPUBPath == nil)
        #expect(book.pdfPreparationStatus == .ready)
        #expect(book.pdfPreparationError == nil)
        #expect(book.preferredPDFMode == .originalPDF)
        #expect(book.pdfLastPageIndex == 0)
        #expect(book.pdfFitPolicy == .fitPage)
    }

    @Test("PDF book initializes with the new dual-mode defaults")
    func pdfBookModelDefaults() {
        let book = Book(title: "活着", author: "余华", filePath: "/tmp/huozhe.pdf", format: .pdf)

        #expect(book.originalPDFPath == nil)
        #expect(book.derivedEPUBPath == nil)
        #expect(book.pdfPreparationStatus == .idle)
        #expect(book.pdfPreparationError == nil)
        #expect(book.preferredPDFMode == .originalPDF)
        #expect(book.pdfLastPageIndex == 0)
        #expect(book.pdfFitPolicy == .fitPage)
    }

    @Test("Legacy converted PDFs migrate back to canonical source-PDF storage")
    func legacyConvertedPDFMigration() {
        let book = Book(title: "旧版", author: "", filePath: "/tmp/旧版-reflow.epub", format: .epub)
        book.originalPDFPath = "/tmp/旧版.pdf"

        let migrated = book.migrateLegacyConvertedPDFIfNeeded()

        #expect(migrated)
        #expect(book.format == .pdf)
        #expect(book.filePath == "/tmp/旧版.pdf")
        #expect(book.derivedEPUBPath == "/tmp/旧版-reflow.epub")
        #expect(book.originalPDFPath == nil)
        #expect(book.pdfPreparationStatus == .ready)
        #expect(book.preferredPDFMode == .bookView)
    }

    @Test("PDF reader state stays on the book model")
    func pdfReaderStateStorage() {
        let book = Book(title: "活着", author: "余华", filePath: "/tmp/huozhe.pdf", format: .pdf)

        book.pdfLastPageIndex = 27
        book.pdfFitPolicy = .fitWidth
        book.preferredPDFMode = .bookView

        #expect(book.pdfLastPageIndex == 27)
        #expect(book.pdfFitPolicy == .fitWidth)
        #expect(book.preferredPDFMode == .bookView)
    }

    @Test("BookFormat encodes round-trip")
    func bookFormatCoding() throws {
        let fmt = BookFormat.pdf
        let data = try JSONEncoder().encode(fmt)
        let decoded = try JSONDecoder().decode(BookFormat.self, from: data)
        #expect(decoded == .pdf)
    }
}
