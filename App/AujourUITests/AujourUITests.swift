import XCTest

// What only a running app can show. Everything about *what* a folder of files
// means, and about which day is today's, lives in Core where `swift test`
// covers it fast; these are the acceptance-level claims of M1 — someone who
// has just installed Aujour is looking at a journal folder that exists and at
// today's Entry, and what they type into it is in a file afterwards.
final class AujourUITests: XCTestCase {
    /// A folder of this test's own, so that one test's Entries are never the
    /// next one's journal. Reused by every launch within the test, which is
    /// how a relaunch is a relaunch and not a fresh install.
    private var journalFolder = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        journalFolder = UUID().uuidString
    }

    func testAFreshInstallFindsAJournalFolderWithoutBeingConfigured() throws {
        // Deliberately without a folder of its own: this is the claim about
        // an install nobody has configured, so it has to be the app's own
        // choice of folder that answers.
        let app = XCUIApplication()
        app.launch()

        // Asking iCloud for the app's container is slow the first time on a
        // device, so this is a wait rather than an assertion about a frame.
        let folderInfo = app.buttons["journalFolderInfo"]
        XCTAssertTrue(
            folderInfo.waitForExistence(timeout: 30),
            "the app did not settle on a journal folder — it is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
        folderInfo.tap()

        let location = app.staticTexts["journalRootLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertFalse(location.label.isEmpty)

        // And it can say where it is, in a path the user could go and find.
        let path = app.staticTexts["journalRootPath"]
        XCTAssertTrue(path.exists)
        XCTAssertTrue(path.label.hasPrefix("/"), "expected a folder path, got \(path.label)")

        // A folder it could not read would have been a problem notice instead.
        XCTAssertTrue(app.staticTexts["journalFileCount"].exists)
        XCTAssertFalse(app.staticTexts["storageProblem"].exists)
    }

    func testTodayIsSpawnedFromTheTemplateWithoutTouchingTheFolder() throws {
        let app = launchApp(contentTemplate: "# {{title}}\n\n{{mood}}\n")

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        // The template, resolved: today's Entry is titled after its own file
        // name, and the interactive placeholder is still literal text.
        let spawned = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(
            spawned.contains("# \(todaysEntryName())"),
            "expected the template's title to be resolved, got: \(spawned)"
        )
        XCTAssertTrue(
            spawned.contains("{{mood}}"),
            "expected {{mood}} to stay literal for the editor to own, got: \(spawned)"
        )

        // And none of it is a file: a day nobody wrote on leaves no husk
        // behind, which the next launch is what proves.
        relaunch(app)
        XCTAssertEqual(fileCountAfterOpeningTheFolderSheet(app), "0 files")
    }

    func testWhatIsTypedIsStillThereAfterARelaunch() throws {
        let app = launchApp()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()
        editor.typeText("Walked to the market.")

        // Autosave is debounced by a second, so this is the wait for a save
        // nobody asked for — the point of the test is that it happens on its
        // own, without a save button and without backgrounding the app.
        Thread.sleep(forTimeInterval: 4)
        relaunch(app)

        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "Walked to the market.")
        XCTAssertEqual(fileCountAfterOpeningTheFolderSheet(app), "1 file")
    }

    // MARK: - Driving the app

    /// Launches the app onto a journal folder of this test's own.
    private func launchApp(contentTemplate: String = "") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AUJOUR_UITEST_JOURNAL_FOLDER"] = journalFolder
        app.launchEnvironment["AUJOUR_UITEST_CONTENT_TEMPLATE"] = contentTemplate
        app.launch()
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func fileCountAfterOpeningTheFolderSheet(_ app: XCUIApplication) -> String {
        let folderInfo = app.buttons["journalFolderInfo"]
        guard folderInfo.waitForExistence(timeout: 30) else { return "the journal never opened" }
        folderInfo.tap()

        let fileCount = app.staticTexts["journalFileCount"]
        guard fileCount.waitForExistence(timeout: 5) else { return "no file count was shown" }
        return fileCount.label
    }

    /// The name today's Entry file carries under the default Path Template —
    /// what `{{title}}` resolves to.
    private func todaysEntryName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
