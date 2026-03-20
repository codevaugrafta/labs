import SwiftUI

// MARK: - Eight-Point Star (Islamic Geometric Pattern)

struct EightPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.38

        for i in 0..<8 {
            let outerAngle = (Double(i) * .pi / 4) - .pi / 2
            let innerAngle = outerAngle + .pi / 8

            let outerPoint = CGPoint(
                x: center.x + CGFloat(cos(outerAngle)) * outerRadius,
                y: center.y + CGFloat(sin(outerAngle)) * outerRadius
            )
            let innerPoint = CGPoint(
                x: center.x + CGFloat(cos(innerAngle)) * innerRadius,
                y: center.y + CGFloat(sin(innerAngle)) * innerRadius
            )

            if i == 0 {
                path.move(to: outerPoint)
            } else {
                path.addLine(to: outerPoint)
            }
            path.addLine(to: innerPoint)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Crescent Moon

struct CrescentMoon: Shape {
    var phase: CGFloat = 0.3 // 0 = full, 1 = new

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Outer circle (full moon)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        // Inner circle offset to create crescent
        let offset = radius * phase
        let innerCenter = CGPoint(x: center.x + offset, y: center.y)
        let innerRadius = radius * 0.92

        // Subtract inner circle using even-odd fill
        path.addArc(center: innerCenter, radius: innerRadius,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        return path
    }
}

// MARK: - Geometric Tile Pattern (Repeating)

struct GeometricPattern: View {
    let theme: any AdhanTheme
    var tileSize: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / tileSize) + 2
            let rows = Int(size.height / tileSize) + 2

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * tileSize
                    let y = CGFloat(row) * tileSize
                    let rect = CGRect(x: x, y: y, width: tileSize, height: tileSize)

                    // Alternating star and diamond
                    if (row + col) % 2 == 0 {
                        let starPath = EightPointStar().path(in: rect.insetBy(dx: tileSize * 0.15, dy: tileSize * 0.15))
                        context.stroke(starPath, with: .color(theme.accent), lineWidth: 0.5)
                    } else {
                        let diamond = Path { p in
                            p.move(to: CGPoint(x: rect.midX, y: rect.minY + tileSize * 0.2))
                            p.addLine(to: CGPoint(x: rect.maxX - tileSize * 0.2, y: rect.midY))
                            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - tileSize * 0.2))
                            p.addLine(to: CGPoint(x: rect.minX + tileSize * 0.2, y: rect.midY))
                            p.closeSubpath()
                        }
                        context.stroke(diamond, with: .color(theme.accent), lineWidth: 0.5)
                    }
                }
            }
        }
        .opacity(theme.patternOpacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Pattern Overlay Modifier

extension View {
    func islamicPatternOverlay() -> some View {
        let tm = AdhanThemeManager.shared
        return self.overlay {
            if tm.showsGeometricPattern {
                GeometricPattern(theme: tm.current)
                    .clipped()
            }
        }
    }
}
