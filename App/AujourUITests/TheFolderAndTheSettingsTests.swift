import UIKit
import XCTest

final class TheFolderAndTheSettingsTests: AujourUITestCase {

    // MARK: - Sending a day somewhere

    // The acceptance-level claim of exporting: both forms are on offer over a
    // day, and choosing one reaches the system share sheet. What is *in*
    // either file — the markdown byte for byte, the page with the marks left
    // off it — is drawn and read back headlessly in `SharedEntryTests` and
    // `EntryPaperTests`; what only a running app can show is the offer and
    // the sheet.
    func testADayIsOfferedAsAPDFAndAsPlainTextThroughTheShareSheet() throws {
        let app = launchApp(contentTemplate: "# {{title}}\n\nWalked to the market.\n")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        // Behind the bar's menu, with the other two things the app can do to
        // a journal that are not writing in it.
        fromTheMenu("shareEntry", in: app)

        XCTAssertTrue(
            app.buttons["PDF"].waitForExistence(timeout: 5),
            "the share sheet did not offer a PDF"
        )
        XCTAssertTrue(
            app.buttons["Plain Text"].exists,
            "the share sheet did not offer plain text"
        )

        // The day as a page, before it leaves: the sheet's whole reason for
        // being a sheet rather than a menu of two words. Asked for by
        // identifier whatever kind of element it lands as, since what is on
        // screen is a picture of a page and its accessibility is a label.
        let preview = app.descendants(matching: .any)
            .matching(identifier: "sharePreview")
            .firstMatch
        XCTAssertTrue(
            preview.waitForExistence(timeout: 20),
            "the share sheet showed no preview of the day"
        )

        app.buttons["Plain Text"].tap()
        app.buttons["shareEntryNow"].tap()

        // The system's own screen, over the file Aujour wrote. That it came
        // up at all is the claim here; *what* is in the file — the day's own
        // characters, named after the day — is proven byte for byte and
        // headlessly in `SharedEntryTests`, which is where a claim about a
        // file belongs.
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 20),
            "the share sheet never came up — the screen is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )

