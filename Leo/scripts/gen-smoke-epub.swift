import Foundation

let outputURL =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("XcodeUX/LeoUITests/Fixtures/smoke.epub")

let fileManager = FileManager.default
let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("leo-smoke-epub-\(UUID().uuidString)", isDirectory: true)
let metaInfURL = tempRoot.appendingPathComponent("META-INF", isDirectory: true)
let oebpsURL = tempRoot.appendingPathComponent("OEBPS", isDirectory: true)

let repeatedParagraph = "你好世界。这是 Leo 的恢复进度测试段落。我们反复阅读这一段，只为确保 Foliate 会产生稳定的定位点。"
let chapterBody = (0..<120).map { index in
    "<p>\(index + 1). \(repeatedParagraph)</p>"
}.joined(separator: "\n  ")

let files: [(URL, String)] = [
    (tempRoot.appendingPathComponent("mimetype"), "application/epub+zip"),
    (
        metaInfURL.appendingPathComponent("container.xml"),
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    ),
    (
        oebpsURL.appendingPathComponent("chapter1.xhtml"),
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>Smoke</title>
        </head>
        <body>
          <h1>Leo Smoke EPUB</h1>
          \(chapterBody)
        </body>
        </html>
        """
    ),
    (
        oebpsURL.appendingPathComponent("content.opf"),
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="BookId">leo-smoke-epub</dc:identifier>
            <dc:title>Smoke</dc:title>
            <dc:language>zh-Hans</dc:language>
          </metadata>
          <manifest>
            <item id="chap1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chap1"/>
          </spine>
        </package>
        """
    ),
]

do {
    try fileManager.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: oebpsURL, withIntermediateDirectories: true)

    for (url, contents) in files {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    if fileManager.fileExists(atPath: outputURL.path) {
        try fileManager.removeItem(at: outputURL)
    }

    try run("/usr/bin/zip", ["-X0", outputURL.path, "mimetype"], workingDirectory: tempRoot)
    try run("/usr/bin/zip", ["-Xr9D", outputURL.path, "META-INF", "OEBPS"], workingDirectory: tempRoot)
    print(outputURL.path)
} catch {
    fputs("gen-smoke-epub failed: \(error)\n", stderr)
    exit(1)
}

private func run(_ executable: String, _ arguments: [String], workingDirectory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "gen-smoke-epub", code: Int(process.terminationStatus))
    }
}
