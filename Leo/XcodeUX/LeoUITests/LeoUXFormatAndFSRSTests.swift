import Foundation
import XCTest
import CoreGraphics
import CoreText

// MARK: - PDF vs EPUB chrome

private enum LeoUXPDFFixtures {
    private static let lock = NSLock()

    static func makeTextPDF(pages: [String]) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-pdf-ux-\(UUID().uuidString).pdf")
        let pageSize = CGSize(width: 612, height: 792)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            struct PDFFixtureError: Error {}
            throw PDFFixtureError()
        }

        for pageText in pages {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)

            var y: CGFloat = 72
            let fontName = pageText.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
                ? "PingFang SC" as CFString
                : "Helvetica" as CFString

            for line in pageText.split(separator: "\n", omittingEmptySubsequences: false) {
                let font = CTFontCreateWithName(fontName, 14, nil)
                let attr = CFAttributedStringCreate(
                    nil,
                    String(line) as CFString,
                    [kCTFontAttributeName: font] as CFDictionary
                )!
                let ctLine = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: 72, y: y)
                CTLineDraw(ctLine, ctx)
                y += 22
            }

            ctx.restoreGState()
            ctx.endPDFPage()
        }

        ctx.closePDF()
        return url
    }

    static func makeBlankPDF(pageCount: Int = 2) throws -> URL {
        try makeTextPDF(pages: Array(repeating: "", count: pageCount))
    }
}

