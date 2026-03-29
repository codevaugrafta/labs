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
    }

    @Test("BookFormat encodes round-trip")
    func bookFormatCoding() throws {
        let fmt = BookFormat.pdf
        let data = try JSONEncoder().encode(fmt)
        let decoded = try JSONDecoder().decode(BookFormat.self, from: data)
        #expect(decoded == .pdf)
    }
}
