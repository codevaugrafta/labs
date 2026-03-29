import SwiftUI

/// Shared typography + display toggles (Settings → Reading and reader toolbar popover).
struct ReadingPreferencesForm: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var textDirection: String
    @Binding var showPinyin: Bool
    @Binding var showHighlights: Bool

    var body: some View {
        Form {
            Section("Typography") {
                Slider(value: $fontSize, in: 14...28, step: 1) {
                    Text("Font size: \(Int(fontSize))pt")
                }
                .accessibilityIdentifier("leo.readingPrefs.fontSize")
                Slider(value: $lineHeight, in: 1.2...2.5, step: 0.1) {
                    Text("Line height: \(lineHeight, specifier: "%.1f")")
                }
                .accessibilityIdentifier("leo.readingPrefs.lineHeight")
                Picker("Text direction", selection: $textDirection) {
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                .accessibilityIdentifier("leo.readingPrefs.textDirection")
            }

            Section("Display") {
                Toggle("Show pinyin in lookup", isOn: $showPinyin)
                    .accessibilityIdentifier("leo.readingPrefs.showPinyin")
                Toggle("Show familiarity highlights", isOn: $showHighlights)
                    .accessibilityIdentifier("leo.readingPrefs.showHighlights")
            }
        }
        .accessibilityIdentifier("leo.readingPrefs.form")
    }
}