/// PDF fixture generated at runtime so the dual-mode behavior is not tied to one bundle asset.
@MainActor
final class LeoUXPDFDualModeTests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!
    private var dataDirectory: URL!
    private var textPDFURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = try LeoUXHarness.makeFreshDataDirectory(for: self)
        textPDFURL = try LeoUXPDFFixtures.makeTextPDF(pages: [
            "标题旁注\n本体第一节。\n本体第二节。",
            "标题旁注\n本体第三节。\n本体第四节。",
        ])
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            bookURL: textPDFURL,
            extraEnvironment: [
                "LEO_UI_TEST_SHOW_LOOKUP": "1",
                "LEO_UI_TEST_LOOKUP_WORD": "你好",
                "LEO_UI_TEST_CAPTURE_LOCATOR": "1",
                "LEO_UI_TEST_CAPTURE_PDF_PAGE": "1",
            ]
        )
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground { app.terminate() }
    }

    func testPDF_opensImmediately_inOriginalMode_withLayoutControls() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))

        XCTAssertTrue(LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfMode.original").waitForExistence(timeout: 15))
        XCTAssertTrue(LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfMode.book").waitForExistence(timeout: 15))
        XCTAssertTrue(LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfLayout").waitForExistence(timeout: 15))

        let pageProbe = LeoUXHarness.anyElement(in: app, identifier: "leo.reader.pdfPageProbe")
        XCTAssertTrue(pageProbe.waitForExistence(timeout: 20), "Original PDF should render immediately")
        XCTAssertTrue(
            (pageProbe.label + (pageProbe.value as? String ?? "")).contains("page=1"),
            "Expected the PDF to open on page 1"
        )
        XCTAssertFalse(
            LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.readingLayout").exists,
            "PDF should not show the EPUB reading-layout control"
        )
    }

    func testPDF_layoutPopover_exposesPageLayoutScrollAndFitControls() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))

        let layoutButton = LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfLayout")
        XCTAssertTrue(layoutButton.waitForExistence(timeout: 15))
        layoutButton.click()

        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.pdfPrefs.form").waitForExistence(timeout: 15))
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: "leo.pdfPrefs.pageLayout").waitForExistence(timeout: 10)
                || app.staticTexts["Page layout"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: "leo.pdfPrefs.fitPolicy").waitForExistence(timeout: 10)
                || app.staticTexts["Fit"].waitForExistence(timeout: 2)
        )
    }

    func testPDF_bookView_becomesAvailable_andCanBeOpened() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))

        let bookMode = LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfMode.book")
        XCTAssertTrue(bookMode.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(bookMode, timeout: 45), "Book View should become available for a text PDF")
        bookMode.click()

        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.toc").waitForExistence(timeout: 12))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.readingLayout").waitForExistence(timeout: 12))
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: "leo.reader.dictionarySmoke").waitForExistence(timeout: 20),
            "Book View should keep the EPUB dictionary overlay"
        )
    }

    func testPDF_relaunch_restoresOriginalPDFPagePosition() throws {
        app.terminate()
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            bookURL: textPDFURL,
            extraEnvironment: [
                "LEO_UI_TEST_CAPTURE_PDF_PAGE": "1",
            ]
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        let savedPageProbe = LeoUXHarness.anyElement(in: app, identifier: "leo.reader.pdfPageProbe")
        XCTAssertTrue(savedPageProbe.waitForExistence(timeout: 20))
        let savedPageSummary = savedPageProbe.label + (savedPageProbe.value as? String ?? "")
        XCTAssertFalse(savedPageSummary.isEmpty, "Expected Original PDF to report a saved page summary")

        app.terminate()
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            bookURL: textPDFURL,
            extraEnvironment: [
                "LEO_UI_TEST_CAPTURE_PDF_PAGE": "1",
            ]
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        let restoredPageProbe = LeoUXHarness.anyElement(in: app, identifier: "leo.reader.pdfPageProbe")
        XCTAssertTrue(restoredPageProbe.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForPageLabelContains(restoredPageProbe, text: savedPageSummary, timeout: 35))
    }

    func testPDF_relaunch_restoresBookViewMode_andPosition() throws {
        app.terminate()
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            bookURL: textPDFURL,
            extraEnvironment: [
                "LEO_UI_TEST_SHOW_LOOKUP": "1",
                "LEO_UI_TEST_LOOKUP_WORD": "你好",
                "LEO_UI_TEST_CAPTURE_LOCATOR": "1",
            ]
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        let bookMode = LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfMode.book")
        XCTAssertTrue(waitForEnabled(bookMode, timeout: 45))
        bookMode.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        let locatorBeforeRelaunch = try waitForLocatorSnapshot(
            timeout: 35,
            failureMessage: "Expected Book View to report a saved locator"
        ) { snapshot in
            snapshot.count >= 1 && snapshot.cfi != "pending"
        }

        app.terminate()
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            bookURL: textPDFURL,
            extraEnvironment: [
                "LEO_UI_TEST_SHOW_LOOKUP": "1",
                "LEO_UI_TEST_LOOKUP_WORD": "你好",
                "LEO_UI_TEST_CAPTURE_LOCATOR": "1",
            ]
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        let restoredLocator = try waitForLocatorSnapshot(
            timeout: 35,
            failureMessage: "Expected Book View to restore the saved locator"
        ) { snapshot in
            snapshot.count >= 1 && (
                snapshot.cfi == locatorBeforeRelaunch.cfi
                || abs(snapshot.fraction - locatorBeforeRelaunch.fraction) < 0.01
            )
        }
        XCTAssertTrue(
            restoredLocator.cfi == locatorBeforeRelaunch.cfi
                || abs(restoredLocator.fraction - locatorBeforeRelaunch.fraction) < 0.01
        )
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: "leo.reader.dictionarySmoke").waitForExistence(timeout: 15),
            "Book View should still expose the dictionary overlay after relaunch"
        )
    }

    private struct LocatorSnapshot {
        let count: Int
        let fraction: Double
        let cfi: String
    }

    private func waitForLocatorSnapshot(
        timeout: TimeInterval,
        failureMessage: String,
        predicate: (LocatorSnapshot) -> Bool
    ) throws -> LocatorSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        let identifier = "leo.reader.locatorProbe"
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: identifier).waitForExistence(timeout: timeout),
            "Expected locator probe to appear"
        )

        while Date() < deadline {
            let probe = LeoUXHarness.anyElement(in: app, identifier: identifier)
            let raw = probe.label + (probe.value as? String ?? "")
            if let snapshot = extractLocatorSnapshot(from: raw), predicate(snapshot) {
                return snapshot
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail(failureMessage)
        return LocatorSnapshot(count: 0, fraction: 0, cfi: "pending")
    }

    private func extractLocatorSnapshot(from text: String) -> LocatorSnapshot? {
        let pattern = #"count=([0-9]+)\s+fraction=([0-9]+\.[0-9]+)\s+cfi=(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let countRange = Range(match.range(at: 1), in: text),
              let fractionRange = Range(match.range(at: 2), in: text),
              let cfiRange = Range(match.range(at: 3), in: text) else {
            return nil
        }
        guard let count = Int(text[countRange]),
              let fraction = Double(text[fractionRange]) else {
            return nil
        }
        return LocatorSnapshot(count: count, fraction: fraction, cfi: String(text[cfiRange]))
    }

    private func waitForPageLabelContains(_ element: XCUIElement, text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let raw = element.label + (element.value as? String ?? "")
            if raw.contains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return (element.label + (element.value as? String ?? "")).contains(text)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.isEnabled
    }
}

