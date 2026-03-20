import SwiftUI

extension Color {
    // MARK: - Islamic Color Palette

    static let islamicEmerald = Color(red: 0.10, green: 0.65, blue: 0.40)
    static let islamicGold = Color(red: 0.85, green: 0.68, blue: 0.35)
    static let islamicMidnight = Color(red: 0.06, green: 0.06, blue: 0.14)
    static let islamicCream = Color(red: 0.95, green: 0.92, blue: 0.88)
    static let islamicSilver = Color(red: 0.75, green: 0.78, blue: 0.90)

    // MARK: - Hex Initializer

    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
