import XCTest

/// Reader + dictionary UX: launched with `LEO_UI_TEST_BOOK_PATH` (bundled `smoke.epub`) and optional dictionary smoke env.
@MainActor
final class LeoUXReaderTests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = try LeoUXHarness.makeFreshDataDirectory(for: self)
        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            fixture: (name: "smoke", ext: "epub"),
            extraEnvironment: [
                "LEO_UI_TEST_SHOW_LOOKUP": "1",
                "LEO_UI_TEST_LOOKUP_WORD": "你好",
            ]
        )
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground {
            app.terminate()
        }
    }

    func testReader_withFixture_showsThemeToolbarAndDictionarySmoke() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))

        let theme = LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme")
        XCTAssertTrue(theme.waitForExistence(timeout: 20), "Theme picker should appear when Smoke EPUB is selected")

        let layout = LeoUXHarness.button(in: app, identifier: "leo.toolbar.readingLayout")
        XCTAssertTrue(layout.waitForExistence(timeout: 8), "Reading layout control should appear for EPUB")

        let dictSmoke = LeoUXHarness.anyElement(in: app, identifier: "leo.reader.dictionarySmoke")
        XCTAssertTrue(dictSmoke.waitForExistence(timeout: 35), "Dictionary smoke label should appear after cedict load")
        let combined = dictSmoke.label + (dictSmoke.value as? String ?? "")
        XCTAssertTrue(
            combined.contains("你好") || combined.localizedCaseInsensitiveContains("hello"),
            "Expected 你好 lookup text in AX; got label=\(dictSmoke.label) value=\(String(describing: dictSmoke.value))"
        )
    }

    func testReader_readingLayout_popoverShowsTypographyControls() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        let layoutBtn = LeoUXHarness.button(in: app, identifier: "leo.toolbar.readingLayout")
        XCTAssertTrue(layoutBtn.waitForExistence(timeout: 8))
        layoutBtn.click()
        let prefs = LeoUXHarness.anyElement(in: app, identifier: "leo.readingPrefs.form")
        XCTAssertTrue(prefs.waitForExistence(timeout: 12), "Popover should host ReadingPreferencesForm")
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 6), "Popover should expose typography controls")
    }

    func testReader_startSession_showsActiveTimerChrome() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        let start = LeoUXHarness.button(in: app, label: "Start Session")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.click()
        XCTAssertTrue(
            LeoUXHarness.anyElement(in: app, identifier: "leo.reader.sessionActive").waitForExistence(timeout: 8),
            "Active session should expose stop/timer group"
        )
    }

    func testReader_relaunch_restoresSavedProgress() throws {
        if app.state == .runningForeground {
            app.terminate()
        }

        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            fixture: (name: "smoke", ext: "epub"),
            extraEnvironment: [
                "LEO_UI_TEST_CAPTURE_LOCATOR": "1",
                "LEO_UI_TEST_AUTO_ADVANCE_PAGE": "1",
            ]
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        let firstSnapshot = try waitForLocatorSnapshot(
            timeout: 35,
            failureMessage: "Expected Leo to report its initial locator"
        ) { snapshot in
            snapshot.count >= 1 && snapshot.cfi != "pending"
        }
        let advancedSnapshot = try waitForLocatorSnapshot(
            timeout: 35,
            failureMessage: "Expected Leo to advance away from the opening locator"
        ) { snapshot in
            snapshot.count >= 2 && snapshot.cfi != firstSnapshot.cfi
        }
        app.terminate()

        app = try LeoUXHarness.launchApp(
            for: self,
            dataDirectory: dataDirectory,
            fixture: (name: "smoke", ext: "epub"),
            extraEnvironment: [
                "LEO_UI_TEST_CAPTURE_LOCATOR": "1",
            ]
        )

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.toolbar.theme").waitForExistence(timeout: 20))
        let restoredSnapshot = try waitForLocatorSnapshot(
            timeout: 35,
            failureMessage: "Expected Leo to relocate back to the saved locator after relaunch"
        ) { snapshot in
            snapshot.count >= 2 && snapshot.cfi == advancedSnapshot.cfi
        }
        XCTAssertEqual(
            restoredSnapshot.cfi,
            advancedSnapshot.cfi,
            "Expected Leo to reopen at the saved reading locator"
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
}