// MARK: - FSRS review (seeded card)

@MainActor
final class LeoUXFSRSReviewTests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = try LeoUXHarness.makeFreshDataDirectory(for: self)
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            extraEnvironment: [
                "LEO_UI_TEST_SEED_FSRS_CARD": "1",
                "LEO_UI_TEST_FSRS_WORD": "你好",
            ]
        )
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground { app.terminate() }
    }

    func testFSRS_seededCard_review_showAnswer_rateGood_endsSession() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let reviewBtn = LeoUXHarness.anyElement(in: app, identifier: "leo.sidebar.review")
        XCTAssertTrue(reviewBtn.waitForExistence(timeout: 12))
        reviewBtn.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.review.root").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["你好"].waitForExistence(timeout: 10))
        let show = try XCTUnwrap(
            LeoUXHarness.firstExisting(
                [
                    LeoUXHarness.button(in: app, identifier: "leo.review.showAnswer"),
                    LeoUXHarness.button(in: app, label: "Show Answer"),
                ],
                timeout: 8
            ),
            "Review flow should expose Show Answer"
        )
        show.click()
        let good = try XCTUnwrap(
            LeoUXHarness.firstExisting(
                [
                    LeoUXHarness.button(in: app, identifier: "leo.review.rate.good"),
                    LeoUXHarness.button(in: app, label: "Good"),
                    LeoUXHarness.buttonContainingLabel(in: app, text: "Good"),
                ],
                timeout: 10
            ),
            "Review flow should expose a Good rating action"
        )
        good.click()
        XCTAssertTrue(
            app.staticTexts["All caught up!"].waitForExistence(timeout: 15),
            "After rating the only due card, review should show completion"
        )
    }
}

// MARK: - PDF low-confidence prep

@MainActor
final class LeoUXPDFLowConfidenceTests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = try LeoUXHarness.makeFreshDataDirectory(for: self)
        let blankPDF = try LeoUXPDFFixtures.makeBlankPDF(pageCount: 2)
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            bookURL: blankPDF,
            extraEnvironment: [
                "LEO_UI_TEST_CAPTURE_PDF_PAGE": "1",
            ]
        )
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground { app.terminate() }
    }

    func testPDF_lowConfidencePrep_keepsOriginalPDFAvailable_andShowsUnavailableState() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))

        XCTAssertTrue(LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfMode.original").waitForExistence(timeout: 15))
        XCTAssertTrue(LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfLayout").waitForExistence(timeout: 15))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.reader.pdfPageProbe").waitForExistence(timeout: 20))

        let unavailable = app.staticTexts["Book View unavailable"]
        let extractionFailure = app.staticTexts["Leo couldn't extract enough readable text to build Book View."]
        let statusFallback = app.staticTexts["Leo couldn't build a usable Book View from this PDF."]
        XCTAssertTrue(
            unavailable.waitForExistence(timeout: 30)
                || extractionFailure.waitForExistence(timeout: 30)
                || statusFallback.waitForExistence(timeout: 30),
            "Low-confidence PDFs should surface a clear Book View unavailable state"
        )
        XCTAssertTrue(
            LeoUXHarness.button(in: app, identifier: "leo.toolbar.pdfMode.original").isEnabled,
            "Original PDF mode should stay available"
        )
    }
}
