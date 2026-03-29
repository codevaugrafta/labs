import Foundation

/// Turns flat PDF page text into reading-order paragraphs with simple header/footer stripping.
struct PDFLayoutAnalyzer: Sendable {

    struct AnalyzedReflow: Sendable {
        let title: String
        let paragraphs: [String]
        /// Heuristic guess for EPUB dc:language
        let primaryLanguageTag: String
    }

    func analyze(content: PDFParser.PDFContent) -> AnalyzedReflow {
        var pageBodies: [String] = content.pages.map(\.text)

        if content.pages.count >= 2 {
            pageBodies = stripRepeatedEdgeLines(pageBodies, edge: .leading)
            pageBodies = stripRepeatedEdgeLines(pageBodies, edge: .trailing)
        }

        let merged = pageBodies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        // Split on blank lines; normalize soft line breaks inside a block to spaces.
        let rawParagraphs = merged
            .components(separatedBy: "\n\n")
            .map { chunk in
                chunk
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let lang = Self.detectLanguageTag(in: rawParagraphs.joined(separator: "\n"))

        return AnalyzedReflow(
            title: content.title,
            paragraphs: rawParagraphs,
            primaryLanguageTag: lang
        )
    }

    private enum Edge { case leading, trailing }

    /// If the same non-empty line appears at the same edge on 2+ pages, drop that line from every page that has it.
    private func stripRepeatedEdgeLines(_ pages: [String], edge: Edge) -> [String] {
        var lineCounts: [String: Int] = [:]
        for page in pages {
            let lines = page.split(whereSeparator: \.isNewline).map(String.init)
            let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !trimmed.isEmpty else { continue }
            let line: String
            switch edge {
            case .leading: line = trimmed[0]
            case .trailing: line = trimmed[trimmed.count - 1]
            }
            lineCounts[line, default: 0] += 1
        }
        let stripThese = Set(lineCounts.filter { $0.value >= 2 }.map(\.key))
        guard !stripThese.isEmpty else { return pages }

        return pages.map { page in
            var lines = page.split(whereSeparator: \.isNewline).map(String.init)
            switch edge {
            case .leading:
                while let first = lines.first {
                    let t = first.trimmingCharacters(in: .whitespaces)
                    if stripThese.contains(t) { lines.removeFirst() } else { break }
                }
            case .trailing:
                while let last = lines.last {
                    let t = last.trimmingCharacters(in: .whitespaces)
                    if stripThese.contains(t) { lines.removeLast() } else { break }
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func detectLanguageTag(in text: String) -> String {
        text.unicodeScalars.contains { s in
            (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
        } ? "zh-Hans" : "en"
    }
}
