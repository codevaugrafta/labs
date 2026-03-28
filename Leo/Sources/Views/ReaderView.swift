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
    @State private var popupPosition: CGPoint = .zero
    @State private var familiarityTracker: FamiliarityTracker?
    @StateObject private var sessionEngine = ReadingSessionEngine()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Reader content
            Group {
                if book.format == .pdf {
                    PDFReaderView(filePath: book.filePath)
                } else {
                    // EPUB via foliate-js + localhost server
                    FoliateReaderView(
                        bookFilePath: book.filePath,
                        bookId: book.id.uuidString,
                        onWordTapped: handleWordTap
                    )
                }
            }

            // Floating word popup
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
                .position(x: popupPosition.x, y: popupPosition.y)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: selectedWord)
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
        // Resolve word from character + context using the parser
        let parser = ChineseParser()
        let word = parser.resolveWordAtPosition(context: context, charIndex: charIndex)

        let entries = DictionaryEngine.shared.lookup(word)
        wordEntries = entries
        wordFamiliarity = familiarityTracker?.state(for: word) ?? .unknown
        wordFrequency = FrequencyEngine.shared.lookup(word)

        // Record encounter
        let pinyin = entries.first?.pinyinDisplay ?? ""
        let def = entries.first?.definitions.first ?? ""
        familiarityTracker?.recordEncounter(word, pinyin: pinyin, definition: def)

        selectedWord = word
        popupPosition = CGPoint(x: min(x + 180, 500), y: y + 80)
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
