import SwiftUI
import PDFKit

private extension PDFPageLayoutMode {
    var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .singlePage:
            return .singlePage
        case .continuous:
            return .singlePageContinuous
        case .twoUp:
            return .twoUp
        case .twoUpContinuous:
            return .twoUpContinuous
        }
    }

    var usesTwoUpSpread: Bool {
        self == .twoUp || self == .twoUpContinuous
    }
}

private extension PDFScrollAxis {
    var pdfDisplayDirection: PDFDisplayDirection {
        switch self {
        case .vertical:
            return .vertical
        case .horizontal:
            return .horizontal
        }
    }
}

struct PDFModeSwitchControl: View {
    let selection: PDFReadingMode
    let bookViewReady: Bool
    let onSelect: (PDFReadingMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button("Original PDF") {
                onSelect(.originalPDF)
            }
            .accessibilityIdentifier("leo.toolbar.pdfMode.original")
            .buttonStyle(.bordered)
            .tint(selection == .originalPDF ? .accentColor : .secondary)

            Button("Book View") {
                onSelect(.bookView)
            }
            .accessibilityIdentifier("leo.toolbar.pdfMode.book")
            .disabled(!bookViewReady)
            .buttonStyle(.bordered)
            .tint(selection == .bookView ? .accentColor : .secondary)
        }
        .accessibilityIdentifier("leo.toolbar.pdfMode")
    }
}

struct PDFLayoutPreferencesForm: View {
    @Binding var layoutMode: PDFPageLayoutMode
    @Binding var scrollAxis: PDFScrollAxis
    @Binding var fitPolicy: PDFPageFitPolicy

    var body: some View {
        Form {
            Section("Pages") {
                Picker("Page layout", selection: $layoutMode) {
                    ForEach(PDFPageLayoutMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .accessibilityIdentifier("leo.pdfPrefs.pageLayout")

                Picker("Scroll direction", selection: $scrollAxis) {
                    ForEach(PDFScrollAxis.allCases) { axis in
                        Text(axis.label).tag(axis)
                    }
                }
                .accessibilityIdentifier("leo.pdfPrefs.scrollAxis")

                Picker("Fit", selection: $fitPolicy) {
                    ForEach(PDFPageFitPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .accessibilityIdentifier("leo.pdfPrefs.fitPolicy")
            }
        }
        .accessibilityIdentifier("leo.pdfPrefs.form")
    }
}

struct PDFReaderView: NSViewRepresentable {
    let filePath: String
    let initialPageIndex: Int
    let layoutMode: PDFPageLayoutMode
    let scrollAxis: PDFScrollAxis
    let fitPolicy: PDFPageFitPolicy
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPageChanged: onPageChanged,
            shouldAutoAdvanceForUITest: ProcessInfo.processInfo.environment["LEO_UI_TEST_AUTO_ADVANCE_PDF_PAGE"] == "1"
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.displayBox = .mediaBox
        pdfView.displaysPageBreaks = true
        pdfView.displaysAsBook = false
        pdfView.autoScales = false
        pdfView.postsFrameChangedNotifications = true

        context.coordinator.attach(to: pdfView)
        context.coordinator.update(
            pdfView: pdfView,
            filePath: filePath,
            initialPageIndex: initialPageIndex,
            layoutMode: layoutMode,
            scrollAxis: scrollAxis,
            fitPolicy: fitPolicy
        )
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        context.coordinator.update(
            pdfView: pdfView,
            filePath: filePath,
            initialPageIndex: initialPageIndex,
            layoutMode: layoutMode,
            scrollAxis: scrollAxis,
            fitPolicy: fitPolicy
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPageChanged: (Int) -> Void
        let shouldAutoAdvanceForUITest: Bool

        private weak var pdfView: PDFView?
        private var currentFilePath: String?
        private var currentLayoutMode: PDFPageLayoutMode?
        private var currentScrollAxis: PDFScrollAxis?
        private var currentFitPolicy: PDFPageFitPolicy?
        private var lastReportedPageIndex = 0
        private var suppressPageCallback = false
        private var didAutoAdvanceForUITest = false

        init(
            onPageChanged: @escaping (Int) -> Void,
            shouldAutoAdvanceForUITest: Bool
        ) {
            self.onPageChanged = onPageChanged
            self.shouldAutoAdvanceForUITest = shouldAutoAdvanceForUITest
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to pdfView: PDFView) {
            NotificationCenter.default.removeObserver(self)
            self.pdfView = pdfView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePageChangedNotification),
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFrameChangedNotification),
                name: NSView.frameDidChangeNotification,
                object: pdfView
            )
        }

        func update(
            pdfView: PDFView,
            filePath: String,
            initialPageIndex: Int,
            layoutMode: PDFPageLayoutMode,
            scrollAxis: PDFScrollAxis,
            fitPolicy: PDFPageFitPolicy
        ) {
            if currentFilePath != filePath {
                currentFilePath = filePath
                didAutoAdvanceForUITest = false
                loadDocument(from: filePath, into: pdfView)
            }

            let layoutChanged = currentLayoutMode != layoutMode || currentScrollAxis != scrollAxis
            if layoutChanged {
                currentLayoutMode = layoutMode
                currentScrollAxis = scrollAxis
                pdfView.displayMode = layoutMode.pdfDisplayMode
                pdfView.displayDirection = scrollAxis.pdfDisplayDirection
                pdfView.displaysAsBook = layoutMode.usesTwoUpSpread
            }

            let fitChanged = currentFitPolicy != fitPolicy
            if fitChanged {
                currentFitPolicy = fitPolicy
            }

            if layoutChanged || fitChanged {
                applyCurrentScale()
            }

            if lastReportedPageIndex != initialPageIndex {
                goToPage(initialPageIndex, in: pdfView)
            }
        }

        private func loadDocument(from filePath: String, into pdfView: PDFView) {
            guard let document = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
                return
            }

            pdfView.document = document
            if let currentLayoutMode {
                pdfView.displayMode = currentLayoutMode.pdfDisplayMode
                pdfView.displaysAsBook = currentLayoutMode.usesTwoUpSpread
            }
            if let currentScrollAxis {
                pdfView.displayDirection = currentScrollAxis.pdfDisplayDirection
            }
            applyCurrentScale()
            goToPage(lastReportedPageIndex, in: pdfView)
            maybeAutoAdvanceForUITest(pdfView: pdfView, document: document)
        }

        private func maybeAutoAdvanceForUITest(pdfView: PDFView, document: PDFDocument) {
            guard shouldAutoAdvanceForUITest,
                  !didAutoAdvanceForUITest,
                  document.pageCount > 1 else { return }

            didAutoAdvanceForUITest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.goToPage(1, in: pdfView)
            }
        }

