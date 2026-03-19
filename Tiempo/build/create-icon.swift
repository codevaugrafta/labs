#!/usr/bin/env swift
import AppKit

// Generate Tiempo app icon — gold timer on dark charcoal
func createIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let s = CGFloat(size)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded square, dark charcoal
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02), xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1.0).setFill()
    bgPath.fill()

    // Subtle gradient overlay
    let gradient = NSGradient(starting: NSColor(white: 1.0, alpha: 0.04), ending: NSColor(white: 0, alpha: 0))!
    gradient.draw(in: bgPath, angle: -45)

    // Gold circle (timer ring)
    let gold = NSColor(red: 0.85, green: 0.65, blue: 0.37, alpha: 1.0)
    let center = NSPoint(x: s/2, y: s/2)
    let ringRadius = s * 0.30
    let ringPath = NSBezierPath()
    ringPath.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
    ringPath.lineWidth = s * 0.035
    gold.setStroke()
    ringPath.stroke()

    // Timer tick marks (12 positions like a clock)
    for i in 0..<12 {
        let angle = CGFloat(i) * 30.0 * .pi / 180.0 - .pi/2
        let innerR = ringRadius - s * 0.04
        let outerR = ringRadius + s * 0.04
        let tickPath = NSBezierPath()
        tickPath.move(to: NSPoint(x: center.x + innerR * cos(angle), y: center.y + innerR * sin(angle)))
        tickPath.line(to: NSPoint(x: center.x + outerR * cos(angle), y: center.y + outerR * sin(angle)))
        tickPath.lineWidth = i % 3 == 0 ? s * 0.02 : s * 0.008
        gold.withAlphaComponent(i % 3 == 0 ? 0.9 : 0.3).setStroke()
        tickPath.stroke()
    }

    // Timer hand (pointing ~2 o'clock position)
    let handAngle = -25.0 * .pi / 180.0
    let handLength = ringRadius * 0.7
    let handPath = NSBezierPath()
    handPath.move(to: center)
    handPath.line(to: NSPoint(x: center.x + handLength * cos(handAngle), y: center.y + handLength * sin(handAngle)))
    handPath.lineWidth = s * 0.025
    handPath.lineCapStyle = .round
    gold.setStroke()
    handPath.stroke()

    // Center dot
    let dotSize = s * 0.04
    let dotRect = NSRect(x: center.x - dotSize/2, y: center.y - dotSize/2, width: dotSize, height: dotSize)
    gold.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    img.unlockFocus()
    return img
}

// Generate all required sizes for .icns
let iconsetPath = "/Users/franciscodilussor/Documents/002/Tiempo/build/AppIcon.iconset"
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
