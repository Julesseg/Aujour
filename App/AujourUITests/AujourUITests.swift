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

    func testAPastDayIsFilledInFromTheCalendar() throws {
        let app = launchApp(contentTemplate: "# {{title}}\n")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        let yesterday = try XCTUnwrap(dayBeforeToday())
        openCalendar(app, showingTheMonthOf: yesterday)

        // A day nobody has written on, which is the whole premise of
        // backfilling it.
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "yesterday was not on the calendar")
        XCTAssertEqual(cell.value as? String, "Not written")
        cell.tap()

        // Spawned from the template with *that* day's date, not today's.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "yesterday's entry never opened")
        let spawned = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(
            spawned.contains("# \(entryName(for: yesterday))"),
            "expected yesterday's entry to be titled after its own day, got: \(spawned)"
        )
        XCTAssertFalse(
            spawned.contains(todaysEntryName()),
            "yesterday's entry was spawned with today's date: \(spawned)"
        )

        editor.tap()
        editor.typeText("Filled in the next morning.")
        goBack(app)

        // The indicator follows the file: the day was written on, so it is
        // marked, and it was marked by re-reading the folder.
        expect(cell, toHaveValue: "Written")

        // And it is all in a file — which the next launch, with nothing kept
        // from this one, is what proves.
        relaunch(app)
        openCalendar(app, showingTheMonthOf: yesterday)
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "yesterday was not on the calendar")
        expect(cell, toHaveValue: "Written")
        cell.tap()

        XCTAssertTrue(editor.waitForExistence(timeout: 10), "yesterday's entry never reopened")
        let written = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(
            written.contains("Filled in the next morning."),
            "expected yesterday's words to have been written to its file, got: \(written)"
        )
    }

    func testAFutureDayIsOnTheCalendarAndCannotBeWrittenIn() throws {
        let app = launchApp()
        let tomorrow = try XCTUnwrap(dayAfterToday())
        openCalendar(app, showingTheMonthOf: tomorrow)

        let cell = app.buttons["day-\(entryName(for: tomorrow))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "tomorrow was not on the calendar")
        XCTAssertFalse(cell.isEnabled, "a day that has not arrived cannot be written in")

        // Tapped anyway: a locked day is one that does nothing, not one that
        // opens an editor nobody can save from. Guarded because a tap at a
        // place the app will not accept one is a failure about the tap, and
        // this test is not about taps.
        if cell.isHittable { cell.tap() }
        XCTAssertFalse(
            app.textViews["entryEditor"].waitForExistence(timeout: 3),
            "tomorrow was opened for editing"
        )
    }

    // MARK: - Driving the app

    /// Launches the app onto a journal folder of this test's own.
    ///
    /// The two keys are spelled out rather than shared: the app and the UI
    /// suite are separate targets, and this suite deliberately imports
    /// nothing from the app it is driving. Their other half is
    /// `UITestingJournal`, which is where they are read.
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

    /// Opens the calendar and steps to the month a day is in.
    ///
    /// One step at most, because the days these tests are about are either
    /// side of today — and the step is needed at all only on the 1st and the
    /// last of a month, which is exactly when a calendar gets it wrong.
    private func openCalendar(_ app: XCUIApplication, showingTheMonthOf day: Date) {
        let calendar = app.buttons["openCalendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 30), "the journal never opened")
        calendar.tap()
        XCTAssertTrue(
            app.staticTexts["calendarMonth"].waitForExistence(timeout: 10),
            "the calendar never appeared"
        )

        let months = Calendar.current.dateComponents(
            [.month],
            from: startOfMonth(Date()),
            to: startOfMonth(day)
        ).month ?? 0
        if months < 0 { app.buttons["previousMonth"].tap() }
        if months > 0 { app.buttons["nextMonth"].tap() }
    }

    /// Back up one screen — the way out of a day, and out of the calendar.
    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Waits for an element to say something. The folder is read after the
    /// words are saved, so an indicator arrives a moment after the day it
    /// belongs to has been written in.
    ///
    /// Polled rather than awaited on an `XCTestExpectation`: waiting on one
    /// hands the test case itself to the main actor, and a test case is not
    /// `Sendable`.
    private func expect(
        _ element: XCUIElement,
        toHaveValue value: String,
        timeout: TimeInterval = 10
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, element.value as? String != value {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(element.value as? String, value)
    }

    private func dayBeforeToday() -> Date? {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())
    }

    private func dayAfterToday() -> Date? {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())
    }

    private func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: date)
        )!
    }

    /// The name a day's Entry file carries under the default Path Template —
    /// what `{{title}}` resolves to, and what the calendar names its cells by.
    private func entryName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func todaysEntryName() -> String {
        entryName(for: Date())
    }
}
