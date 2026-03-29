import XCTest

// MARK: - PDF vs EPUB chrome

/// PDF fixture: bundled `smoke.pdf` (regenerate with `swiftc … scripts/gen-smoke-pdf.swift`).
@MainActor
final class LeoUXPDFReaderTests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = try LeoUXHarness.makeFreshDataDirectory(for: self)
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            fixture: (name: "smoke", ext: "pdf"),
            extraEnvironment: [
                "LEO_UI_TEST_SHOW_LOOKUP": "1",
                "LEO_UI_TEST_LOOKUP_WORD": "你好",
            ]
        )
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground { app.terminate() }
    }

    func testPDF_viewOnlyBanner_andNoEpubToolbarOrDictionaryOverlay() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: "leo.reader.pdfViewOnlyBanner").waitForExistence(timeout: 15),
            "PDF reader shows view-only banner"
        )
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 15))
        let layout = LeoUXHarness.button(in: app, identifier: "leo.toolbar.readingLayout")
        XCTAssertFalse(layout.waitForExistence(timeout: 2), "No reading-layout control for PDF")
        let overlay = LeoUXHarness.anyElement(in: app, identifier: "leo.reader.dictionarySmoke")
        XCTAssertFalse(overlay.waitForExistence(timeout: 2), "Dictionary smoke overlay is EPUB-only")
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
