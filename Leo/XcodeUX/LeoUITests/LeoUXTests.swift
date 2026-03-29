import XCTest

@MainActor
enum LeoUXHarness {
    static let appBundleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("build/LeoUITest.app")

    static func makeFreshDataDirectory(for testCase: XCTestCase) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LeoUX", isDirectory: true)
            .appendingPathComponent(sanitizedName(for: testCase), isDirectory: true)

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func launchApp(
        for testCase: XCTestCase,
        dataDirectory: URL,
        fixture: (name: String, ext: String)? = nil,
        extraEnvironment: [String: String] = [:]
    ) throws -> XCUIApplication {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appBundleURL.path),
            "Missing \(appBundleURL.path). Run ./scripts/run-ux-tests.sh from Leo/."
        )

        let app = XCUIApplication(url: appBundleURL)
        var environment = extraEnvironment
        environment["LEO_UI_TEST_DATA_DIR"] = dataDirectory.path

        if let fixture {
            let fixtureURL = try XCTUnwrap(
                Bundle(for: type(of: testCase)).url(forResource: fixture.name, withExtension: fixture.ext),
                "Missing \(fixture.name).\(fixture.ext) in LeoUITests resources"
            )
            environment["LEO_UI_TEST_BOOK_PATH"] = fixtureURL.path
        }

        app.launchEnvironment = environment
        app.launchArguments = []
        app.launch()
        return app
    }

    static func anyElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    static func button(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    static func button(in app: XCUIApplication, label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    static func buttonContainingLabel(in app: XCUIApplication, text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    static func firstExisting(_ candidates: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let existing = candidates.first(where: { $0.exists }) {
                return existing
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return candidates.first(where: { $0.exists })
    }

    static func labeledControl(in app: XCUIApplication, label: String, timeout: TimeInterval) -> XCUIElement? {
        let predicate = NSPredicate(format: "label == %@", label)
        return firstExisting(
            [
                app.radioButtons.matching(predicate).firstMatch,
                app.buttons.matching(predicate).firstMatch,
                app.staticTexts.matching(predicate).firstMatch,
                app.descendants(matching: .any).matching(predicate).firstMatch,
            ],
            timeout: timeout
        )
    }

    private static func sanitizedName(for testCase: XCTestCase) -> String {
        testCase.name.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "_", options: .regularExpression)
    }
}

/// UI tests for `Leo/build/LeoUITest.app` (built by `./scripts/run-ux-tests.sh`).
/// Uses `XCUIApplication(url:)` so Launch Services / Spotlight is not required to resolve the bundle ID.
@MainActor
final class LeoUXTests: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = try LeoUXHarness.makeFreshDataDirectory(for: self)
        app = try LeoUXHarness.launchApp(for: self, dataDirectory: dataDirectory)
    }

    override func tearDownWithError() throws {
        if app?.state == .runningForeground {
            app.terminate()
        }
    }

    func testLaunch_mainWindowAndEmptyLibraryCopy() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25), "Leo should show a window")
        let emptyPrompt = app.staticTexts["Open a book to start reading"]
        XCTAssertTrue(emptyPrompt.waitForExistence(timeout: 15), "Empty-library detail should be visible")
        let split = LeoUXHarness.anyElement(in: app, identifier: "leo.root.split")
        if split.waitForExistence(timeout: 2) {
            XCTAssertTrue(split.exists)
        }
    }

    func testEmptyLibrary_importButton() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let byId = app.buttons["leo.library.import"]
        let byLabel = app.buttons["Import Book"]
        XCTAssertTrue(
            byId.waitForExistence(timeout: 12) || byLabel.waitForExistence(timeout: 4),
            "Import affordance should exist (identifier or label)"
        )
    }

    func testSettings_opensWithCommandComma() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: [.command])
        let settingsRoot = app.descendants(matching: .any)["leo.settings.root"]
        let generalTab = app.staticTexts["General"]
        XCTAssertTrue(
            settingsRoot.waitForExistence(timeout: 12) || generalTab.waitForExistence(timeout: 4),
            "Settings window should list General (tab label) or expose leo.settings.root"
        )
    }

    func testSidebar_reviewAndVocabularyRows_exist() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.sidebar.review").waitForExistence(timeout: 10))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.sidebar.vocabulary").waitForExistence(timeout: 8))
    }

    func testReviewSheet_opensFromSidebar_showsEmptyState() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let reviewBtn = LeoUXHarness.anyElement(in: app, identifier: "leo.sidebar.review")
        XCTAssertTrue(reviewBtn.waitForExistence(timeout: 10))
        reviewBtn.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.review.root").waitForExistence(timeout: 12))
        let caughtUp = app.staticTexts["All caught up!"]
        let noDue = app.staticTexts["No cards due for review."]
        XCTAssertTrue(
            caughtUp.waitForExistence(timeout: 8) || noDue.waitForExistence(timeout: 2),
            "Empty review session should show catch-up copy"
        )
    }

    func testVocabularySheet_opensFromSidebar_showsEmptyState() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let vocabBtn = LeoUXHarness.anyElement(in: app, identifier: "leo.sidebar.vocabulary")
        XCTAssertTrue(vocabBtn.waitForExistence(timeout: 10))
        vocabBtn.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.vocabulary.root").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["No vocabulary yet"].waitForExistence(timeout: 8))
    }

    func testSettings_tabs_voiceAnkiReading_reachable() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.settings.root").waitForExistence(timeout: 12))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.settings.tab.general").waitForExistence(timeout: 8))

        let voiceTab = try XCTUnwrap(
            LeoUXHarness.labeledControl(in: app, label: "Voice", timeout: 6),
            "Settings should expose the Voice tab"
        )
        voiceTab.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.settings.tab.voice").waitForExistence(timeout: 8))

        let ankiTab = try XCTUnwrap(
            LeoUXHarness.labeledControl(in: app, label: "Anki", timeout: 4),
            "Settings should expose the Anki tab"
        )
        ankiTab.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.settings.tab.anki").waitForExistence(timeout: 8))

        let readingTab = try XCTUnwrap(
            LeoUXHarness.labeledControl(in: app, label: "Reading", timeout: 4),
            "Settings should expose the Reading tab"
        )
        readingTab.click()
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.settings.tab.reading").waitForExistence(timeout: 8))
        XCTAssertTrue(LeoUXHarness.anyElement(in: app, identifier: "leo.readingPrefs.form").waitForExistence(timeout: 6))
    }
}
