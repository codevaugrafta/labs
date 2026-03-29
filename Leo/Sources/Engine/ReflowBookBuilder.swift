import Foundation

/// Builds minimal XHTML fragments and full chapter documents for EPUB 3.
enum ReflowBookBuilder {

    static func chapterXHTML(title: String, paragraphs: [String], lang: String) -> String {
        let headTitle = title.xmlEscaped
        let body = paragraphs.map { "<p>\($0.xmlEscaped)</p>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(lang)">
        <head>
          <title>\(headTitle)</title>
          <style type="text/css">
            body { font-family: system-ui, -apple-system, sans-serif; line-height: 1.6; margin: 1.2em; }
            p { margin: 0.9em 0; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func navXHTML(chapterHref: String, chapterLabel: String, bookTitle: String, lang: String) -> String {
        let t = bookTitle.xmlEscaped
        let label = chapterLabel.xmlEscaped
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(lang)">
        <head>
          <title>\(t)</title>
        </head>
        <body>
          <nav epub:type="toc" id="toc">
            <h1>\(t)</h1>
            <ol>
              <li><a href="\(chapterHref)">\(label)</a></li>
            </ol>
          </nav>
        </body>
        </html>
        """
    }
}

extension String {
    var xmlEscaped: String {
        var s = ""
        s.reserveCapacity(count)
        for ch in self {
            switch ch {
            case "&": s.append("&amp;")
            case "<": s.append("&lt;")
            case ">": s.append("&gt;")
            case "\"": s.append("&quot;")
            default: s.append(ch)
            }
        }
        return s
    }
}
