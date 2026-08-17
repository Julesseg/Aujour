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
        XCTAssertTrue(app.staticTexts["journalEntryCount"].exists)
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
        XCTAssertEqual(entryCountAfterOpeningTheFolderSheet(app), "0 entries")
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
        XCTAssertEqual(entryCountAfterOpeningTheFolderSheet(app), "1 entry")
    }

    /// The claim the editor is worth nothing without: it draws markdown, and
    /// writes plain text.
    ///
    /// What the drawing *looks like* is not here — a heading's point size, and
    /// which marks a moving caret hides, are checked where a font and a line
    /// exist to check them, in `MarkdownTextStorageTests` and
    /// `HiddenSyntaxDrawingTests`. What only a running app can show is that a
    /// day typed as markdown, and hidden and revealed under a caret since,
    /// comes back out of the folder character for character: no markup the
    /// editor added, no curly quote where an apostrophe was typed, no em dash
    /// where two hyphens were.
    func testMarkdownIsWrittenToTheFileExactlyAsItWasTyped() throws {
        let app = launchApp()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()

        // Every line starts with a capital the test typed itself, so that
        // autocapitalisation has nothing it could change.
        //
        // The second bullet is not typed: a return at the end of a list item
        // opens the next one, which is the one keystroke this editor answers
        // itself (`MarkdownReturnTests`). What that leaves in the file is
        // still markdown somebody could have typed, which is the claim here.
        let entry = "# Sunday\n\nWalked to the *market* -- it's shut.\n\n- Milk\n- **Bread**"
        editor.typeText("# Sunday\n\nWalked to the *market* -- it's shut.\n\n- Milk\n**Bread**")

        // And the caret away from the last thing typed, which is what makes
        // the marks hide (`HiddenSyntaxDrawingTests` has the hiding itself).
        // By coordinate rather than `editor.tap()`: the keyboard is up by now
        // and covers the text view's middle, so a tap there would land on a
        // key and type it.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.05)).tap()
        XCTAssertEqual(editor.value as? String, entry)

        Thread.sleep(forTimeInterval: 4)
        relaunch(app)

        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, entry)
        XCTAssertEqual(entryCountAfterOpeningTheFolderSheet(app), "1 entry")
    }

    /// A checkbox is the one thing in an Entry that answers a tap, and the
    /// whole of what it does is rewrite one character of the file.
    ///
    /// Whether a box is drawn at all, and where, is
    /// `DrawnMarkdownDrawingTests` — headless, and exact. What only a running
    /// app can show is that a finger on the box changes the markdown, that the
    /// caret does not go chasing it, and that what reaches the folder is a
    /// plain task list somebody could open in Obsidian.
    func testTappingACheckboxTicksItInTheFile() throws {
        let app = launchApp()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()

        // Typed rather than seeded, because a file the launch environment
        // seeds is seeded again on the next launch — and this test is about
        // what survives one.
        //
        // The second task's `- [ ] ` is not typed: the return at the end of
        // the first opens it, empty box and all.
        editor.typeText("- [ ] Milk\nBread")

        // The first line's box, a little in from the top left corner of the
        // text. The caret is on the second line by now, so the first one is
        // drawn as a box — and it is aimed at by coordinate because a box is a
        // drawing rather than a view: there is nothing in the hierarchy to
        // find, and nothing was added to the text to find either (ADR 0001).
        //
        // In points from the corner rather than as a fraction of the editor,
        // whose height is whatever the keyboard has left of the screen.
        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()
        expect(editor, toHaveValue: "- [x] Milk\n- [ ] Bread")

        Thread.sleep(forTimeInterval: 4)
        relaunch(app)

        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "- [x] Milk\n- [ ] Bread")
        XCTAssertEqual(entryCountAfterOpeningTheFolderSheet(app), "1 entry")
    }

    /// The formatting row above the keyboard: the marks a journal is written
    /// with, one tap on glass.
    ///
    /// What each control writes, and where it leaves the cursor, is decided in
    /// Core and tested there against the text it rewrites; that a press reaches
    /// the Entry the app is saving is `MarkdownAccessoryRowTests`, headless.
    /// What only a running app can show is the rest of the claim: the row is
    /// there while the day is being written in and gone while it is not, the
    /// controls are aimed at what the cursor is on, and what they wrote is
    /// plain markdown in the file afterwards.
    func testTheFormattingRowWritesMarkdownWhereTheCursorIs() throws {
        let app = launchApp()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        // Nobody is writing in it yet: no keyboard, and so no row.
        XCTAssertFalse(
            app.buttons["formatBold"].exists,
            "the formatting row was up over a day nobody was writing in"
        )

        editor.tap()
        let bold = app.buttons["formatBold"]
        XCTAssertTrue(bold.waitForExistence(timeout: 10), "the formatting row never appeared")

        // The line becomes a task, the box is ticked, the word being written
        // becomes bold, and the whole line steps in — each of them where the
        // cursor is, and none of them aimed at.
        editor.typeText("Milk")
        let checkbox = app.buttons["formatTaskList"]
        checkbox.tap()
        expect(editor, toHaveValue: "- [ ] Milk")

        // The one thing a finger on the box is otherwise the only way to do,
        // which is why the control goes round three states rather than two.
        checkbox.tap()
        expect(editor, toHaveValue: "- [x] Milk")

        bold.tap()
        expect(editor, toHaveValue: "- [x] **Milk**")

        app.buttons["formatIndent"].tap()
        expect(editor, toHaveValue: "  - [x] **Milk**")

        // The way to a photograph is on the row and is not offered yet: its
        // flow is the attachment pipeline's (issue #22).
        XCTAssertTrue(app.buttons["insertPhoto"].exists, "there was no way to a photo on the row")
        XCTAssertFalse(app.buttons["insertPhoto"].isEnabled)

        // And what the row wrote is in the file, exactly as a hand would have
        // typed it — which the relaunch is what proves.
        Thread.sleep(forTimeInterval: 4)
        relaunch(app)

        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "  - [x] **Milk**")
        // A day being read has no keyboard, and the row is gone with it.
        XCTAssertFalse(
            app.buttons["formatBold"].exists,
            "the formatting row outlived the keyboard it came up with"
        )
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

        XCTAssertTrue(
            editor.waitForExistence(timeout: 10),
            "yesterday's entry never reopened — the screen is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
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

    func testTheJournalMovesToAPickedFolderAndStaysThere() throws {
        // The folder that stands in for one picked in the Files app. Driving
        // the picker itself would be a test of another process's screen; what
        // is under test here is everything after the tap — the folder becomes
        // the journal, it is still the journal next launch, and the user can
        // come back.
        let vault = UUID().uuidString
        let app = launchApp(folderToPick: vault)

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()
        editor.typeText("Written in Aujour's own folder.")
        Thread.sleep(forTimeInterval: 4)

        // Where a journal nobody has moved lives.
        openFolderSheet(app)
        XCTAssertEqual(app.staticTexts["journalRootLocation"].label, "On My iPhone › Aujour")
        XCTAssertEqual(app.staticTexts["journalEntryCount"].label, "1 entry")

        // Pointed at a folder of the user's own: the journal is that folder
        // from now on, and it is empty because that folder is.
        app.buttons["chooseCustomFolder"].tap()
        expect(app.staticTexts["journalRootLocation"], toHaveLabel: vault)
        XCTAssertEqual(app.staticTexts["journalEntryCount"].label, "0 entries")
        app.buttons["Done"].tap()

        // Today is a day nobody has written on there, and writing in it
        // writes into that folder.
        let inTheVault = app.textViews["entryEditor"]
        XCTAssertTrue(inTheVault.waitForExistence(timeout: 10), "today never reopened")
        XCTAssertEqual(inTheVault.value as? String, "")
        inTheVault.tap()
        inTheVault.typeText("Written in the folder I picked.")
        Thread.sleep(forTimeInterval: 4)

        // Still that folder after a relaunch — which is the bookmark, since
        // nothing else about the choice outlives the launch.
        relaunch(app)
        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "Written in the folder I picked.")
        openFolderSheet(app)
        XCTAssertEqual(app.staticTexts["journalRootLocation"].label, vault)
        XCTAssertEqual(app.staticTexts["journalEntryCount"].label, "1 entry")

        // And the way back: Aujour's own folder, with everything that was
        // written there still in it.
        app.buttons["useAujoursOwnFolder"].tap()
        expect(app.staticTexts["journalRootLocation"], toHaveLabel: "On My iPhone › Aujour")
        XCTAssertEqual(app.staticTexts["journalEntryCount"].label, "1 entry")
        app.buttons["Done"].tap()

        let backHome = app.textViews["entryEditor"]
        XCTAssertTrue(backHome.waitForExistence(timeout: 10), "today never reopened")
        XCTAssertEqual(backHome.value as? String, "Written in Aujour's own folder.")
    }

    func testADayWrittenOnTwoDevicesKeepsBothVersionsAndSaysSo() throws {
        // The day was written here and on the iPad, and iCloud has come back
        // holding both. Making that happen takes two devices and a sync, so
        // the suite says at launch what iCloud would have been holding;
        // everything after that is the app deciding and doing.
        let app = launchApp(
            todaysEntry: "Written on this iPhone.",
            divergedVersion: "Written on the iPad."
        )

        // The version written last is the one at the day's own path, and so
        // the one in front of the user.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        expect(editor, toHaveValue: "Written on the iPad.")

        // And the one it displaced was not dropped: it is a file beside the
        // entry, and the app says which, because a file nobody knows about is
        // a file nobody merges.
        let notice = app.staticTexts["parkedFileNotice"]
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "nothing on screen said the other version had been kept"
        )
        let parkedName = "\(todaysEntryName())_1.md"
        XCTAssertTrue(
            app.staticTexts["parkedFileNames"].label.contains(parkedName),
            "the notice did not name \(parkedName): "
                + app.staticTexts["parkedFileNames"].label
        )

        // The Parked File is beside the journal and not in it: one day
        // written, one entry, whatever else is in the folder (ADR 0002).
        XCTAssertEqual(entryCountAfterOpeningTheFolderSheet(app), "1 entry")
        app.buttons["Done"].tap()

        // Dismissible, because the file itself is the lasting notice.
        app.buttons["dismissParkedFileNotice"].tap()
        XCTAssertFalse(notice.waitForExistence(timeout: 3))
    }

    func testChangingWhereEntriesGoOffersToMoveThemAndMovesThem() throws {
        // A day this device already journaled, under the entry path a fresh
        // install starts with — so there is something for the migration to
        // be about.
        let app = launchApp(todaysEntry: "Walked to the market.")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openFolderSheet(app)
        XCTAssertEqual(app.staticTexts["journalEntryCount"].label, "1 entry")
        typeEntryPath("[Journal]/YYYY-MM-DD", into: app)

        // Changing it is an offer, not a change: the files are still where
        // they were until this is answered (ADR 0002).
        app.buttons["changeEntryPath"].tap()
        let prompt = app.staticTexts["migrationPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15), "nothing offered to move the entries")
        XCTAssertEqual(prompt.label, "Move your 1 entry?")
        // And it says the one thing about renaming daily notes that nobody
        // would guess (ADR 0002).
        XCTAssertTrue(app.staticTexts["migrationLinkWarning"].exists)

        app.buttons["moveEntries"].tap()
        let summary = app.staticTexts["migrationSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "the migration never finished")
        XCTAssertEqual(summary.label, "1 entry moved.")
        app.buttons["dismissMigrationSummary"].tap()

        // Still one entry, and the same words — moved, not copied and not
        // lost. The count is read from the folder, so this is the file being
        // where the new template says.
        expect(app.staticTexts["journalEntryCount"], toHaveLabel: "1 entry")
        XCTAssertEqual(app.textFields["entryPathField"].value as? String, "[Journal]/YYYY-MM-DD")
        app.buttons["Done"].tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never reopened")
        expect(editor, toHaveValue: "Walked to the market.")

        // And the entry path outlives the launch, the way every other
        // journal-shaping setting does (ADR 0003).
        relaunch(app)
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 30))
        XCTAssertEqual(entryCountAfterOpeningTheFolderSheet(app), "1 entry")
        XCTAssertEqual(app.textFields["entryPathField"].value as? String, "[Journal]/YYYY-MM-DD")
    }

    func testSkippingTheMigrationLeavesTheOldFilesWhereTheyAreAndUnsurfaced() throws {
        let app = launchApp(todaysEntry: "Walked to the market.")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openFolderSheet(app)
        typeEntryPath("[Journal]/YYYY-MM-DD", into: app)
        app.buttons["changeEntryPath"].tap()
        XCTAssertTrue(
            app.staticTexts["migrationPrompt"].waitForExistence(timeout: 15),
            "nothing offered to move the entries"
        )

        app.buttons["skipMigration"].tap()

        // The old file is still in the folder and is no longer an Entry: the
        // count is a scan of the folder against the *current* template, and
        // nothing anywhere else surfaces what was left behind (ADR 0002).
        expect(app.staticTexts["journalEntryCount"], toHaveLabel: "0 entries")
        app.buttons["Done"].tap()

        // Today, under the new path, is a day nobody has written on.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never reopened")
        expect(editor, toHaveValue: "")

        // Not on the calendar either — a skipped migration orphans the old
        // files completely, which is the deal ADR 0002 makes.
        openCalendar(app, showingTheMonthOf: Date())
        let today = app.buttons["day-\(todaysEntryName())"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today was not on the calendar")
        XCTAssertEqual(today.value as? String, "Not written")
    }

    func testAMigrationOntoAnOccupiedPathKeepsBothFiles() throws {
        // The vault already keeps a note where the new entry path would put
        // today — which is exactly how two files come to claim one day.
        let app = launchApp(
            todaysEntry: "Written in Aujour.",
            vaultNote: (at: "Journal/\(todaysEntryName()).md", saying: "Written in Obsidian.")
        )
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openFolderSheet(app)
        typeEntryPath("[Journal]/YYYY-MM-DD", into: app)
        app.buttons["changeEntryPath"].tap()

        // The collision is named before anything moves — being asked is the
        // whole of ADR 0002's rule here.
        let collisions = app.staticTexts["migrationCollisions"]
        XCTAssertTrue(collisions.waitForExistence(timeout: 15), "the collision was never mentioned")
        XCTAssertEqual(collisions.label, "1 day already has a file where it would go")

        app.buttons["moveEntries"].tap()
        XCTAssertTrue(
            app.staticTexts["migrationSummary"].waitForExistence(timeout: 30),
            "the migration never finished"
        )
        let parked = app.staticTexts["migrationParkedFiles"]
        XCTAssertTrue(parked.exists, "nothing said where the second version went")
        XCTAssertTrue(
            parked.label.contains("\(todaysEntryName())_1.md"),
            "the summary did not name the parked file: \(parked.label)"
        )
        app.buttons["dismissMigrationSummary"].tap()

        // One day, one Entry: the file that was already there. The version
        // Aujour brought is beside it and is not an Entry (ADR 0002).
        expect(app.staticTexts["journalEntryCount"], toHaveLabel: "1 entry")
        app.buttons["Done"].tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never reopened")
        expect(editor, toHaveValue: "Written in Obsidian.")
    }

    // MARK: - Driving the app

    /// Launches the app onto a journal folder of this test's own.
    ///
    /// The keys are spelled out rather than shared: the app and the UI suite
    /// are separate targets, and this suite deliberately imports nothing from
    /// the app it is driving. Their other half is `UITestingJournal`, which is
    /// where they are read.
    ///
    /// - Parameters:
    ///   - folderToPick: the folder "Use a custom folder…" picks, in place of
    ///     the Files picker.
    ///   - todaysEntry: what today's Entry file already says, written an hour
    ///     ago — a day this device journaled before the app was opened.
    ///   - divergedVersion: what another device wrote for today, which iCloud
    ///     is holding as an unresolved version of the same file. Dated at
    ///     launch, so it is the newer of the two.
    ///   - vaultNote: a file the folder already holds that is none of Aujour's
    ///     business — a note the vault made — and the path it sits at.
    private func launchApp(
        contentTemplate: String = "",
        folderToPick: String? = nil,
        todaysEntry: String? = nil,
        divergedVersion: String? = nil,
        vaultNote: (at: String, saying: String)? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AUJOUR_UITEST_JOURNAL_FOLDER"] = journalFolder
        app.launchEnvironment["AUJOUR_UITEST_CONTENT_TEMPLATE"] = contentTemplate
        if let folderToPick {
            app.launchEnvironment["AUJOUR_UITEST_FOLDER_TO_PICK"] = folderToPick
        }
        if let todaysEntry {
            app.launchEnvironment["AUJOUR_UITEST_TODAYS_ENTRY"] = todaysEntry
        }
        if let divergedVersion {
            app.launchEnvironment["AUJOUR_UITEST_DIVERGED_VERSION"] = divergedVersion
        }
        if let vaultNote {
            app.launchEnvironment["AUJOUR_UITEST_VAULT_NOTE_AT"] = vaultNote.at
            app.launchEnvironment["AUJOUR_UITEST_VAULT_NOTE"] = vaultNote.saying
        }
        app.launch()
        return app
    }

    /// Opens the sheet that says where the journal is kept and offers to move
    /// it.
    private func openFolderSheet(_ app: XCUIApplication) {
        let folderInfo = app.buttons["journalFolderInfo"]
        XCTAssertTrue(folderInfo.waitForExistence(timeout: 30), "the journal never opened")
        folderInfo.tap()
        XCTAssertTrue(
            app.staticTexts["journalRootLocation"].waitForExistence(timeout: 10),
            "the folder sheet never appeared"
        )
    }

    /// Replaces what is in the entry path field, and puts the keyboard away.
    ///
    /// Cleared a character at a time from the end, because a text field's
    /// whole contents cannot be selected without a hardware keyboard the
    /// simulator does not have. The tap is at the far right of the field so
    /// that the cursor is behind the last character rather than wherever the
    /// middle of the field happened to be.
    ///
    /// The keyboard is dismissed afterwards for a plain reason: it covers the
    /// button the test is about to press.
    private func typeEntryPath(_ path: String, into app: XCUIApplication) {
        let field = app.textFields["entryPathField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the entry path field never appeared")
        let existing = (field.value as? String) ?? ""

        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText(path)
        field.typeText("\n")

        XCTAssertEqual(field.value as? String, path)
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func entryCountAfterOpeningTheFolderSheet(_ app: XCUIApplication) -> String {
        let folderInfo = app.buttons["journalFolderInfo"]
        guard folderInfo.waitForExistence(timeout: 30) else { return "the journal never opened" }
        folderInfo.tap()

        let entryCount = app.staticTexts["journalEntryCount"]
        guard entryCount.waitForExistence(timeout: 5) else { return "no entry count was shown" }
        return entryCount.label
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

    /// Waits for an element to be labelled something. What a screen that is
    /// being rebuilt says while it is: the journal folder's name is absent
    /// for as long as the folder it names is being opened.
    private func expect(
        _ element: XCUIElement,
        toHaveLabel label: String,
        timeout: TimeInterval = 15
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, element.label != label {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(element.label, label)
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
