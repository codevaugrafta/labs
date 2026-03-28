import SwiftUI
import WebKit
import PDFKit

struct ReaderView: View {
    let book: Book
    @State private var theme: ReadingTheme = .light
    @State private var error: String?
    @State private var selectedWord: String?
    @State private var wordEntries: [DictionaryEngine.Entry] = []
    @State private var wordFamiliarity: FamiliarityState = .unknown
    @State private var wordFrequency: FrequencyEngine.FrequencyData?
    @State private var familiarityTracker: FamiliarityTracker?
    @StateObject private var sessionEngine = ReadingSessionEngine()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Reader content fills the full area.
        // The popup is anchored to the bottom via safeAreaInset — it slides up
        // from the window edge and never overlaps the reading text.
        // No coordinate mapping needed: iframe coords are not used.
        Group {
            if book.format == .pdf {
                PDFReaderView(filePath: book.filePath)
            } else {
                // EPUB via foliate-js + localhost server
                FoliateReaderView(
                    bookFilePath: book.filePath,
                    bookId: book.id.uuidString,
                    theme: theme,
                    onWordTapped: handleWordTap
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let word = selectedWord {
                WordPopupView(
                    word: word,
                    entries: wordEntries,
                    familiarityState: wordFamiliarity,
                    frequencyData: wordFrequency ?? FrequencyEngine.shared.lookup(word),
                    onDismiss: { selectedWord = nil },
                    onMarkKnown: {
                        familiarityTracker?.markAsKnown(word)
                        selectedWord = nil
                    },
                    onAddToSRS: {
                        familiarityTracker?.markAsLearning(word)
                        let fsrs = FSRSEngine(modelContext: modelContext)
                        if fsrs.card(for: word) == nil {
                            _ = fsrs.createCard(for: word)
                        }
                        selectedWord = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: selectedWord)
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
                .onChange(of: theme) { _, newTheme in
                    // Send theme to foliate-js via JS bridge
                    // FoliateReaderView will pick this up
                }
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
            // Load dictionaries in background
            Task.detached(priority: .userInitiated) {
                DictionaryEngine.shared.load()
                FrequencyEngine.shared.load()
            }
            familiarityTracker = FamiliarityTracker(modelContext: modelContext)
            sessionEngine.configure(modelContext: modelContext)
        }
        .onTapGesture {
            if selectedWord != nil { selectedWord = nil }
        }
    }

    private func handleWordTap(_ char: String, context: String, charIndex: Int, x: CGFloat, y: CGFloat) {
        NSLog("[Leo UI] Word tap received: char=\(char), context=\(context.prefix(20)), idx=\(charIndex)")

        // Resolve word from character + context using the parser
        let parser = ChineseParser()
        let word = parser.resolveWordAtPosition(context: context, charIndex: charIndex)
        NSLog("[Leo UI] Resolved word: \(word)")

        let entries = DictionaryEngine.shared.lookup(word)
        NSLog("[Leo UI] Dictionary entries: \(entries.count) for '\(word)'")
        wordEntries = entries
        wordFamiliarity = familiarityTracker?.state(for: word) ?? .unknown
        wordFrequency = FrequencyEngine.shared.lookup(word)

        // Record encounter
        let pinyin = entries.first?.pinyinDisplay ?? ""
        let def = entries.first?.definitions.first ?? ""
        familiarityTracker?.recordEncounter(word, pinyin: pinyin, definition: def)

        selectedWord = word
        NSLog("[Leo UI] Popup showing for '\(word)'")
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
