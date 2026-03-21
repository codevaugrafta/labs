#!/usr/bin/env swift
import AppKit

/// Minimal “one focus point” motif — deep teal on near-black.
func createIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let s = CGFloat(size)
    let center = NSPoint(x: s / 2, y: s / 2)

    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.06, dy: s * 0.06), xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1).setFill()
    bgPath.fill()

    let accent = NSColor(red: 0.25, green: 0.72, blue: 0.65, alpha: 1)
    let dotR = s * 0.12
    let dotRect = NSRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2)
    accent.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    let trail = NSBezierPath()
    trail.move(to: NSPoint(x: center.x - s * 0.28, y: center.y + s * 0.02))
    trail.line(to: center)
    trail.lineWidth = s * 0.045
    trail.lineCapStyle = .round
    accent.withAlphaComponent(0.55).setStroke()
    trail.stroke()

    img.unlockFocus()
    return img
}

let cwd = FileManager.default.currentDirectoryPath
let iconsetPath = "\(cwd)/build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    let img = createIcon(size: size)
    let tiffData = img.tiffRepresentation!
    let bitmap = NSBitmapImageRep(data: tiffData)!
    let pngData = bitmap.representation(using: .png, properties: [:])!
    try! pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
}

print("Icon PNGs generated at \(iconsetPath)")