        // And the day is exactly where it was afterwards: an export is a copy
        // handed to something else, and nothing about it touches the Entry
        // (ADR 0001).
        dismissTheShareSheet(app)
        let stillThere = try XCTUnwrap(app.textViews["entryEditor"].value as? String)
        XCTAssertTrue(
            stillThere.contains("Walked to the market."),
            "sharing the day changed it: \(stillThere)"
        )
    }

    // "Works for any day, from history as well as today": the offer is on the
    // Entry's own screen, so a day reached from the calendar has it too.
    func testADayFilledInFromHistoryCanBeSentAsWell() throws {
        let app = launchApp(contentTemplate: "# {{title}}\n")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        let yesterday = try XCTUnwrap(dayBeforeToday())
        openTheMonth(app, showing: yesterday)

        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "yesterday was not on the calendar")
        cell.tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "yesterday's entry never opened")

        fromTheMenu("shareEntry", in: app)
        XCTAssertTrue(
            app.buttons["PDF"].waitForExistence(timeout: 5),
            "the share sheet did not offer a PDF for a day from history"
        )

        app.buttons["PDF"].tap()
        app.buttons["shareEntryNow"].tap()

        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 30),
            "the share sheet never came up for a day from history"
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

        // Where a journal nobody has moved lives — a step in from the sheet,
        // on the folder's own page.
        openSettings(app)
        openTheJournalFolder(in: app)
        let location = app.buttons["journalRootLocation"]
        expect(location, toBeShowing: aujoursOwnFolder)

        // Pointed at a folder of the user's own — the row opens the picker,
        // and launched with a folder to pick, the picker is the folder the
        // test named. The journal is that folder from now on.
        location.tap()
        expect(location, toBeShowing: vault)
        backToTheSettings(in: app)
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
        openSettings(app)
        openTheJournalFolder(in: app)
        expect(location, toBeShowing: vault)

        // And the way back: Aujour's own folder, with everything that was
        // written there still in it.
        app.buttons["useAujoursOwnFolder"].tap()
        expect(location, toBeShowing: aujoursOwnFolder)
        backToTheSettings(in: app)
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
            notice.label.contains(parkedName),
            "the notice did not name \(parkedName): " + notice.label
        )

        // And the one thing the app offers to do about it: show that file
        // where it lies. Not tapped — it leaves for the Files app, and what
        // is being proven here is that the way out is on screen and reachable
        // at all.
        let showIt = app.buttons["showParkedFileInFiles"]
        XCTAssertTrue(showIt.exists, "the notice offered no way to the file it named")
        XCTAssertEqual(showIt.label, "Show in Files")
        XCTAssertTrue(showIt.isHittable)

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

        openSettings(app)
        openTheEntryPath(in: app)
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

        // Both ways out are offered, and each says what it does. Leaving the
        // files where they are is a choice ADR 0002 gives the user, not a
        // way of backing out of one the screen had already made for them.
        XCTAssertEqual(app.buttons["moveEntries"].label, "Move Them")
        XCTAssertEqual(app.buttons["skipMigration"].label, "Leave Them Where They Are")

        app.buttons["moveEntries"].tap()
        let summary = app.staticTexts["migrationSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "the migration never finished")
        XCTAssertEqual(summary.label, "1 entry moved.")
        app.buttons["dismissMigrationSummary"].tap()

        // The same words, read from where the new template says — moved, not
        // lost.
        XCTAssertEqual(app.textFields["entryPathField"].value as? String, "[Journal]/YYYY-MM-DD")
        backToTheSettings(in: app)
        app.buttons["Done"].tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never reopened")
        expect(editor, toHaveValue: "Walked to the market.")

        // And the entry path outlives the launch, the way every other
        // journal-shaping setting does (ADR 0003) — which is the day still
        // being found under it from a cold start.
        relaunch(app)
        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        expect(reopened, toHaveValue: "Walked to the market.")
        openSettings(app)
        openTheEntryPath(in: app)
        XCTAssertEqual(app.textFields["entryPathField"].value as? String, "[Journal]/YYYY-MM-DD")
    }

    func testSkippingTheMigrationLeavesTheOldFilesWhereTheyAreAndUnsurfaced() throws {
        let app = launchApp(todaysEntry: "Walked to the market.")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openSettings(app)
        openTheEntryPath(in: app)
        typeEntryPath("[Journal]/YYYY-MM-DD", into: app)
        app.buttons["changeEntryPath"].tap()
        XCTAssertTrue(
            app.staticTexts["migrationPrompt"].waitForExistence(timeout: 15),
            "nothing offered to move the entries"
        )

        app.buttons["skipMigration"].tap()

        // The old file is still in the folder and is no longer an Entry, and
        // nothing anywhere surfaces what was left behind (ADR 0002).
        backToTheSettings(in: app)
        app.buttons["Done"].tap()

        // Today, under the new path, is a day nobody has written on.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never reopened")
        expect(editor, toHaveValue: "")

        // Not on the calendar either — a skipped migration orphans the old
        // files completely, which is the deal ADR 0002 makes.
        openTheMonth(app, showing: Date())
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

        openSettings(app)
        openTheEntryPath(in: app)
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
        backToTheSettings(in: app)
        app.buttons["Done"].tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never reopened")
        expect(editor, toHaveValue: "Written in Obsidian.")
    }

    func testAWordFindsTheDayItWasWrittenOnAndOpensIt() throws {
        let lastWeek = try XCTUnwrap(daysBeforeToday(7))
        let lastMonth = try XCTUnwrap(daysBeforeToday(30))
        let app = launchApp(
            entries: """
                \(entryName(for: lastWeek)) Walked to the market with Robin.
                \(entryName(for: lastMonth)) Rained all day, so I stayed in and read.
                """
        )

        openSearch(app)
        search(for: "market", in: app)

        // The day that says it, and only that day — a search that answered
        // with the whole journal would be no search at all.
        let result = app.buttons["searchResult-\(entryName(for: lastWeek))"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "the day was not found")
        XCTAssertFalse(
            app.buttons["searchResult-\(entryName(for: lastMonth))"].exists,
            "a day with none of the searched words in it was offered as a result"
        )
        // What the row shows is the day's own words, which is how somebody
        // knows it is the day they meant before opening it.
        XCTAssertEqual(result.value as? String, "Walked to the market with Robin.")

        result.tap()

        // Opening a result opens that day's Entry — the file, not a new one.
        //
        // Asked of every editor on screen rather than of one: search is a
        // sheet, so today's Entry is still in the tree underneath it and the
        // day just opened is the one on top of it.
        XCTAssertTrue(
            app.textViews["entryEditor"].firstMatch.waitForExistence(timeout: 10),
            "the day found never opened"
        )
        let onScreen = app.textViews.matching(identifier: "entryEditor")
            .allElementsBoundByIndex
            .compactMap { $0.value as? String }
        XCTAssertTrue(
            onScreen.contains { $0.contains("Walked to the market with Robin.") },
            "expected the day that was searched for, got: \(onScreen)"
        )
    }

    // The other half of what an empty search box is for: the queries already
    // made. Remembered when one leads somewhere rather than as it is typed,
    // and kept on the device rather than in the folder (ADR 0003) — so the
    // claim is that it is still there in the next launch.
    func testAQueryThatFoundADayIsOfferedBackTheNextTime() throws {
        let lastWeek = try XCTUnwrap(daysBeforeToday(7))
        let written = "\(entryName(for: lastWeek)) Walked to the market with Robin."
        let app = launchApp(entries: written)

        openSearch(app)
        search(for: "market", in: app)

        let result = app.buttons["searchResult-\(entryName(for: lastWeek))"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "the day was not found")
        result.tap()
        // The one on top: search is a sheet, so today's Entry is still in the
        // tree underneath it.
        XCTAssertTrue(
            app.textViews["entryEditor"].firstMatch.waitForExistence(timeout: 10),
            "the day found never opened"
        )

        app.terminate()
        let relaunched = launchApp(entries: written)
        openSearch(relaunched)

        let recent = relaunched.buttons["recentSearch-market"]
        XCTAssertTrue(
            recent.waitForExistence(timeout: 15),
            "an empty search box offered nothing back"
        )

        // And one of them is that search again, without typing it.
        recent.tap()
        XCTAssertTrue(
            relaunched.buttons["searchResult-\(entryName(for: lastWeek))"]
                .waitForExistence(timeout: 10),
            "tapping a recent query did not search for it"
        )
    }

    func testADayWrittenElsewhereIsFoundOnceTheFolderIsReadAgain() throws {
        let lastWeek = try XCTUnwrap(daysBeforeToday(7))
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let alreadyThere = "\(entryName(for: lastWeek)) Walked to the market with Robin."

        let app = launchApp(entries: alreadyThere)
        openSearch(app)
        search(for: "mountain", in: app)
        XCTAssertTrue(
            app.staticTexts["noSearchResults"].waitForExistence(timeout: 10),
            "a word nobody has written was found somewhere"
        )

        // A day arriving in the folder with Aujour not looking: written in
        // Obsidian, or come down from another device. Seeded at launch, which
        // is the only way a file appears in the folder without the app having
        // put it there.
        app.terminate()
        let relaunched = launchApp(
            entries: """
                \(alreadyThere)
                \(entryName(for: yesterday)) Climbed the mountain in the fog.
                """
        )

        openSearch(relaunched)
        search(for: "mountain", in: relaunched)

        // Found because the search screen read the folder again — not because
        // anything told Aujour the day was there.
        let result = relaunched.buttons["searchResult-\(entryName(for: yesterday))"]
        XCTAssertTrue(
            result.waitForExistence(timeout: 15),
            "a day written outside Aujour was not found after the folder was read again"
        )
        XCTAssertEqual(result.value as? String, "Climbed the mountain in the fog.")
    }

    func testTheDaysEventsAndRemindersAreSpawnedIntoTodaysEntry() throws {
        let app = launchApp(
            contentTemplate: "## Today\n{{events}}\n\n## To do\n{{reminders}}\n",
            events: "09:30 Standup\nBank holiday",
            reminders: "18:00 Buy bread"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        // The day, written into the Entry as plain markdown: a list of what
        // was on, and a task list of what to do — which is the file, and the
        // same file in Obsidian.
        let spawned = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(
            spawned.contains("- 09:30 Standup"),
            "the day's events were not spawned into the entry, got: \(spawned)"
        )
        XCTAssertTrue(
            spawned.contains("- Bank holiday"),
            "an all-day event should be written without an hour, got: \(spawned)"
        )
        XCTAssertTrue(
            spawned.contains("- [ ] 18:00 Buy bread"),
            "a reminder should arrive as a task, got: \(spawned)"
        )
    }

    func testADayWithNothingInItSpawnsWithoutBreakingTheTemplate() throws {
        // No calendar seeded at all — which is also what a refused permission
        // looks like from here: the placeholders render empty, and the entry
        // appears anyway.
        let app = launchApp(contentTemplate: "# {{title}}\n\n## Today\n{{events}}\n")

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        let spawned = try XCTUnwrap(editor.value as? String)
        XCTAssertEqual(spawned, "# \(todaysEntryName())\n\n## Today\n\n")
    }

    // MARK: - What the sheet is grouped by

    /// The sheet as the redesign made it: three groups by subject, in one
    /// order, and every row saying what it is set to.
    ///
    /// Asked by where each control sits and not only by reading the headings,
    /// because the headings are the easy half — a sheet can say "Files" over a
    /// group holding the daily reminder and pass every check that looked for
    /// the words.
    ///
    /// Every frame is read at one scroll position and none of them is scrolled
    /// to, which is what makes the comparison a comparison: the rows are laid
    /// out whether or not they are on screen, and a swipe between two readings
    /// would be measuring a position before it against a position after it.
    ///
    /// The half that would go unnoticed is the values. A sheet of four
    /// chevrons that named the settings and said nothing about them would look
    /// tidy and be a menu of doors — the point of grouping by subject is that
    /// the sheet is a summary of the journal, readable without opening
    /// anything.
    func testTheSheetIsGroupedBySubjectAndEveryRowSaysWhatItIsSetTo() throws {
        let app = launchApp()
        openSettings(app)

        let files = app.staticTexts["Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 10), "the sheet has no Files group")
        let entries = app.staticTexts["Entries"]
        XCTAssertTrue(entries.exists, "the sheet has no Entries group")
        XCTAssertLessThan(
            files.frame.minY, entries.frame.minY,
            "Entries comes before Files — the writing's own settings are above where it lives"
        )

        // Where the writing lives, in order, each row saying what it is set
        // to. Read off the end of the row's label, which is where a list puts
        // a value.
        //
        // Two comparisons rather than a range, which would trap on the very
        // inversion this is checking for.
        let inFiles: [(String, String)] = [
            ("openJournalFolder", aujoursOwnFolder),
            ("openEntryPath", "YYYY/MM/YYYY-MM-DD"),
            ("openPhotoPath", "[attachments]/YYYY/MM"),
            ("openContentTemplate", "None"),
        ]
        var previously = files.frame.minY
        for (identifier, value) in inFiles {
            let row = app.buttons[identifier]
            XCTAssertTrue(row.exists, "\(identifier) is not on the settings sheet at all")
            XCTAssertTrue(
                row.frame.minY > previously && row.frame.minY < entries.frame.minY,
                "\(identifier) is not under Files, in order — it is at \(row.frame.minY), and "
                    + "that group runs from \(previously) to \(entries.frame.minY)"
            )
            XCTAssertEqual(
                theValue(of: row), value,
                "\(identifier) is not saying what it is set to — it says \(row.label)"
            )
            previously = row.frame.minY
        }

        // What goes into an entry: the two data placeholders showing the token
        // the user would type, then the day's turn — which acts in place
        // rather than opening anything.
        let inEntries: [(String, XCUIElement, String)] = [
            ("the calendar", app.buttons["dataPlaceholder-events"], "{{events}}"),
            ("the reminders", app.buttons["dataPlaceholder-reminders"], "{{reminders}}"),
            ("the day's turn", app.buttons["rolloverHour"], onTheClock(hour: 0)),
        ]
        previously = entries.frame.minY
        for (what, row, value) in inEntries {
            XCTAssertTrue(row.exists, "\(what) is not on the settings sheet at all")
            XCTAssertGreaterThan(
                row.frame.minY, previously,
                "\(what) is not under Entries, in order — it is at \(row.frame.minY), and the "
                    + "row before it is at \(previously)"
            )
            XCTAssertEqual(
                theValue(of: row), value,
                "\(what) is not saying what it is set to — it says \(row.label)"
            )
            previously = row.frame.minY
        }

        // The last group is unnamed, so it is read by position alone — and on
        // the smallest phone it is below the fold, which is a `Form` and not a
        // stack: a row that has not been scrolled to has not been built and is
        // not there to be asked. So everything about it is read after the
        // scroll, against the row above it, and nothing measured before the
        // scroll is compared with anything measured after.
        let appearance = app.buttons["openHowItLooks"]
        scrollTo(appearance, in: app)

        let embeds = app.switches["embedSyntax"]
        XCTAssertTrue(embeds.exists, "the embed spelling is not on the sheet")
        XCTAssertLessThan(
            embeds.frame.minY, appearance.frame.minY,
            "the embed spelling is below the appearance, so it is not under Entries"
        )
        // And the one line that group is allowed: the embed as it would be
        // written into today.
        XCTAssertTrue(
            app.staticTexts["embedSyntaxExample"].exists,
            "the group never showed what an embed would come out as"
        )

        XCTAssertEqual(
            theValue(of: appearance), "Driftwood",
            "the appearance row is not saying which accent is in force — it says "
                + appearance.label
        )
        let reminder = app.switches["dailyReminder"]
        XCTAssertTrue(reminder.exists, "the daily reminder is not on the sheet")
        XCTAssertGreaterThan(
            reminder.frame.minY, appearance.frame.minY,
            "the daily reminder is above the appearance, so the last group is not in order"
        )

        // And nothing explains anything. The three lines the old sheet led
        // with — what travels, what stays, and which day the rollover hour
        // makes — are the ones a caption paragraph would come back as.
        for gone in ["journalSettingsSaying", "deviceSettingsSaying", "rolloverHourDay"] {
            XCTAssertFalse(
                app.staticTexts[gone].exists,
                "\(gone) is back on the sheet — the sheet explains itself again"
            )
        }
    }

    // MARK: - How the day's own data is written out

    /// The screen the redesign left undesigned longest: a row per data
    /// placeholder, each opening the fields that decide what it puts in the
    /// file.
    ///
    /// What each field *means* is Core's and proved there. What only a running
    /// app can show is the round trip — a marker typed into a settings field
    /// coming back out of the next day Aujour spawns, on a launch after the
    /// one it was typed on.
    func testTheCalendarsLinesAreWrittenTheWayTheSettingSays() throws {
        let app = launchApp(
            contentTemplate: "## Today\n{{events}}\n",
            events: "09:30 Standup"
        )
        openSettings(app)

        let events = app.buttons["dataPlaceholder-events"]
        scrollTo(events, in: app)
        events.tap()

        XCTAssertTrue(
            app.staticTexts["wholeDayExample"].waitForExistence(timeout: 10),
            "the page never showed what a day would read like"
        )
        // The one field this placeholder has no business offering, for the
        // reason `DataPlaceholder.itemsCanBeDone` gives.
        XCTAssertFalse(
            app.textFields["donePrefixField"].exists,
            "{{events}} was offered a done marker, and an event is never done"
        )

        replaceTheText(in: "linePrefixField", with: "* ", in: app)
        // The worked example follows the field as it is typed, before anything
        // has been changed — which is the whole reason the field has one.
        let asItWouldRead = app.staticTexts["linePrefixExample"]
        scrollTo(asItWouldRead, in: app)
        XCTAssertTrue(
            asItWouldRead.label.hasPrefix("* "),
            "the example did not follow the field — it reads \(asItWouldRead.label)"
        )

        replaceTheText(in: "timeFormatField", with: "[at] HH:mm", in: app)

        let change = app.buttons["changeHowItIsWritten"]
        scrollTo(change, in: app)
        change.tap()

        // A launch later, because that is the claim: the setting travels
        // through the synced seam, and the next day spawned is written by it.
        relaunch(app)

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never came back")
        let spawned = try XCTUnwrap(editor.value as? String)
        XCTAssertEqual(spawned, "## Today\n* at 09:30 Standup\n")
    }

    func testTheRemindersHaveADoneMarkerAndSayWhenTheDayHeldNothing() throws {
        // No reminders seeded, which is the day the empty text is for: a
        // heading with nothing under it, unless the user asked to be told.
        let app = launchApp(contentTemplate: "## To do\n{{reminders}}\n")
        openSettings(app)

        let reminders = app.buttons["dataPlaceholder-reminders"]
        scrollTo(reminders, in: app)
        reminders.tap()

        // The field {{events}} does not get.
        XCTAssertTrue(
            app.textFields["donePrefixField"].waitForExistence(timeout: 10),
            "{{reminders}} was not offered a done marker, and a reminder gets ticked"
        )

        replaceTheText(in: "whenEmptyField", with: "Nothing on the list.", in: app)
        let onAnEmptyDay = app.staticTexts["whenEmptyExample"]
        scrollTo(onAnEmptyDay, in: app)
        XCTAssertEqual(onAnEmptyDay.label, "Nothing on the list.")

        let change = app.buttons["changeHowItIsWritten"]
        scrollTo(change, in: app)
        change.tap()

        relaunch(app)

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never came back")
        XCTAssertEqual(editor.value as? String, "## To do\nNothing on the list.\n")
    }
}
