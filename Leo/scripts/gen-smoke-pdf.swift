import AppKit
import PDFKit

let out =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("XcodeUX/LeoUITests/Fixtures/smoke.pdf")

let doc = PDFDocument()
let img = NSImage(size: NSSize(width: 400, height: 240))
img.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 240)).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22)]
NSString(string: "Leo PDF smoke test").draw(at: NSPoint(x: 40, y: 110), withAttributes: attrs)
img.unlockFocus()
guard let page = PDFPage(image: img) else {
    fputs("PDFPage failed\n", stderr)
    exit(1)
}
doc.insert(page, at: 0)
guard doc.write(to: out) else {
    fputs("write failed\n", stderr)
    exit(1)
}
print(out.path)
