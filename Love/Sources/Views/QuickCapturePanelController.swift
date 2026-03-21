import AppKit
import SwiftData
import SwiftUI

/// Floating panel for ⌃⌥L / menu “Quick capture”.
@MainActor
final class QuickCapturePanelController {
    private let modelContainer: ModelContainer
    private weak var engine: LoveEngine?
    private var panel: NSPanel?

    init(modelContainer: ModelContainer, engine: LoveEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
    }

    func show() {
        guard let engine else { return }

        let root = QuickCaptureSheet(engine: engine, onFinished: { [weak self] in
            self?.panel?.orderOut(nil)
        })
        .modelContainer(modelContainer)

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.title = "Later — quick capture"
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            p.center()
            panel = p
        }

        panel?.contentView = NSHostingView(rootView: root)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

struct QuickCaptureSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CaptureCategory.sortOrder) private var categories: [CaptureCategory]
    var engine: LoveEngine
    var onFinished: () -> Void

    @State private var bodyText = ""
    @State private var selectedCategoryID: UUID?

    var body: some View {
        Form {
            TextField("Paste a link or a thought…", text: $bodyText, axis: .vertical)
                .lineLimit(3...8)
            Picker("Category", selection: $selectedCategoryID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(categories, id: \.id) { cat in
                    Text(cat.name).tag(Optional(cat.id))
                }
            }
            HStack {
                Spacer()
                Button("Save to later") {
                    let cat = categories.first { $0.id == selectedCategoryID }
                    engine.addCapture(body: bodyText, category: cat)
                    bodyText = ""
                    onFinished()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 380, minHeight: 160)
        .onAppear {
            if selectedCategoryID == nil, let first = categories.first {
                selectedCategoryID = first.id
            }
        }
    }
}
