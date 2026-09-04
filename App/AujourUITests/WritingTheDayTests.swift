import UIKit
import XCTest

// What only a running app can show. Everything about *what* a folder of files
// means, and about which day is today's, lives in Core where `swift test`
// covers it fast; these are the acceptance-level claims of M1 — someone who
// has just installed Aujour is looking at a journal folder that exists and at
// today's Entry, and what they type into it is in a file afterwards.
final class WritingTheDayTests: AujourUITestCase {
    func testAFreshInstallFindsAJournalFolderWithoutBeingConfigured() throws {
        // Deliberately without a folder of its own: this is the claim about
        // an install nobody has configured, so it has to be the app's own
        // choice of folder that answers.
        let app = XCUIApplication()
        app.launch()

        // And so the app's own `UserDefaults` too, which is where it remembers
        // being welcomed — so whether the welcome is up depends on whether
        // this simulator has run the suite before. Answered if it is there,
        // and passed over if it is not: what is being claimed here is about
        // the folder on the other side of it.
        let skip = app.buttons["skipTheWelcome"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }

        // Asking iCloud for the app's container is slow the first time on a
        // device, so this is a wait rather than an assertion about a frame.
        let more = app.buttons["moreActions"]
        XCTAssertTrue(
            more.waitForExistence(timeout: 30),
            "the app did not settle on a journal folder — it is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
        more.tap()

        let settings = app.buttons["openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "the menu did not offer the settings")
        settings.tap()

        openTheJournalFolder(in: app)

        // And it can say where it is, the way the Files app would.
        let location = app.buttons["journalRootLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertEqual(theValue(of: location), aujoursOwnFolder)

        // A folder it could not read would have been a problem notice instead.
        XCTAssertFalse(app.staticTexts["journalFolderProblem"].exists)
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
        // behind, which the next launch is what proves — the calendar reads
        // the folder, and it says today is still unwritten.
        relaunch(app)
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 30))
        openTheMonth(app, showing: Date())
        let today = app.buttons["day-\(todaysEntryName())"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today was not on the calendar")
        XCTAssertEqual(today.value as? String, "Not written")
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

        // And the one control on the row that is not punctuation, which has a
        // test of its own below.
        XCTAssertTrue(app.buttons["insertPhoto"].isEnabled, "there was no way to a photo")

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

    /// The heading control, which is the one on the row that is a menu.
    ///
    /// Which characters a level writes, and that a heading asked for another
    /// level is re-levelled rather than taken away, is decided in Core and
    /// tested there against the text it rewrites; that the menu is built at
    /// the levels it names is `MarkdownAccessoryRowTests`, headless. What only
    /// a running app can show is the tap itself — that one press opens the
    /// menu over the keyboard rather than needing a press and hold, that
    /// picking a level reaches the line the cursor is on, and that picking
    /// another one leaves a heading behind rather than a plain line.
    func testTheHeadingControlLevelsTheLineAndThenRelevelsIt() throws {
        let app = launchApp()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        editor.tap()
        let headings = app.buttons["formatHeading"]
        XCTAssertTrue(headings.waitForExistence(timeout: 10), "the formatting row never appeared")

        editor.typeText("Sunday")

        // One tap opens it, because nobody presses and holds above a keyboard.
        headings.tap()
        tapTheOption(labelled: "Heading 2", in: app)
        expect(editor, toHaveValue: "## Sunday")

        // And the same control again, at another level: nobody presses
        // *Heading 1* on a Heading 2 meaning "not a heading", so the line is
        // re-levelled rather than left plain.
        headings.tap()
        tapTheOption(labelled: "Heading 1", in: app)
        expect(editor, toHaveValue: "# Sunday")
    }

    /// A photograph, from the row to the folder.
    ///
    /// Where the file goes, what it is called there and what the embed says
    /// are decided in Core and tested there against the paths they come out
    /// as; that the conversion and the write happen at all is
    /// `InsertedPhotographsTests`, headless. What only a running app can show
    /// is the rest: the control is live while a day is being written in, what
    /// it inserts lands where the cursor was, the writing carries on from
    /// under it, and what is in the file afterwards is the plain markdown
    /// anybody could have typed.
    ///
    /// The picker itself is the one part left out — it is another process's
    /// screen, and driving it would make this a test of that screen. So the
    /// suite says which photograph it means at launch and it goes in through
    /// the same door the picker's would (`UITestingJournal`).
    func testAPhotographIsInsertedAtTheCaretAndKeptAsAFile() throws {
        let app = launchApp(photograph: "png")

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()
        editor.typeText("Walked to the market.")

        let photo = app.buttons["insertPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the formatting row never appeared")
        photo.tap()

        // On a line of its own under the sentence, pointed at the file
        // relative to the day holding it.
        let embed = "![](\(todaysPhotograph()))"
        expect(editor, toHaveValue: "Walked to the market.\n" + embed)

        // And the cursor is after it, so the next sentence is the next
        // sentence rather than something wedged inside the link.
        editor.typeText("\nAnd back the long way.")
        expect(
            editor,
            toHaveValue: "Walked to the market.\n" + embed + "\nAnd back the long way."
        )

        // What is in the file is what was on screen — the write of the photo
        // itself is what the embed is evidence of, since nothing is inserted
        // until the file is in the folder.
        Thread.sleep(forTimeInterval: 4)
        relaunch(app)

        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(
            reopened.value as? String,
            "Walked to the market.\n" + embed + "\nAnd back the long way."
        )
    }

    /// The embed-syntax setting: the same photograph, written the way the
    /// user's vault is written.
    ///
    /// What a HEIC becomes on the way in is not asked here — it needs an
    /// ImageIO and no screen, which is `InsertedPhotographsTests`, in the same
    /// CI job on the same simulator.
    func testTheEmbedSyntaxSettingDecidesHowAPhotographIsWritten() throws {
        let app = launchApp(photograph: "jpeg")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openSettings(app)
        let example = app.staticTexts["embedSyntaxExample"]
        scrollTo(example, in: app)
        XCTAssertEqual(example.label, "![](\(todaysPhotograph(named: "jpg")))")

        let wiki = app.switches["embedSyntax"]
        scrollTo(wiki, in: app)
        flip(wiki)
        // The setting made concrete, on the day the user is in.
        expect(example, toHaveLabel: "![[\(todaysEntryName()).jpg]]")
        app.buttons["Done"].tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never came back")
        editor.tap()
        XCTAssertTrue(
            app.buttons["insertPhoto"].waitForExistence(timeout: 10),
            "the formatting row never appeared"
        )
        app.buttons["insertPhoto"].tap()

        // The file still goes where the Attachment Path Template says — the
        // setting decides only how the Entry points at it.
        expect(editor, toHaveValue: "![[\(todaysEntryName()).jpg]]")
    }

    /// The suggestions panel: the library asked for because a finger landed on
    /// the offer, the day's own photographs behind it, and one tap that writes
    /// one into the folder and points the Entry at it.
    ///
    /// The library itself is the part left out, for the reason the picker is:
    /// a simulator's is empty, and asking a real one would put a system alert
    /// from another process in the middle of a test. So the suite says which
    /// days the camera has something from and everything after that — the day
    /// query, the panel, the attachment pipeline — is the app's own code
    /// (`UITestingJournal`).
    func testTheDaysPhotographsAreOfferedAndOneTapInsertsOne() throws {
        let app = launchApp(
            photoLibrary: "\(todaysEntryName()) 09:15\n\(todaysEntryName()) 18:40",
            photoLibraryAccess: "undecided"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        // Nothing has been asked for yet, and nothing has been read: the
        // library permission is this panel's alone, and it is asked for
        // because somebody said to look.
        let offer = app.buttons["showPhotoSuggestions"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the panel never offered to look")
        XCTAssertFalse(
            app.staticTexts["photoSuggestions"].exists,
            "the day's photographs were read before anybody was asked"
        )
        offer.tap()

        let headline = app.staticTexts["photoSuggestions"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10), "the panel never filled in")
        XCTAssertEqual(headline.label, "2 photos from this day")

        editor.tap()
        editor.typeText("Walked to the market.")

        let photo = app.buttons["photoSuggestion0"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the strip had no photographs in it")
        photo.tap()

        // The same pipeline the picker's photograph goes through: under the
        // Attachment Path Template for this day, pointed at relatively, and on
        // a line of its own after the sentence the caret was in.
        let embed = "![](\(todaysPhotograph(named: "jpg")))"
        expect(editor, toHaveValue: "Walked to the market.\n" + embed)

        // And what is in the file is what was on screen — nothing is inserted
        // until the photograph is in the folder.
        Thread.sleep(forTimeInterval: 4)
        relaunch(app)

        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "Walked to the market.\n" + embed)
    }

    /// A day filled in later is offered *its* photographs, and today is not
    /// offered them — which is the whole of the panel being about the Journal
    /// Day rather than about now.
    func testADayFilledInLaterIsOfferedItsOwnPhotographs() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            contentTemplate: "# {{title}}\n",
            photoLibrary: entryName(for: yesterday)
        )
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        // Today's camera roll is empty, so today has no panel — even though
        // the library has a photograph in it.
        XCTAssertFalse(
            app.staticTexts["photoSuggestions"].waitForExistence(timeout: 3),
            "today was offered a photograph from another day"
        )

        openTheMonth(app, showing: yesterday)
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "yesterday was not on the calendar")
        cell.tap()

        let headline = app.staticTexts["photoSuggestions"]
        XCTAssertTrue(
            headline.waitForExistence(timeout: 15),
            "the day being written about was offered nothing"
        )
        XCTAssertEqual(headline.label, "1 photo from this day")
    }

    /// Saying no costs the panel and nothing else. The photo button above the
    /// keyboard goes through the system picker, which runs in a process of its
    /// own and needs no permission at all.
    ///
    /// The library has a photograph from today in it throughout, so what is
    /// being watched is the refusal and not an empty camera roll.
    func testARefusedLibraryLeavesNoPanelAndTheManualInsertWorking() throws {
        let app = launchApp(
            photograph: "png",
            photoLibrary: todaysEntryName(),
            photoLibraryAccess: "refuses"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        let offer = app.buttons["showPhotoSuggestions"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the panel never offered to look")
        offer.tap()

        // Absent, and silent with it: they answered the question that was put
        // to them, and nothing about a photo library belongs in front of
        // somebody who is writing.
        XCTAssertFalse(
            app.staticTexts["photoSuggestions"].waitForExistence(timeout: 3),
            "a refused library was read anyway"
        )
        // And it does not come back: the way past a refusal is Settings, not
        // an app that asks again every time the day is opened.
        XCTAssertFalse(offer.exists, "a library already refused was offered again")

        // The other door, which never needed the library at all.
        editor.tap()
        let photo = app.buttons["insertPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the formatting row never appeared")
        photo.tap()

        expect(editor, toHaveValue: "![](\(todaysPhotograph()))")
    }

    func testATemplateFilePickedAnywhereIsWhatTheNextDayStartsFrom() throws {
        // A template kept somewhere else entirely — not in the journal folder
        // — which is the case a file picker is needed for at all (ADR 0005).
        // Deliberately no template setting, so what puts one in force is the
        // app.
        let app = launchApp(templateToPick: "## Morning\n\n## Evening\n")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openSettings(app)
        openTheTemplate(in: app)
        app.buttons["contentTemplateFile"].tap()
        backToTheSettings(in: app)
        app.buttons["Done"].tap()

        // Today has not been written in, so today is what the file says.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "today never came back")
        expect(editor, toHaveValue: "## Morning\n\n## Evening\n")

        // And still the template on the next launch: the file is remembered by
        // a bookmark, which is what makes a file outside the folder reachable
        // at all after the app is relaunched.
        relaunch(app)
        expect(editor, toHaveValue: "## Morning\n\n## Evening\n")

        // Until it is asked for no template, which forgets the file and
        // nothing else: today goes back to the blank page it was.
        openSettings(app)
        openTheTemplate(in: app)
        let noTemplate = app.buttons["noContentTemplate"]
        scrollTo(noTemplate, in: app)
        noTemplate.tap()
        backToTheSettings(in: app)
        app.buttons["Done"].tap()
        expect(editor, toHaveValue: "")
    }

    func testTheRolloverHourChosenIsTheOneStillInForceAfterARelaunch() throws {
        let app = launchApp()
        openSettings(app)

        // Four in the morning: the night owl's rollover, and the hour the
        // decision log uses to explain what one is for. Named the way this
        // device's clock names it rather than spelled into the test — the app
        // runs in whatever region the simulator is set to, and so does the
        // runner.
        let fourInTheMorning = onTheClock(hour: 4)
        let hour = app.buttons["rolloverHour"]
        scrollTo(hour, in: app)
        hour.tap()
        tapTheOption(labelled: fourInTheMorning, in: app)

        // The row is the setting, said back: the sheet is a summary of the
        // journal, so an hour chosen is an hour the row is showing.
        expect(hour, toBeShowing: fourInTheMorning)

        relaunch(app)
        openSettings(app)
        let afterARelaunch = app.buttons["rolloverHour"]
        XCTAssertTrue(afterARelaunch.waitForExistence(timeout: 15), "settings never came back")
        // The end of the label rather than any of it: an hour that merely
        // appears in "Day starts at, 14:00" is not the hour it turns at.
        XCTAssertTrue(
            afterARelaunch.label.hasSuffix(", \(fourInTheMorning)"),
            "expected the day to still turn at \(fourInTheMorning), got \(afterARelaunch.label)"
        )
    }

    /// The reminder is off until somebody chooses a time, and what they choose
    /// is what this device goes on doing.
    ///
    /// Which nudges exist — one a day, none for a day already written in, the
    /// Rollover Hour respected — is decided in Core and tested there against a
    /// folder said rather than read. What only a running app can show is the
    /// setting itself: a fresh install with no reminder in it, any minute of
    /// the clock available to be chosen, a choice that survives a relaunch,
    /// and a switch that takes it away again.
    func testTheDailyReminderIsOffUntilATimeIsChosenAndStaysChosen() throws {
        let app = launchApp()
        openSettings(app)

        let reminder = app.switches["dailyReminder"]
        scrollTo(reminder, in: app)
        // Nothing on a fresh install: Aujour has never nudged anybody who did
        // not ask it to, so there is no reminder here to turn off.
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertFalse(
            app.datePickers["dailyReminderTime"].exists,
            "a reminder nobody has turned on was offering a time"
        )

        flip(reminder)

        // The evening it lands on — a starting point, not a default, since it
        // took a tap to get here at all.
        let time = app.datePickers["dailyReminderTime"]
        XCTAssertTrue(time.waitForExistence(timeout: 10), "no time was offered")
        XCTAssertEqual(
            theTimeShowing(on: time, in: app),
            onTheClock(hour: 21, minute: 0),
            "expected the evening to be offered"
        )
        // Moved to a minute nothing would have offered as an option, which is
        // the whole of what a clock face is for: the reminder is any time on
        // it and not a list of the sensible ones.
        setTheMinutes(of: time, to: 7, in: app)
        XCTAssertEqual(theTimeShowing(on: time, in: app), onTheClock(hour: 21, minute: 7))

        relaunch(app)
        openSettings(app)
        let afterARelaunch = app.datePickers["dailyReminderTime"]
        XCTAssertEqual(
            theTimeShowing(on: afterARelaunch, in: app),
            onTheClock(hour: 21, minute: 7),
            "expected the time chosen to still be in force"
        )

        // And off again, which takes the time with it: there is no reminder
        // set to a time and switched off, because the time is what a reminder
        // is.
        let stillOn = app.switches["dailyReminder"]
        scrollTo(stillOn, in: app)
        XCTAssertEqual(stillOn.value as? String, "1")
        flip(stillOn)
        XCTAssertFalse(
            app.datePickers["dailyReminderTime"].waitForExistence(timeout: 3),
            "a reminder that was turned off was still offering a time"
        )
    }
}
