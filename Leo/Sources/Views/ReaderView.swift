import SwiftUI
import WebKit
import PDFKit

struct ReaderView: View {
    let book: Book
    @State private var theme: ReadingTheme = .light
    @State private var error: String?
    @State private var familiarityTracker: FamiliarityTracker?
    @StateObject private var sessionEngine = ReadingSessionEngine()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if book.format == .pdf {
                PDFReaderView(filePath: book.filePath)
            } else {
                // EPUB via foliate-js + localhost server.
                // The dictionary popup is rendered as an HTML floating card inside the
                // WKWebView — no SwiftUI overlay. The popup positions itself next to the
                // tapped word and handles its own dismiss / action buttons.
                FoliateReaderView(
                    bookFilePath: book.filePath,
                    bookId: book.id.uuidString,
                    theme: theme,
                    onWordTapped: handleWordTap,
                    onPopupAction: handlePopupAction
                )
            }
        }
        .toolbar {
            // Theme picker
            ToolbarItem(placement: .automatic) {
                Picker("Theme", selection: $theme) {
                    ForEach(ReadingTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Reading session timer
            ToolbarItem(placement: .automatic) {
                if sessionEngine.isActive {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundStyle(.orange)
                        Text(sessionEngine.formattedTime)
                            .font(.system(.body, design: .monospaced))
                        Button(action: { sessionEngine.stopSession() }) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(action: { sessionEngine.startSession(bookTitle: book.title) }) {
                        Label("Start Session", systemImage: "play.circle")
                    }
                }
            }
        }
        .task {
            Task.detached(priority: .userInitiated) {
                DictionaryEngine.shared.load()
                FrequencyEngine.shared.load()
            }
            familiarityTracker = FamiliarityTracker(modelContext: modelContext)
            sessionEngine.configure(modelContext: modelContext)
        }
    }

    // Called by the coordinator immediately after resolving the tapped word.
    // Used to record the encounter in the familiarity tracker / session engine.
    // The popup itself is rendered in JS — we don't show any SwiftUI state here.
    private func handleWordTap(_ char: String, context: String, charIndex: Int, x: CGFloat, y: CGFloat) {
        NSLog("[Leo UI] Word tap received: char=\(char), context=\(context.prefix(20)), idx=\(charIndex)")

        // The coordinator already resolved the word and is calling showPopup() in JS.
        // We just record the encounter here for familiarity tracking.
        let parser = ChineseParser()
        let word = parser.resolveWordAtPosition(context: context, charIndex: charIndex)
        let entries = DictionaryEngine.shared.lookup(word)
        let pinyin = entries.first?.pinyinDisplay ?? ""
        let def = entries.first?.definitions.first ?? ""
        familiarityTracker?.recordEncounter(word, pinyin: pinyin, definition: def)

        NSLog("[Leo UI] Encounter recorded for '\(word)'")
    }

    // Called when the user taps "I know this" or "Add to review" inside the JS popup.
    private func handlePopupAction(_ action: FoliateReaderView.PopupAction, word: String) {
        NSLog("[Leo UI] Popup action: \(action) for '\(word)'")
        switch action {
        case .markKnown:
            familiarityTracker?.markAsKnown(word)
        case .addToSRS:
            familiarityTracker?.markAsLearning(word)
            let fsrs = FSRSEngine(modelContext: modelContext)
            if fsrs.card(for: word) == nil {
                _ = fsrs.createCard(for: word)
            }
        }
    }
}

// MARK: - PDF Reader (Apple PDFKit — native, works for Chinese visual rendering)

struct PDFReaderView: NSViewRepresentable {
    let filePath: String

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor

        if let document = PDFDocument(url: URL(fileURLWithPath: filePath)) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {}
}

// MARK: - Reading Theme

enum ReadingTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case sepia

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .sepia: "Sepia"
        }
    }
}
