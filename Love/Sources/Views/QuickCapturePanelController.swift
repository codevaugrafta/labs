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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.title = "Love · Quick capture"
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                LoveAccentRule(width: 36)
                Text("Quick capture")
                    .font(LoveTypography.panelTitle)
                Text("Anything that isn’t for right now — filed without friction.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, LoveTheme.contentGutter)
            .padding(.top, 18)
            .padding(.bottom, 10)

            if let err = engine.lastError {
                LoveSaveErrorBanner(message: err, onDismiss: { engine.clearLastError() }, horizontalPadding: 16)
            }

            Group {
                Form {
                    TextField("Paste a link or a thought…", text: $bodyText, axis: .vertical)
                        .lineLimit(3...12)
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
                            if engine.lastError == nil {
                                bodyText = ""
                                onFinished()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .formStyle(.grouped)
            }
            .padding(12)
            .background {
                LoveComposerChrome()
            }
            .padding(.horizontal, LoveTheme.contentGutter - 4)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 440, minHeight: 240)
        .background(LoveWindowBackdrop())
        .tint(LoveTheme.accent)
        .onAppear {
            if selectedCategoryID == nil, let first = categories.first {
                selectedCategoryID = first.id
            }
        }
    }
}