        private func goToPage(_ index: Int, in pdfView: PDFView) {
            guard let document = pdfView.document,
                  document.pageCount > 0 else { return }

            let clamped = max(0, min(index, document.pageCount - 1))
            guard let page = document.page(at: clamped) else { return }

            suppressPageCallback = true
            pdfView.go(to: page)
            lastReportedPageIndex = clamped
            applyCurrentScale()
            DispatchQueue.main.async { [weak self] in
                self?.suppressPageCallback = false
            }
            DispatchQueue.main.async {
                self.onPageChanged(clamped)
            }
        }

        private func handlePageChanged() {
            guard !suppressPageCallback,
                  let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage else { return }

            let pageIndex = document.index(for: currentPage)
            lastReportedPageIndex = max(0, pageIndex)
            onPageChanged(lastReportedPageIndex)
        }

        private func applyCurrentScale() {
            guard let pdfView,
                  let document = pdfView.document,
                  document.pageCount > 0,
                  let currentPage = pdfView.currentPage ?? document.page(at: 0),
                  let currentFitPolicy else { return }

            let pageBounds = currentPage.bounds(for: pdfView.displayBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else { return }

            let spreadMultiplier: CGFloat = (currentLayoutMode?.usesTwoUpSpread == true) ? 2 : 1
            let availableBounds = pdfView.bounds.insetBy(dx: 24, dy: 24)
            let availableWidth = max(availableBounds.width, 1)
            let availableHeight = max(availableBounds.height, 1)
            let widthScale = availableWidth / (pageBounds.width * spreadMultiplier)
            let heightScale = availableHeight / pageBounds.height
            let fitPageScale = min(widthScale, heightScale)
            let targetScale = currentFitPolicy == .fitWidth ? widthScale : fitPageScale

            pdfView.autoScales = false
            pdfView.minScaleFactor = max(min(fitPageScale, widthScale) * 0.5, 0.1)
            pdfView.maxScaleFactor = max(targetScale * 4, 4.0)
            pdfView.scaleFactor = max(pdfView.minScaleFactor, min(targetScale, pdfView.maxScaleFactor))
        }

        @objc
        private func handlePageChangedNotification() {
            handlePageChanged()
        }

        @objc
        private func handleFrameChangedNotification() {
            applyCurrentScale()
        }
    }
}
