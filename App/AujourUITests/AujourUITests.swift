import UIKit
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

    /// What the Files app calls Aujour's own on-device folder *here*. The app
    /// names it after the device it is running on, so spelling "iPhone" into
    /// the expectation made the suite assert that the iPad build was wrong.
    /// Read the same way the app reads it (`UIDevice.current.model`) — the
    /// runner is an app on the same device.
    private var aujoursOwnFolder: String { "On My \(UIDevice.current.model) › Aujour" }

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

        // And so the app's own `UserDefaults` too, which is where it remembers
        // being welcomed — so whether the welcome is up depends on whether
        // this simulator has run the suite before. Answered if it is there,
        // and passed over if it is not: what is being claimed here is about
        // the folder on the other side of it.
        let skip = app.buttons["skipTheWelcome"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }

        // Asking iCloud for the app's container is slow the first time on a
        // device, so this is a wait rather than an assertion about a frame.
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 30),
            "the app did not settle on a journal folder — it is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
        settings.tap()

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
        XCTAssertEqual(entryCountFromTheSettingsSheet(app), "0 entries")
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
        XCTAssertEqual(entryCountFromTheSettingsSheet(app), "1 entry")
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
        XCTAssertEqual(entryCountFromTheSettingsSheet(app), "1 entry")
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
        XCTAssertEqual(entryCountFromTheSettingsSheet(app), "1 entry")
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

        let wiki = app.buttons["Wiki-style"]
        scrollTo(wiki, in: app)
        wiki.tap()
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
        let chooseTemplate = app.buttons["contentTemplateFile"]
        scrollTo(chooseTemplate, in: app)
        chooseTemplate.tap()
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
        let noTemplate = app.buttons["noContentTemplate"]
        scrollTo(noTemplate, in: app)
        noTemplate.tap()
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

        // The setting said as the day it makes, which is what it is for.
        XCTAssertTrue(
            app.staticTexts["rolloverHourDay"].waitForExistence(timeout: 10),
            "the day being written was never shown"
        )

        relaunch(app)
        openSettings(app)
        let afterARelaunch = app.buttons["rolloverHour"]
        XCTAssertTrue(afterARelaunch.waitForExistence(timeout: 15), "settings never came back")
        // The end of the label rather than any of it: an hour that merely
        // appears in "When the day turns, 14:00" is not the hour it turns at.
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
    /// setting itself: a fresh install with no reminder in it, a time chosen
    /// that survives a relaunch, and a switch that takes it away again.
    func testTheDailyReminderIsOffUntilATimeIsChosenAndStaysChosen() throws {
        let app = launchApp()
        openSettings(app)

        let reminder = app.switches["dailyReminder"]
        scrollTo(reminder, in: app)
        // Nothing on a fresh install: Aujour has never nudged anybody who did
        // not ask it to, so there is no reminder here to turn off.
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertFalse(
            app.buttons["dailyReminderTime"].exists,
            "a reminder nobody has turned on was offering a time"
        )

        reminder.tap()

        // The evening it lands on — a starting point, not a default, since it
        // took a tap to get here at all.
        let time = app.buttons["dailyReminderTime"]
        XCTAssertTrue(time.waitForExistence(timeout: 10), "no time was offered")
        XCTAssertTrue(
            time.label.hasSuffix(", \(onTheClock(hour: 21, minute: 0))"),
            "expected the evening to be offered, got \(time.label)"
        )
        // And it is booked, not merely written down: the line underneath is
        // the nudge the app has actually put in front of the device.
        XCTAssertTrue(
            app.staticTexts["nextDailyReminder"].waitForExistence(timeout: 10),
            "nothing was said about when the next reminder would arrive"
        )

        // Changed to the half hour beside it, which is the setting being a
        // setting rather than a switch.
        scrollTo(time, in: app)
        time.tap()
        tapTheOption(labelled: onTheClock(hour: 21, minute: 30), in: app)

        relaunch(app)
        openSettings(app)
        let afterARelaunch = app.buttons["dailyReminderTime"]
        scrollTo(afterARelaunch, in: app)
        XCTAssertTrue(
            afterARelaunch.label.hasSuffix(", \(onTheClock(hour: 21, minute: 30))"),
            "expected the time chosen to still be in force, got \(afterARelaunch.label)"
        )

        // And off again, which takes the time with it: there is no reminder
        // set to a time and switched off, because the time is what a reminder
        // is.
        let stillOn = app.switches["dailyReminder"]
        scrollTo(stillOn, in: app)
        XCTAssertEqual(stillOn.value as? String, "1")
        stillOn.tap()
        XCTAssertFalse(
            app.buttons["dailyReminderTime"].waitForExistence(timeout: 3),
            "a reminder that was turned off was still offering a time"
        )
    }

    /// The first thirty seconds of an App Store product: three pages that say
    /// what this is, where the words will be and what Aujour would ever do
    /// while nobody is looking — and then an app with today's page open in it.
    ///
    /// Which page is on screen and what the offer means are decided in Core and
    /// tested there; that the journal is open behind the cover is
    /// `WelcomeWiringTests`, over a real folder. What only a running app can
    /// show is the run itself: somebody who has answered nothing but "not now"
    /// is typing into their journal a moment later, the reminder they declined
    /// is off, and the welcome does not come back the next morning.
    func testTheFirstRunSaysHelloAndLeavesTheAppReadyToWriteIn() throws {
        let app = launchApp(welcome: true)

        let whatThisIs = app.staticTexts["welcomeWhatThisIs"]
        XCTAssertTrue(whatThisIs.waitForExistence(timeout: 30), "the welcome never appeared")
        // And the app is behind it, not waiting for it: nothing on this page
        // has to be answered for a folder to have been found.
        XCTAssertFalse(app.textViews["entryEditor"].isHittable)

        app.buttons["continueTheWelcome"].tap()

        // The second page is this install rather than the app: the folder
        // Aujour found for itself, named the way the Files app names it.
        let whereYourWordsGo = app.staticTexts["welcomeWhereYourWordsGo"]
        XCTAssertTrue(whereYourWordsGo.waitForExistence(timeout: 30))
        expect(whereYourWordsGo, toHaveLabel: aujoursOwnFolder)

        app.buttons["continueTheWelcome"].tap()

        let theReminder = app.staticTexts["welcomeTheDailyReminder"]
        XCTAssertTrue(theReminder.waitForExistence(timeout: 10), "the reminder was never offered")
        // Offered, and skippable — which is the whole of what "offered" means
        // here. Declining is a button on the page and not a thing to go
        // looking for.
        app.buttons["skipTheReminder"].tap()

        // And straight into the day: no folder chosen, no template picked,
        // nothing configured.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()
        editor.typeText("Walked to the market.")
        Thread.sleep(forTimeInterval: 4)

        // Skipped means off, and not "on at some default hour": Aujour has
        // never nudged anybody who did not ask it to.
        openSettings(app)
        expect(app.staticTexts["journalEntryCount"], toHaveLabel: "1 entry")
        let reminder = app.switches["dailyReminder"]
        scrollTo(reminder, in: app)
        XCTAssertEqual(reminder.value as? String, "0")

        relaunch(app)

        // A welcome is a thing that happens once. The second launch is the
        // app, and the words typed into the first one are still in it.
        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "Walked to the market.")
        XCTAssertFalse(
            app.staticTexts["welcomeWhatThisIs"].exists,
            "the welcome came back for a device that had already been through it"
        )
    }

    /// The other answer to the offer: a time taken up on the last page is the
    /// reminder the app has, and the one the journal sheet is showing a moment
    /// later.
    func testATimeTakenUpInTheWelcomeIsTheReminderTheAppHas() throws {
        let app = launchApp(welcome: true)

        XCTAssertTrue(
            app.staticTexts["welcomeWhatThisIs"].waitForExistence(timeout: 30),
            "the welcome never appeared"
        )
        app.buttons["continueTheWelcome"].tap()
        XCTAssertTrue(app.staticTexts["welcomeWhereYourWordsGo"].waitForExistence(timeout: 30))
        app.buttons["continueTheWelcome"].tap()

        // The evening it opens on, changed to an hour earlier — the offer is a
        // time to pick and not a switch to flick.
        //
        // An hour either side rather than the other end of the clock: a menu
        // of forty-eight half hours opens scrolled to the one that is
        // selected, and only the ones near it are on screen to be tapped.
        let time = app.buttons["welcomeReminderTime"]
        XCTAssertTrue(time.waitForExistence(timeout: 10), "no time was offered")
        time.tap()
        tapTheOption(labelled: onTheClock(hour: 20, minute: 0), in: app)

        let takeItUp = app.buttons["takeTheReminderUp"]
        XCTAssertTrue(
            takeItUp.label.hasSuffix(onTheClock(hour: 20, minute: 0)),
            "the button did not say the time it would set, it said \(takeItUp.label)"
        )
        takeItUp.tap()

        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        // The same reminder, seen from the other end of the app: one setting,
        // set in the welcome and shown on the sheet.
        openSettings(app)
        let reminder = app.switches["dailyReminder"]
        scrollTo(reminder, in: app)
        XCTAssertEqual(reminder.value as? String, "1")
        let chosen = app.buttons["dailyReminderTime"]
        scrollTo(chosen, in: app)
        XCTAssertTrue(
            chosen.label.hasSuffix(", \(onTheClock(hour: 20, minute: 0))"),
            "expected the time taken up in the welcome, got \(chosen.label)"
        )
    }

    /// The first screen anybody ever sees, seen by the reader who has turned
    /// the system's text size all the way up.
    ///
    /// The welcome is the one screen in Aujour nobody chose to be on, so it is
    /// also the one where a reader who cannot read it has no way past — and
    /// the identity put three pages of Newsreader on it. Two launches and not
    /// one, because a size only means something against another size: a page
    /// that ignored Dynamic Type entirely would pass every "is it on screen"
    /// check ever written.
    ///
    /// It ends by leaving, at that size, through the offer's own "Not now" —
    /// which is the other half of the claim. A welcome that held together and
    /// could not be got out of would be a worse screen than one that did not.
    func testTheWelcomeHoldsTogetherAtTheLargestTextSize() throws {
        let atTheFactorySetting = launchApp(welcome: true)
        let ordinary = atTheFactorySetting.staticTexts["welcomeWhatThisIs"]
        XCTAssertTrue(ordinary.waitForExistence(timeout: 30), "the welcome never appeared")
        let ordinaryHeight = ordinary.frame.height
        atTheFactorySetting.terminate()

        let app = launchApp(textSize: "UICTContentSizeCategoryAccessibilityXXXL", welcome: true)
        let turnedUp = app.staticTexts["welcomeWhatThisIs"]
        XCTAssertTrue(turnedUp.waitForExistence(timeout: 30), "the welcome never appeared")
        XCTAssertGreaterThan(
            turnedUp.frame.height, ordinaryHeight,
            "the welcome's title did not grow with the system text size — it was "
                + "\(ordinaryHeight) points tall and is now \(turnedUp.frame.height)"
        )

        // Every one of the three, because they are three different pages and
        // only one of them is the one that was designed first: the second
        // holds a folder named after this device and the third holds a picker.
        let page = app.scrollViews["welcomePage"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the welcome has no page to scroll")
        assertTheLayoutHolds(on: page)

        app.buttons["continueTheWelcome"].tap()
        XCTAssertTrue(app.staticTexts["welcomeWhereYourWordsGo"].waitForExistence(timeout: 30))
        assertTheLayoutHolds(on: page)

        app.buttons["continueTheWelcome"].tap()
        XCTAssertTrue(app.staticTexts["welcomeTheDailyReminder"].waitForExistence(timeout: 10))
        assertTheLayoutHolds(on: page)

        // The ways on sit under the pages rather than in them, so the page's
        // own check does not reach them — and they are the half likeliest to
        // come apart, since a capsule with "Remind me at 9:00 PM" written
        // across it is the widest thing on the screen at this size.
        let screen = app.windows.firstMatch.frame
        for identifier in ["takeTheReminderUp", "skipTheReminder", "goBackAPage"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) was not on the last page")
            XCTAssertTrue(
                button.frame.minX >= screen.minX - 1 && button.frame.maxX <= screen.maxX + 1,
                "\(identifier) is at \(button.frame), off a screen \(screen) wide"
            )
        }

        app.buttons["skipTheReminder"].tap()
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "the welcome could not be left at the largest text size"
        )
    }

    /// A journal with nothing in it yet, on the three screens that would
    /// otherwise be blank.
    ///
    /// Which of the ways a screen can be empty this is — nothing written,
    /// nothing read yet, or a folder that would not answer — is decided in
    /// Core and tested there against folders that are told what to say. What
    /// only a running app can show is that the sentences are on the screens: a
    /// first day that says what to do with itself, a calendar that reads as a
    /// beginning rather than a grid of numbers, and a search box that does not
    /// tell somebody their query was not found in a journal they have not
    /// written yet.
    ///
    /// And that they stop. A beginning is the one empty grid worth words,
    /// because the grid is the way in and nobody who has just installed the
    /// app knows that; every other empty month is a gap the grid states for
    /// itself.
    func testAFreshJournalSaysSoOnEveryScreenWithNothingToShow() throws {
        let app = launchApp()

        // Today's page, with no Content Template pointed at it: the one screen
        // in the app that is genuinely a blank page on day one.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        // The prompt is drawn only over an Entry with no characters in it, so
        // its being here is also the claim that a journal with no Content
        // Template pointed at it starts the day blank.
        XCTAssertTrue(
            app.staticTexts["aBlankPage"].waitForExistence(timeout: 5),
            "a blank first day said nothing at all"
        )

        openTheMonth(app, showing: Date())
        XCTAssertTrue(
            app.staticTexts["aJournalNobodyHasWrittenIn"].waitForExistence(timeout: 15),
            "a month with no marks on it was left as a grid of numbers"
        )
        shutTheDatePill(app)

        openSearch(app)
        XCTAssertTrue(
            app.staticTexts["nothingToSearchYet"].waitForExistence(timeout: 15),
            "a search over a journal with nothing in it said nothing about that"
        )
        goBack(app)

        // One day written, and every one of those sentences stops being true.
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText("Walked to the market.")
        XCTAssertTrue(
            app.staticTexts["aBlankPage"].waitForNonExistence(timeout: 5),
            "the prompt was still over a page that had been written on"
        )
        Thread.sleep(forTimeInterval: 4)

        openTheMonth(app, showing: Date())
        expect(app.buttons["day-\(todaysEntryName())"], toHaveValue: "Written")
        XCTAssertFalse(
            app.staticTexts["aJournalNobodyHasWrittenIn"].exists,
            "a journal with a day in it was still being called empty"
        )

        // And a month it does not reach into says nothing at all. It is an
        // ordinary gap, which the grid states by having no marks on it — a
        // line underneath explaining that next month was quiet would be the
        // app narrating what the reader is looking at, and calling it a
        // journal nobody has written in would be the app forgetting today.
        app.buttons["pillNextMonth"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "identifier == %@", "aJournalNobodyHasWrittenIn")
            ).count == 0,
            "an empty month in a journal with a past was called a journal with nothing in it"
        )
    }

    /// An interactive placeholder is a question the file itself carries: it
    /// is a literal `{{mood}}` in the folder until somebody answers it, and a
    /// widget every time Aujour has the day open.
    ///
    /// Which stretches are one, and what answering writes, is decided in Core
    /// and tested there against the text; that the widget takes a widget's
    /// room and that a tap on it asks the question is
    /// `PlaceholderWidgetTests`, headless. What only a running app can show is
    /// the round trip: a token that was never answered is still literal text
    /// in the file after the app has closed, another tool has edited the day,
    /// and Aujour has opened it again — and it is a widget once more, while
    /// the one that *was* answered is plain markdown that nothing in the day
    /// remembers was ever a question.
    func testAnUnansweredPlaceholderSurvivesAndAnsweringOneWritesPlainText() throws {
        let app = launchApp(contentTemplate: "{{mood}}\n{{location}}\n")

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        // The tokens are the text, character for character: what the editor
        // draws over them is drawn over them, and every other tool sees this.
        XCTAssertEqual(editor.value as? String, "{{mood}}\n{{location}}\n")

        // The first line's widget, aimed at by coordinate for the reason a box
        // is: it is a drawing rather than a view, and nothing was added to the
        // text to find either (ADR 0001). In points from the corner rather
        // than as a fraction of the editor, whose height is whatever the
        // keyboard has left of the screen.
        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()

        // {{mood}} is rated rather than typed: five marks, and the one pressed
        // is the whole answer. What lands in the file is a sentence, which is
        // the only thing the folder ends up holding.
        let fourOutOfFive = app.buttons["moodRating4"]
        XCTAssertTrue(
            fourOutOfFive.waitForExistence(timeout: 10), "the widget never asked anything"
        )
        fourOutOfFive.tap()

        expect(editor, toHaveValue: "Today's mood: 4/5\n{{location}}\n")

        Thread.sleep(forTimeInterval: 4)

        // And somebody else edits the day while Aujour is closed — Obsidian in
        // the same vault, or another device's copy arriving. The token it did
        // not answer is literal text to every one of them, so it comes back
        // untouched with a line of theirs after it.
        let elsewhere = "Today's mood: 4/5\n{{location}}\n\nWrote this in Obsidian.\n"
        app.launchEnvironment["AUJOUR_UITEST_TODAYS_ENTRY"] = elsewhere
        relaunch(app)

        // Through a real file, written by the app, edited by another tool and
        // read back: the answer is plain markdown, and the question nobody
        // answered is still its own twelve characters.
        let reopened = app.textViews["entryEditor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        expect(reopened, toHaveValue: elsewhere)

        // And it is a widget again, from the text alone — a second line down,
        // where the token that survived the round trip stands.
        reopened.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 45))
            .tap()
        XCTAssertTrue(
            app.textFields["placeholderAnswerField"].waitForExistence(timeout: 10),
            "the unanswered placeholder did not come back as a widget"
        )

        // Cancelling writes nothing at all, which is what leaves the token
        // where it stands for the next time the day is opened.
        app.buttons["cancelPlaceholder"].tap()
        expect(reopened, toHaveValue: elsewhere)

    }

    /// The `{{location}}` widget's own half: the device is asked where it is,
    /// the place it names is what the widget offers, and a different one is a
    /// tap away in the list under it.
    ///
    /// Which places those are, and when there are none to offer, is decided in
    /// Core and tested there against places that are said rather than found.
    /// What only a running app can show is the round trip through the file:
    /// the offer confirmed with one tap, a different place chosen from the
    /// picker, and both landing in the day as plain markdown that nothing
    /// remembers was ever a question.
    func testTheLocationWidgetOffersAPlaceAndAPickerForADifferentOne() throws {
        let app = launchApp(
            contentTemplate: "{{location}}\n{{location}}\n",
            places: "Cafe de Flore | Boulevard Saint-Germain\nLes Deux Magots | Place Saint-Germain",
            placesAccess: "allowed"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        XCTAssertEqual(editor.value as? String, "{{location}}\n{{location}}\n")

        // The second line's widget first, and the first line's after — because
        // answering one takes a widget's height out of the line it stood on,
        // and everything below it moves up. Widgets are drawings rather than
        // views, aimed at by coordinate like every other one, so the way to
        // tap two of them is bottom up.
        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 45))
            .tap()

        // Changed rather than confirmed: the picker is the places around, and
        // tapping one puts it where the offer was.
        let different = app.buttons["nearbyPlace.Les Deux Magots"]
        XCTAssertTrue(
            different.waitForExistence(timeout: 10),
            "the picker never offered a different place"
        )
        different.tap()
        expect(app.textFields["placeholderAnswerField"], toHaveValue: "Les Deux Magots")
        app.buttons["answerPlaceholder"].tap()
        expect(editor, toHaveValue: "{{location}}\nLes Deux Magots\n")

        // And the one above it is simply confirmed: the widget asked the
        // device where it was, and the nearest place it named is already in
        // the field.
        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()

        let answer = app.textFields["placeholderAnswerField"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10), "the widget never asked anything")
        expect(answer, toHaveValue: "Cafe de Flore")
        app.buttons["answerPlaceholder"].tap()

        // Plain place text, both of them, in a file every other tool reads as
        // two lines somebody typed.
        expect(editor, toHaveValue: "Cafe de Flore\nLes Deux Magots\n")
    }

    /// Opening the sheet asks the device nothing.
    ///
    /// A `{{location}}` token in somebody's template must not mean a system
    /// permission alert the first time they tap a word in their own sentence.
    /// So the sheet offers to look, the looking happens because they said to,
    /// and only then is there a place in the field.
    func testTheLocationWidgetOffersToLookBeforeItAsksAnything() throws {
        let app = launchApp(
            contentTemplate: "{{location}}\n",
            places: "Cafe de Flore | Boulevard Saint-Germain",
            placesAccess: "undecided"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()

        // Nothing found and nothing offered: the device has not been asked.
        let look = app.buttons["findMyPlace"]
        XCTAssertTrue(look.waitForExistence(timeout: 10), "the widget never offered to look")
        XCTAssertNotEqual(
            app.textFields["placeholderAnswerField"].value as? String,
            "Cafe de Flore",
            "a place was offered before anybody was asked for the permission"
        )

        // And now they said to look.
        look.tap()
        expect(app.textFields["placeholderAnswerField"], toHaveValue: "Cafe de Flore")
        app.buttons["answerPlaceholder"].tap()

        expect(editor, toHaveValue: "Cafe de Flore\n")
    }

    /// A device that will not say where it is costs the offer and nothing
    /// else.
    ///
    /// The acceptance criterion, and the thing a permission-shaped feature
    /// most often gets wrong: no crash, no alert, no notice in front of
    /// somebody who is writing — and above all, a question that is still
    /// answerable. The token stays exactly where it stood until they answer
    /// it, and typing the place is how they do.
    func testALocationWidgetOnADeviceThatWillNotSayIsStillAnswered() throws {
        let app = launchApp(
            contentTemplate: "{{location}}\n",
            // Places to offer, and a refusal that means none of them is.
            places: "Cafe de Flore | Boulevard Saint-Germain",
            placesAccess: "refused"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        XCTAssertEqual(editor.value as? String, "{{location}}\n")

        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()

        let answer = app.textFields["placeholderAnswerField"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10), "the widget never asked anything")
        // Nothing offered, and nothing asked for either: somebody who said no
        // is not asked again by a widget. Said as "not the seeded place"
        // rather than "empty", because an empty field answers with its own
        // prompt.
        XCTAssertNotEqual(answer.value as? String, "Cafe de Flore")
        XCTAssertFalse(
            app.buttons["findMyPlace"].exists,
            "a refused device was offered to be looked at again"
        )
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "nearbyPlace.")
            ).count,
            0,
            "a refused device offered places anyway"
        )

        // Cancelling writes nothing at all, so the token is still the question
        // it was — which is the second half of degrading gracefully.
        app.buttons["cancelPlaceholder"].tap()
        expect(editor, toHaveValue: "{{location}}\n")

        // And it is answered by typing, exactly as it would have been if there
        // had never been a device to ask.
        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()
        let typed = app.textFields["placeholderAnswerField"]
        XCTAssertTrue(typed.waitForExistence(timeout: 10), "the widget never came back")
        typed.tap()
        typed.typeText("The kitchen table")
        app.buttons["answerPlaceholder"].tap()

        expect(editor, toHaveValue: "The kitchen table\n")
    }

    /// A day filled in later is offered the places *its own* photographs were
    /// taken, ahead of the street the phone happens to be standing in now.
    ///
    /// The whole of what this issue is about, and the round trip only a
    /// running app can show: yesterday's pictures read for the positions they
    /// carry, the positions gathered and named, the two sources drawn under
    /// their own headings, the name landing in the field, and plain markdown
    /// in the file afterwards. Which places come out of which positions is
    /// decided in Core and tested there against a library and a map that are
    /// said rather than read.
    func testADayFilledInLaterIsOfferedThePlacesItsOwnPhotographsWereTakenIn() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            contentTemplate: "{{location}}\n",
            // Four pictures of one lunch, which is one place and not four.
            photoLibrary: """
                \(entryName(for: yesterday)) 11:04 @ 48.85419,2.33262
                \(entryName(for: yesterday)) 11:20 @ 48.85421,2.33266
                \(entryName(for: yesterday)) 11:35 @ 48.85417,2.33259
                \(entryName(for: yesterday)) 12:02 @ 48.85420,2.33263
                """,
            // Where the phone is standing today, which for yesterday's entry
            // is the wrong answer however confidently it is offered.
            places: "Gare du Nord | Paris",
            placesAccess: "allowed",
            placesAt: "48.85419,2.33262 | Cafe de Flore | Boulevard Saint-Germain"
        )
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openTheMonth(app, showing: yesterday)
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "yesterday was not on the calendar")
        cell.tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "yesterday's entry never appeared")
        XCTAssertEqual(editor.value as? String, "{{location}}\n")

        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()

        // Yesterday's café, worked out from yesterday's photographs — and the
        // one the phone is standing in today behind it rather than in front.
        let photographed = app.buttons["nearbyPlace.Cafe de Flore"]
        XCTAssertTrue(
            photographed.waitForExistence(timeout: 20),
            "the day's own photographs were not offered as a place"
        )
        XCTAssertTrue(
            app.buttons["nearbyPlace.Gare du Nord"].exists,
            "the live fix stopped being offered at all"
        )

        // Four photographs of one café is one row, not four.
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier == %@", "nearbyPlace.Cafe de Flore")
            ).count,
            1,
            "the same place was offered once per photograph"
        )

        // Each under its own heading, so somebody can see which of the two
        // ways a suggestion was arrived at.
        XCTAssertTrue(
            app.staticTexts["From photos"].exists,
            "the day's own places were not drawn under their own heading"
        )
        XCTAssertTrue(
            app.staticTexts["Near you"].exists,
            "the live fix was not drawn under its own heading"
        )

        // Already in the field, because it is the offer: the day's own place
        // leads for a day that is not today.
        expect(app.textFields["placeholderAnswerField"], toHaveValue: "Cafe de Flore")

        app.buttons["answerPlaceholder"].tap()

        // Plain place text, exactly as confirming a nearby place writes it —
        // nothing in the file remembers this was ever a question, and nothing
        // of the photograph it was worked out from comes along with it.
        expect(editor, toHaveValue: "Cafe de Flore\n")
    }

    /// Refusing one of the two permissions does not refuse the other.
    ///
    /// A device that will not say where it is still has the day's own
    /// photographs, and naming the position one of them carries is a question
    /// about the map rather than about this device — so the offer survives a
    /// refused location, which is half the reason it rides both.
    func testARefusedDeviceIsStillOfferedThePlacesItsPhotographsWereTakenIn() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            contentTemplate: "{{location}}\n",
            photoLibrary: "\(entryName(for: yesterday)) 11:04 @ 48.85419,2.33262",
            places: "Gare du Nord | Paris",
            placesAccess: "refused",
            placesAt: "48.85419,2.33262 | Cafe de Flore | Boulevard Saint-Germain"
        )
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openTheMonth(app, showing: yesterday)
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "yesterday was not on the calendar")
        cell.tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "yesterday's entry never appeared")

        editor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 24, dy: 23))
            .tap()

        XCTAssertTrue(
            app.buttons["nearbyPlace.Cafe de Flore"].waitForExistence(timeout: 20),
            "a refused device lost the places its own photographs were taken in"
        )
        XCTAssertFalse(
            app.buttons["nearbyPlace.Gare du Nord"].exists,
            "a refused device was read anyway"
        )
    }

    func testAPastDayIsFilledInFromTheCalendar() throws {
        let app = launchApp(contentTemplate: "# {{title}}\n")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        let yesterday = try XCTUnwrap(dayBeforeToday())
        openTheMonth(app, showing: yesterday)

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

        // The indicator follows the file: the day was written on, so it is
        // marked, and it was marked by re-reading the folder. Opened again
        // rather than gone back to — the day was opened in place, so there is
        // no screen between here and it.
        openTheMonth(app, showing: yesterday)
        expect(cell, toHaveValue: "Written")

        // And it is all in a file — which the next launch, with nothing kept
        // from this one, is what proves.
        relaunch(app)
        openTheMonth(app, showing: yesterday)
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

    // MARK: - The date pill

    // The header on iPhone, and the spine of the app: the day being written,
    // the week around it and the whole month, in one container that grows.
    //
    // What is asked here is what only a running app can show — that a tap and
    // a drag both move it, that a day picked out of the grid becomes the day
    // on screen, and that the grid marks what the folder holds. Where it
    // settles when a finger lets go of it mid-travel, and that a reversal
    // part-way through is honoured, are `DatePillTests` in Core: they are
    // arithmetic, and a synthesized drag is the wrong instrument for
    // arithmetic.

    func testTheDatePillOpensAndGoesBetweenTheWeekAndTheMonth() throws {
        let app = launchApp()
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")
        XCTAssertEqual(pill.value as? String, "Closed")

        // Nothing of the grid is reachable while it is shut — a shut pill is
        // not a calendar with the lights off.
        XCTAssertFalse(
            app.buttons["day-\(todaysEntryName())"].exists,
            "the month was reachable behind a shut pill"
        )

        pill.tap()
        expect(pill, toHaveValue: "Week")
        let today = app.buttons["day-\(todaysEntryName())"]
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the week strip had no days on it")
        XCTAssertTrue(today.isHittable, "today could not be tapped in the week strip")

        pill.tap()
        expect(pill, toHaveValue: "Month")

        // And back to the week, rather than round to shut: what a tap on the
        // pill is for is the one question it asks — this week, or this month.
        // Shutting it is the page behind it, and picking a day out of it.
        pill.tap()
        expect(pill, toHaveValue: "Week")

        pill.tap()
        expect(pill, toHaveValue: "Month")

        // A strip is one week and not a month with five of its rows painted
        // out. A row the grid has slid past is drawn nowhere *and* is not
        // there to be tapped — those rows sit squarely on the pill they came
        // out of, so a week's worth of invisible buttons there would pick a
        // day nobody aimed at, and swallow the tap that opens the month.
        //
        // A week away is the same weekday one row over — on the grid and
        // never on the strip — so long as it is a week the month reaches.
        // Which way to look is a question of the date: a week back falls off
        // the top of the grid while the month is under a week old, and a week
        // on is in the month for exactly as long as a week back is not. Told
        // apart by the day of the month, which is the same in every locale;
        // which weekday starts a row is not.
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        let aWeekAway = try XCTUnwrap(daysBeforeToday(dayOfMonth > 7 ? 7 : -7))
        let aRowOver = app.buttons["day-\(entryName(for: aWeekAway))"]
        openTheDatePill(app, to: "Week")
        XCTAssertTrue(aRowOver.exists, "the week beside this one was not on the grid")
        if aRowOver.isHittable { aRowOver.tap() }
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "a day the strip had slid past was picked through the ceiling"
        )

        // And with the whole month out a day off the strip is a day like any
        // other. Which is also what says the ceiling is not simply shut: a
        // grid nothing could be picked from would pass every check above.
        //
        // Picked in the past, because a day that has not arrived is locked
        // however far open the month is — and early in the month, when the
        // row over is the week ahead, the grid's pickable past is yesterday,
        // worn as one of the fill days the grid keeps around its edge.
        let pickable =
            dayOfMonth > 7
            ? aRowOver
            : app.buttons["day-\(entryName(for: try XCTUnwrap(dayBeforeToday())))"]
        openTheDatePill(app, to: "Month")
        pickable.tap()
        XCTAssertTrue(
            app.buttons["backToToday"].waitForExistence(timeout: 5),
            "a day could not be picked with the whole month showing"
        )
    }

    /// Where the shut pill sits, which is the one thing about it that is not a
    /// question of how far open it is.
    ///
    /// The failure this catches is an overlay left to its own alignment: sized
    /// to a pill one row tall, it centres it, and the day's name hangs halfway
    /// down the page until the calendar comes out and the way out of it fills
    /// the screen — at which point the pill jumps to the top.
    func testTheShutDatePillSitsAtTheTopOfThePage() throws {
        let app = launchApp()
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")
        expect(pill, toHaveValue: "Closed")

        let window = app.windows.firstMatch.frame
        let shut = pill.frame
        XCTAssertLessThan(
            shut.midY, window.minY + window.height / 4,
            "the shut pill was not near the top of the page: \(shut) in \(window)"
        )

        // And it was there all along, rather than arriving there when the
        // calendar came out.
        openTheDatePill(app, to: "Week")
        XCTAssertEqual(
            pill.frame.minY, shut.minY, accuracy: 1,
            "the pill moved up the page when it was opened: \(pill.frame) from \(shut)"
        )
    }

    /// The other way through the calendar, and the only one a week strip has
    /// room for: a finger drawn across it.
    ///
    /// What a walk arrives at is asked by picking the day it walked to, rather
    /// than by measuring where a cell has got to. The strip is the month grid
    /// slid up under a ceiling, and a row the grid has slid past is not there
    /// to be picked — so a day off the strip that *can* be picked is a strip
    /// that moved onto it, which is the whole claim.
    func testTheDatePillIsWalkedSidewaysAWeekAndAMonthAtATime() throws {
        let app = launchApp()
        let today = app.buttons["day-\(todaysEntryName())"]
        let aWeekAgo = app.buttons["day-\(entryName(for: try XCTUnwrap(daysBeforeToday(7))))"]

        openTheDatePill(app, to: "Week")
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the week strip had no days on it")
        XCTAssertTrue(today.isHittable, "today was not on the strip to begin with")

        // Rightwards is backwards: a week ago is the same weekday one row up,
        // off the strip until the strip is walked to it.
        swipeTheWeekStrip(app, alongside: today, across: 160)
        XCTAssertTrue(
            waitFor { aWeekAgo.isHittable },
            "a swipe across the strip did not bring the week before onto it"
        )
        aWeekAgo.tap()
        XCTAssertTrue(
            app.buttons["backToToday"].waitForExistence(timeout: 5),
            "the day tapped on the strip was not opened"
        )

        // With the whole month out the same finger steps months instead: one
        // of whatever unit is on screen.
        openTheDatePill(app, to: "Month")
        let month = app.staticTexts["pillMonth"]
        XCTAssertTrue(month.waitForExistence(timeout: 5), "the month was not named over the grid")
        let thisMonth = month.label

        swipe(month, across: -160)
        XCTAssertTrue(
            waitFor { month.label != thisMonth },
            "a swipe across the month did not step it on from \(thisMonth)"
        )

        swipe(month, across: 160)
        expect(month, toHaveLabel: thisMonth)

        // And walking the calendar is looking rather than choosing: the day
        // the app is on is still the one picked out of the strip.
        XCTAssertTrue(
            app.buttons["backToToday"].exists,
            "walking the months moved the day being written"
        )
    }

    /// That a drag drives the pill at all, which is the half of the gesture no
    /// unit test can reach.
    ///
    /// One pull, and a long one. Where a drag *settles* — the rounding to the
    /// nearest state, the few points that are a tap rather than a drag, the
    /// reversal halfway — is `DatePillTests` in Core, and it belongs there. A
    /// synthesized drag is not a finger: it arrives often enough as a press
    /// and *then* a drag that asking a point-exact question of one is asking
    /// it of the harness. A pull long enough to clamp is the one answer that
    /// is the same either way.
    ///
    /// Only downward, too. The pill sits an inch from the top of the screen,
    /// so a finger on it has the whole page to pull down into and barely
    /// seventy points to pull up — less than one state's worth. Dragging a
    /// month shut is not something to leave a reader needing: tapping the pill
    /// closes it, and so does tapping the day's own words
    /// (`testTappingTheDaysWordsShutsTheDatePill`).
    func testTheDatePillIsDraggedOpen() throws {
        let app = launchApp()
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")

        // Pulled far enough down to be unambiguous, it goes the whole way in
        // one gesture rather than one state at a time.
        drag(pill, by: 400)

        expect(pill, toHaveValue: "Month")
        XCTAssertTrue(
            app.buttons["day-\(todaysEntryName())"].waitForExistence(timeout: 5),
            "the month a drag opened had no days on it"
        )
    }

    func testPickingADayFromTheDatePillOpensItAndShutsThePill() throws {
        let app = launchApp(contentTemplate: "# {{title}}\n")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )
        let yesterday = try XCTUnwrap(dayBeforeToday())

        openTheDatePill(app, to: "Month")
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "yesterday was not on the month")
        XCTAssertEqual(cell.value as? String, "Not written")
        cell.tap()

        // Picked, so the pill has nothing left to say and shuts itself.
        let pill = app.buttons["datePill"]
        expect(pill, toHaveValue: "Closed")

        // And the day it named is the day now open — spawned from the template
        // with *that* day's date, in place, without a screen being pushed.
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "yesterday's entry never opened")
        let spawned = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(
            spawned.contains("# \(entryName(for: yesterday))"),
            "expected yesterday's entry to be titled after its own day, got: \(spawned)"
        )

        editor.tap()
        editor.typeText("Filled in the next morning.")

        // The way back, offered only because the app is no longer on today.
        let backToToday = app.buttons["backToToday"]
        XCTAssertTrue(backToToday.waitForExistence(timeout: 5), "there was no way back to today")
        backToToday.tap()

        // The mark follows the file: the day was written on, so opening the
        // month again reads the folder and finds it.
        openTheDatePill(app, to: "Month")
        expect(cell, toHaveValue: "Written")
    }

    func testTappingTheDaysWordsShutsTheDatePill() throws {
        let app = launchApp()
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )
        let pill = app.buttons["datePill"]

        openTheDatePill(app, to: "Month")

        // Going back to the day's own words is a way of saying you are done
        // with the calendar. Low down the page, so it is the page being tapped
        // and not the grid hanging over the top of it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(pill, toHaveValue: "Closed")

        // And nothing was picked on the way out: shutting the calendar is not
        // choosing a day from it.
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "shutting the pill by tapping the page picked a day"
        )
    }

    func testAFutureDayCannotBePickedFromTheDatePill() throws {
        let app = launchApp()
        let tomorrow = try XCTUnwrap(dayAfterToday())

        openTheDatePill(app, to: "Month")
        let cell = app.buttons["day-\(entryName(for: tomorrow))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "tomorrow was not on the month")
        XCTAssertFalse(cell.isEnabled, "a day that has not arrived cannot be written in")

        // Tapped anyway: a locked day is one that does nothing, not one that
        // opens an editor nobody can save from.
        if cell.isHittable { cell.tap() }

        // Nothing moved: the pill is still open on the month, and the app is
        // still on today.
        expect(app.buttons["datePill"], toHaveValue: "Month")
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "a day that has not arrived was opened"
        )
    }

    func testTheMonthOnTheDatePillMarksTheDaysTheFolderHolds() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let theDayBefore = try XCTUnwrap(daysBeforeToday(2))
        let app = launchApp(
            entries: "\(entryName(for: yesterday)) Walked to the market with Robin."
        )

        openTheDatePill(app, to: "Month")

        expect(app.buttons["day-\(entryName(for: yesterday))"], toHaveValue: "Written")
        expect(
            app.buttons["day-\(entryName(for: theDayBefore))"],
            toHaveValue: "Not written"
        )
    }

    /// The claim the pill's own geometry is bounded by: a month is seven
    /// columns across whatever the reader's text size, so at the largest one
    /// the grid still fits between the edges of the screen.
    ///
    /// The failure this catches is the one a fixed cell size causes and a
    /// screenshot would not: the tint under a day drawn at a size measured
    /// off the row rather than off the column, spilling onto the day beside
    /// it, on the one setting nobody develops at.
    func testTheDatePillHoldsTogetherAtTheLargestTextSize() throws {
        let app = launchApp(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openTheDatePill(app, to: "Month")

        let window = app.windows.firstMatch.frame
        let cells = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'day-'")
        )
        XCTAssertGreaterThan(cells.count, 0, "the month had no days on it")

        for cell in cells.allElementsBoundByIndex {
            let frame = cell.frame
            XCTAssertGreaterThanOrEqual(
                frame.minX, window.minX - 0.5,
                "a day of the month hangs off the left of the screen: \(cell.label) at \(frame)"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX, window.maxX + 0.5,
                "a day of the month hangs off the right of the screen: \(cell.label) at \(frame)"
            )
        }

        // And the day being written is still nameable, which is what the pill
        // is for — the one thing on it that does grow all the way.
        let pill = app.buttons["datePill"]
        XCTAssertLessThanOrEqual(
            pill.frame.maxX, window.maxX + 0.5,
            "the pill hangs off the side at the largest text size: \(pill.frame)"
        )
    }

    // MARK: - Walking the journal a day at a time

    // The way through the journal that does not open the grid: a finger drawn
    // sideways across the shut pill, which steps a day the same way a finger
    // across the open one steps a week or a month. And the two days that are
    // not an ordinary written day — one that has not arrived, and one already
    // gone that nobody wrote.
    //
    // What is asked here is what only a running app can show: that a finger
    // moves the journal at all, that it does not do it while it is pulling the
    // pill open, and that the pages either end of the ordinary case are the
    // ones that appear. Where a swipe settles, how much of the finger the pill
    // takes and which day it lands on are `DaySwipeTests` in Core — they are
    // arithmetic, and a synthesized drag is the wrong instrument for
    // arithmetic.

    func testADayIsSwipedAsideToReachTheDayEitherSideOfIt() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            entries: "\(entryName(for: yesterday)) Walked to the market with Robin.",
            todaysEntry: "At the desk all day.\n"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        expect(editor, toHaveValue: "At the desk all day.\n")

        // Rightwards is backwards, as it is everywhere else in the app.
        swipeTheDay(app, across: 160)
        expect(editor, toHaveValue: "Walked to the market with Robin.\n")
        XCTAssertTrue(
            app.buttons["backToToday"].exists,
            "a swipe moved the day without the app knowing it had left today"
        )

        // And leftwards is forwards, back to the day it started on — which is
        // today, and so is following the clock again rather than pinned to
        // today's date.
        swipeTheDay(app, across: -160)
        expect(editor, toHaveValue: "At the desk all day.\n")
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "swiping back onto today left the app thinking it was elsewhere"
        )
    }

    /// A swipe is a thing somebody has to mean. The threshold itself is Core's
    /// (`DaySwipeTests`); what this asks is that the app honours it, that a
    /// finger which changed its mind leaves the journal where it found it —
    /// and that the pill it was drawn across is still shut, because a short
    /// sideways drag must not come out as the tap that opens the calendar.
    func testAShortSwipeLeavesTheDayWhereItWas() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            entries: "\(entryName(for: yesterday)) Walked to the market with Robin.",
            todaysEntry: "At the desk all day.\n"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        swipeTheDay(app, across: 40)

        expect(editor, toHaveValue: "At the desk all day.\n")
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "a swipe too short to mean it moved the journal anyway"
        )
        expect(app.buttons["datePill"], toHaveValue: "Closed")
    }

    /// The axis lock, asked the only way a running app can ask it. Both
    /// gestures live on the pill and share a finger now, so a pull down it —
    /// which no finger draws exactly vertically — must open the calendar and
    /// nothing else, however far off true it wanders.
    func testPullingThePillOpenDoesNotTakeTheDayWithIt() throws {
        let app = launchApp(todaysEntry: "At the desk all day.\n")
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")

        drag(pill, by: 400)

        expect(pill, toHaveValue: "Month")
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "pulling the pill open moved the day being written"
        )
    }

    /// Sideways on an open pill answers nothing. The pages under the header
    /// are what a sideways finger moves, and they carry a gesture of their own
    /// — a header that walked the days as well would be a second answer to one
    /// finger, and one that merely leaned would be the whole pane sliding
    /// while the grid inside it slid the other way.
    ///
    /// Three things it must not do, and the pill has done all three: step the
    /// day, step the month, or come out as the tap that goes between the week
    /// and the month.
    func testSwipingTheOpenPillAnswersNothingAndLeavesThePagesToTheGrid() throws {
        let app = launchApp(todaysEntry: "At the desk all day.\n")
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")
        let today = pill.label

        openTheDatePill(app, to: "Month")
        let month = app.staticTexts["pillMonth"]
        XCTAssertTrue(month.waitForExistence(timeout: 5), "the month was not named over the grid")
        let thisMonth = month.label

        // Drawn across the header, which is the pill itself.
        swipe(pill, across: -160)

        expect(pill, toHaveValue: "Month")
        expect(month, toHaveLabel: thisMonth)
        expect(pill, toHaveLabel: today)
        XCTAssertFalse(
            app.buttons["backToToday"].exists,
            "a swipe across the open pill moved the day being written"
        )

        // And across the grid under it, which is where sideways does belong.
        swipe(month, across: -160)

        XCTAssertTrue(
            waitFor { month.label != thisMonth },
            "a swipe across the grid did not step the month on from \(thisMonth)"
        )
        expect(pill, toHaveLabel: today)
    }

    func testADayThatHasNotArrivedIsLockedAndSaysWhenWritingOpens() throws {
        let app = launchApp(todaysEntry: "At the desk all day.\n")
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        // Forwards, off the end of the days there are to write.
        swipeTheDay(app, across: -160)


        let locked = app.staticTexts["aDayThatHasNotArrived"]
        XCTAssertTrue(
            locked.waitForExistence(timeout: 10),
            "a day that has not arrived did not say so — the screen is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
        // Cannot be typed in, which is the whole of what "locked" means here:
        // an editor is the only thing that can write an Entry, and there is
        // not one.
        XCTAssertFalse(editor.exists, "a day that has not arrived had an editor on it")

        // And it names the hour writing opens at, which is this journal's
        // Rollover Hour — midnight, until somebody changes it.
        let opens = app.staticTexts["whenWritingOpens"]
        XCTAssertTrue(
            opens.label.contains(onTheClock(hour: 0)),
            "the locked day did not name when writing opens: \(opens.label)"
        )

        // The pill is over it like any other day, with the way back on it.
        XCTAssertTrue(
            app.buttons["backToToday"].exists,
            "a day that has not arrived had no way back to today on it"
        )

        // Left the way it was arrived at.
        swipeTheDay(app, across: 160)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the day could not be swiped back out of")
        expect(editor, toHaveValue: "At the desk all day.\n")
    }

    /// A day nobody has written is drawn quieter than one somebody has, and
    /// stops being quiet at the first keystroke rather than at the file that
    /// keystroke eventually makes.
    ///
    /// The ink itself is `UnwrittenDayStylingTests`, which holds the two steps
    /// to being two steps and the quiet one to the ink a sentence takes. What
    /// only a running app can show is that the words on screen actually change
    /// when the day does — so this asks the pixels, and asks them of the same
    /// text twice over: a character typed and taken straight back out again
    /// leaves the day saying exactly what it said, in the other ink.
    ///
    /// Both readings are taken with the keyboard up. It covers a third of the
    /// screen, and a before that had it down would be a comparison of two
    /// different pictures.
    func testAnUnwrittenPastDayIsDrawnQuietlyUntilItIsTypedIn() throws {
        // Enough prose that ink is a fair share of the pixels: a page holding
        // one short line would put the whole difference inside the rounding.
        let template = """
            # {{title}}

            Walked to the market and back the long way round.
            The stalls were packing up by the time I got there.
            Bought bread, and a paper nobody had opened.
            Sat on the wall by the church and read the front of it.
            Rain came in off the hill at about four.
            Home, and the kettle on before the coat was off.
            Wrote none of this down until the next morning.
            """
        let app = launchApp(contentTemplate: template)
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        swipeTheDay(app, across: 160)

        // Spawned for *that* day and not for today, which is what filling one
        // in after the fact means.
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let itsOwnTitle = "# \(entryName(for: yesterday))"
        XCTAssertTrue(
            waitFor { (editor.value as? String)?.contains(itsOwnTitle) == true },
            "expected yesterday's entry to be titled after its own day, got: "
                + ((editor.value as? String) ?? "nothing")
        )
        let spawned = try XCTUnwrap(editor.value as? String)

        // And nothing is in the folder: the marks are a scan of it, so a day
        // still marked unwritten is a day with no file.
        openTheMonth(app, showing: yesterday)
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        expect(cell, toHaveValue: "Not written")
        // Put away by hand rather than through `shutTheDatePill`, for the
        // failure message: the tap is a bare coordinate below an open month,
        // and the one thing worth knowing when it misses is how far down the
        // panel actually reached.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        let pill = app.buttons["datePill"]
        XCTAssertTrue(
            waitFor { pill.value as? String == "Closed" },
            "the tap below the month did not shut the pill — the pill is at "
                + "\(pill.frame) in a window of \(app.windows.firstMatch.frame)"
        )

        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the day went away with the pill")
        editor.tap()
        let quiet = try brightness(of: editor)

        // One character in and straight back out: the day says exactly what it
        // said, and it is no longer a day nobody has written.
        editor.typeText("x")
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        expect(editor, toHaveValue: spawned)
        let written = try brightness(of: editor)

        XCTAssertGreaterThan(
            abs(quiet - written), 0.01,
            "the same words came out the same on a day nobody had written and a day "
                + "somebody had — \(quiet) against \(written)"
        )

        // At the keystroke and not at the file, which is the whole of what
        // "until the first edit" means: the day says exactly what it said, so
        // there is still nothing in the folder to mark, and it is drawn as a
        // day somebody has written anyway.
        //
        // Last, because the keyboard is up from here on and it covers the page
        // the pill is put away by tapping. That the file does arrive once
        // there is something to put in it is
        // `testAPastDayIsFilledInFromTheCalendar`.
        openTheMonth(app, showing: yesterday)
        expect(cell, toHaveValue: "Not written")
    }

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

        let share = app.buttons["shareEntry"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "today's entry offered no way to share it")
        share.tap()

        XCTAssertTrue(
            app.buttons["shareAsPDF"].waitForExistence(timeout: 5),
            "the share menu did not offer a PDF"
        )
        XCTAssertTrue(app.buttons["shareAsPlainText"].exists, "the share menu did not offer plain text")

        app.buttons["shareAsPlainText"].tap()

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

        let share = app.buttons["shareEntry"]
        XCTAssertTrue(
            share.waitForExistence(timeout: 10),
            "a day reached from the calendar offered no way to share it"
        )
        share.tap()
        XCTAssertTrue(
            app.buttons["shareAsPDF"].waitForExistence(timeout: 5),
            "the share menu did not offer a PDF for a day from history"
        )

        app.buttons["shareAsPDF"].tap()

        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 30),
            "the share sheet never came up for a day from history"
        )
    }

    /// Puts the system share sheet away, whichever way this device offers.
    ///
    /// The Close button where the activity controller draws one, and a swipe
    /// down where it does not — the sheet is presented by SwiftUI and is
    /// dismissible either way, and which of them is on screen differs between
    /// the two device families the suite runs on.
    private func dismissTheShareSheet(_ app: XCUIApplication) {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 5), close.isHittable {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForNonExistence(timeout: 10),
            "the share sheet would not go away"
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
        openSettings(app)
        XCTAssertEqual(app.staticTexts["journalRootLocation"].label, aujoursOwnFolder)
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
        openSettings(app)
        XCTAssertEqual(app.staticTexts["journalRootLocation"].label, vault)
        XCTAssertEqual(app.staticTexts["journalEntryCount"].label, "1 entry")

        // And the way back: Aujour's own folder, with everything that was
        // written there still in it.
        app.buttons["useAujoursOwnFolder"].tap()
        expect(app.staticTexts["journalRootLocation"], toHaveLabel: aujoursOwnFolder)
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

        // The Parked File is beside the journal and not in it: one day
        // written, one entry, whatever else is in the folder (ADR 0002).
        XCTAssertEqual(entryCountFromTheSettingsSheet(app), "1 entry")
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

        openSettings(app)
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
        XCTAssertEqual(entryCountFromTheSettingsSheet(app), "1 entry")
        XCTAssertEqual(app.textFields["entryPathField"].value as? String, "[Journal]/YYYY-MM-DD")
    }

    func testSkippingTheMigrationLeavesTheOldFilesWhereTheyAreAndUnsurfaced() throws {
        let app = launchApp(todaysEntry: "Walked to the market.")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openSettings(app)
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
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the day found never opened")
        let opened = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(
            opened.contains("Walked to the market with Robin."),
            "expected the day that was searched for, got: \(opened)"
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

    // MARK: - What travels and what stays

    /// ADR 0003's boundary, made visible: the settings sheet is two groups,
    /// and which one a setting is in is the whole of what tells the user
    /// whether changing it reaches their iPad.
    ///
    /// Asked by where each control sits rather than by reading the two
    /// headings, because the headings are the easy half. A sheet can say
    /// "these travel" over a group with the theme in it, and it would pass
    /// every check that only looked for the words.
    ///
    /// Every frame is read at one scroll position and none of them is
    /// scrolled to, which is what makes the comparison a comparison: the
    /// sections are laid out whether or not they are on screen, and a swipe
    /// between two readings would be measuring a position before it against a
    /// position after it.
    ///
    /// The two the design files get wrong are in the travelling list on
    /// purpose: where photographs go and how they are written are separate
    /// controls, not one row called "Attachments".
    func testTheSettingsSayWhichOfThemReachTheOtherDevices() throws {
        let app = launchApp()
        openSettings(app)

        let travels = app.staticTexts["journalSettingsSaying"]
        XCTAssertTrue(
            travels.waitForExistence(timeout: 10),
            "the sheet never said which of its settings reach the other devices"
        )
        let stays = app.staticTexts["deviceSettingsSaying"]
        XCTAssertTrue(
            stays.waitForExistence(timeout: 10),
            "the sheet never said which of its settings stay on this device"
        )

        let travelling = travels.frame.minY
        let onThisDevice = stays.frame.minY
        XCTAssertLessThan(
            travelling, onThisDevice,
            "the two groups are not one above the other — the journal's are at "
                + "\(travelling) and the device's at \(onThisDevice)"
        )

        // Every Journal Setting with a control of its own, under the heading
        // that promises it travels.
        let journals: [(String, XCUIElement)] = [
            ("where each day's entry goes", app.textFields["entryPathField"]),
            ("what a new day starts from", app.buttons["contentTemplateFile"]),
            ("how the calendar is written out", app.buttons["dataPlaceholder-events"]),
            ("how the reminders are written out", app.buttons["dataPlaceholder-reminders"]),
            ("when the day turns", app.buttons["rolloverHour"]),
            ("where photos go", app.textFields["attachmentPathField"]),
            ("how photos are written", app.segmentedControls["embedSyntax"]),
        ]
        for (what, control) in journals {
            XCTAssertTrue(control.exists, "\(what) is not on the settings sheet at all")
            // Two comparisons rather than a range, which would trap on the
            // very inversion this test exists to catch.
            let y = control.frame.minY
            XCTAssertTrue(
                y > travelling && y < onThisDevice,
                "\(what) is not among the settings that travel — it is at \(y), "
                    + "and that group runs from \(travelling) to \(onThisDevice)"
            )
        }

        // And every Device Setting under the heading that promises it does
        // not. The half that would go unnoticed: a sheet with both headings
        // and everything under the first one says nothing at all.
        let devices: [(String, XCUIElement)] = [
            ("how it looks", app.buttons["openHowItLooks"]),
            ("the daily reminder", app.switches["dailyReminder"]),
        ]
        for (what, control) in devices {
            XCTAssertTrue(control.exists, "\(what) is not on the settings sheet at all")
            XCTAssertGreaterThan(
                control.frame.minY, onThisDevice,
                "\(what) is being promised to the user's other devices — it is at "
                    + "\(control.frame.minY), above the line at \(onThisDevice)"
            )
        }

        // And each heading says which kind it is in words, since that is what
        // a user actually reads; the positions above are only how a test can
        // tell. Told apart by whether the sentence names *this* device, which
        // is the difference between them rather than a phrase to match: a
        // group that stays is about this iPhone by name, and one that travels
        // cannot be about any device in particular. Two sayings swapped
        // between the groups fail here, which a check for the word "device"
        // in both would not.
        let thisDevice = UIDevice.current.model.lowercased()
        XCTAssertTrue(
            travels.label.lowercased().contains("devices"),
            "the group that travels does not say where its settings go — it says "
                + "\"\(travels.label)\""
        )
        XCTAssertFalse(
            travels.label.lowercased().contains(thisDevice),
            "the group that travels is talking about this \(UIDevice.current.model) "
                + "in particular — it says \"\(travels.label)\""
        )
        XCTAssertTrue(
            stays.label.lowercased().contains(thisDevice),
            "the group that stays does not say which device it stays on — it says "
                + "\"\(stays.label)\""
        )
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

    // MARK: - Driving the app

    /// Launches the app onto a journal folder of this test's own.
    ///
    /// The keys are spelled out rather than shared: the app and the UI suite
    /// are separate targets, and this suite deliberately imports nothing from
    /// the app it is driving. Their other half is `UITestingJournal`, which is
    /// where they are read.
    ///
    /// - Parameters:
    ///   - welcome: whether this launch is a device nobody has welcomed yet.
    ///     `false` — a device that has been through it — for every test but
    ///     the first run's own, since the welcome is a cover over the app and
    ///     dismissing one is not what any other test is here to do.
    ///   - folderToPick: the folder "Use a custom folder…" picks, in place of
    ///     the Files picker.
    ///   - todaysEntry: what today's Entry file already says, written an hour
    ///     ago — a day this device journaled before the app was opened.
    ///   - divergedVersion: what another device wrote for today, which iCloud
    ///     is holding as an unresolved version of the same file. Dated at
    ///     launch, so it is the newer of the two.
    ///   - vaultNote: a file the folder already holds that is none of Aujour's
    ///     business — a note the vault made — and the path it sits at.
    ///   - templateToPick: the markdown of a template file kept outside the
    ///     journal folder, for "Choose a template file…" to pick in place of
    ///     the Files picker.
    ///   - photograph: the format of the photograph the app hands itself in
    ///     place of the one the system picker would have come back with —
    ///     `png`, `jpeg` or `heic`.
    ///   - photoLibrary: the days the device's camera roll holds a photograph
    ///     from, one per line as `YYYY-MM-DD` or `YYYY-MM-DD HH:mm`. The
    ///     simulator's library is empty and behind a system alert nothing here
    ///     can answer, so this is the only way the suggestions panel has
    ///     anything to offer.
    ///   - photoLibraryAccess: where the library permission stands before the
    ///     test starts, and what the user says if they are asked — `allowed`,
    ///     which is the default; `undecided` for somebody who says yes to the
    ///     panel's offer to look; `refuses` for somebody who says no to it;
    ///     `refused` for somebody who said no some launch ago.
    ///   - events: what the day being spawned holds in the calendar, one per
    ///     line as `HH:mm Title` — or `Title` for something with no hour. The
    ///     simulator's own calendar is empty and unaskable, so this is the
    ///     only way a data placeholder has anything to render.
    ///   - reminders: the same, for the day's reminders.
    private func launchApp(
        textSize: String? = nil,
        contentTemplate: String? = nil,
        welcome: Bool = false,
        folderToPick: String? = nil,
        entries: String? = nil,
        todaysEntry: String? = nil,
        divergedVersion: String? = nil,
        vaultNote: (at: String, saying: String)? = nil,
        templateToPick: String? = nil,
        photograph: String? = nil,
        photoLibrary: String? = nil,
        photoLibraryAccess: String? = nil,
        events: String? = nil,
        reminders: String? = nil,
        places: String? = nil,
        placesAccess: String? = nil,
        placesAt: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AUJOUR_UITEST_JOURNAL_FOLDER"] = journalFolder
        // Where the reader has left the system's text size. A launch argument
        // and not an environment variable, because this is UIKit's own switch
        // rather than one of Aujour's — the app never reads it, it just comes
        // up drawn at that size.
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        // Only when a test asks for one. Seeded on every launch, it would be
        // set again on the relaunch that is supposed to prove a template set
        // through the app is still there.
        if let contentTemplate {
            app.launchEnvironment["AUJOUR_UITEST_CONTENT_TEMPLATE"] = contentTemplate
        }
        // Only for the test that is about the first run. Everybody else is a
        // device that has already been through the welcome, because it is a
        // cover over the whole app and dismissing one is not what any other
        // test is here to do.
        if welcome {
            app.launchEnvironment["AUJOUR_UITEST_WELCOME"] = "due"
        }
        if let folderToPick {
            app.launchEnvironment["AUJOUR_UITEST_FOLDER_TO_PICK"] = folderToPick
        }
        if let entries {
            app.launchEnvironment["AUJOUR_UITEST_ENTRIES"] = entries
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
        if let templateToPick {
            app.launchEnvironment["AUJOUR_UITEST_TEMPLATE_TO_PICK"] = templateToPick
        }
        if let photograph {
            app.launchEnvironment["AUJOUR_UITEST_PHOTO"] = photograph
        }
        if let photoLibrary {
            app.launchEnvironment["AUJOUR_UITEST_PHOTO_LIBRARY"] = photoLibrary
        }
        if let photoLibraryAccess {
            app.launchEnvironment["AUJOUR_UITEST_PHOTO_LIBRARY_ACCESS"] = photoLibraryAccess
        }
        if let events {
            app.launchEnvironment["AUJOUR_UITEST_EVENTS"] = events
        }
        if let reminders {
            app.launchEnvironment["AUJOUR_UITEST_REMINDERS"] = reminders
        }
        if let places {
            app.launchEnvironment["AUJOUR_UITEST_PLACES"] = places
        }
        if let placesAccess {
            app.launchEnvironment["AUJOUR_UITEST_PLACES_ACCESS"] = placesAccess
        }
        if let placesAt {
            app.launchEnvironment["AUJOUR_UITEST_PLACES_AT"] = placesAt
        }
        app.launch()
        return app
    }

    /// Opens the one sheet: where the journal is kept, every setting that
    /// shapes what goes into it, and the ones that stay on this device.
    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 30),
            "the settings button never appeared"
        )
        settings.tap()
        XCTAssertTrue(
            app.staticTexts["journalRootLocation"].waitForExistence(timeout: 10),
            "the settings sheet never appeared"
        )
    }

    /// Taps an option in an open menu, found by what it says rather than by
    /// an identifier: the rows a `Picker` puts in a menu carry their label and
    /// no identifier of their own.
    private func tapTheOption(labelled label: String, in app: XCUIApplication) {
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(
            option.waitForExistence(timeout: 10),
            "the menu never offered \(label) — it offered "
                + app.buttons.allElementsBoundByIndex.map { "[\($0.label)]" }.joined()
                + " and menu items "
                + app.menuItems.allElementsBoundByIndex.map { "[\($0.label)]" }.joined()
        )
        option.tap()
    }

    /// An hour of the day as this device's clock writes it — the same way the
    /// app writes it, so that a test does not assert an American clock on a
    /// simulator set to a French one.
    ///
    /// The whole hour, which is the Rollover Hour: `RolloverHour.spelledOut`
    /// is a `TimeOfDay` at nought minutes, so it is written off the same
    /// daylight-saving-free day as every other clock face in the app.
    private func onTheClock(hour: Int) -> String {
        onTheClock(hour: hour, minute: 0)
    }

    /// A reminder's time as this device's clock writes it — measured off a day
    /// with no daylight saving in it, which is how the app writes one
    /// (`TimeOfDay.spelledOut`): a clock face is a clock face on the two days
    /// a year the local one has an hour missing.
    private func onTheClock(hour: Int, minute: Int) -> String {
        let noRules = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = noRules

        let midnight = Date(timeIntervalSince1970: 0)
        let atThatTime =
            calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: midnight)
            ?? midnight
        return atThatTime.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: noRules)
        )
    }

    /// Replaces what is in the entry path field, and puts the keyboard away.
    private func typeEntryPath(_ path: String, into app: XCUIApplication) {
        replaceTheText(in: "entryPathField", with: path, in: app)
    }

    /// Replaces what is in a settings field named by its identifier, and puts
    /// the keyboard away — the data placeholder pages are four of them on one
    /// screen.
    ///
    /// Scrolled to first, because these sit below the fold on a small phone,
    /// and a field that is not on screen cannot be tapped into.
    ///
    /// Cleared a character at a time from the end, because a text field's
    /// whole contents cannot be selected without a hardware keyboard the
    /// simulator does not have.
    ///
    /// The keyboard is dismissed afterwards for a plain reason: it covers the
    /// button the test is about to press.
    private func replaceTheText(
        in identifier: String,
        with text: String,
        in app: XCUIApplication
    ) {
        let field = app.textFields[identifier]
        scrollTo(field, in: app)
        giveTheKeyboardTo(field, in: app)

        // Read after the field has the keyboard and not before: taking it
        // scrolls the sheet, and everything here is measured against where
        // the field ended up.
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText(text)
        field.typeText("\n")

        XCTAssertEqual(field.value as? String, text)
    }

    /// Puts the caret at the end of a text field, and lets the sheet stop
    /// moving before deciding where the end is.
    ///
    /// Two taps and not one, which is not superstition. The first summons the
    /// keyboard, and a field far enough down a sheet is where the keyboard is
    /// about to be — so iOS scrolls the sheet out from under the finger as it
    /// rises, and what the runner types next goes to a field that is no
    /// longer where it was tapped ("Neither element nor any descendant has
    /// keyboard focus", which is a sentence about the runner rather than
    /// about the app). The second tap is taken against the frame the field
    /// settled at; on a field that already has the caret it does nothing but
    /// move it, which is what it is for.
    ///
    /// At the far right both times, so the caret lands behind the last
    /// character rather than wherever the middle of the field happened to be.
    private func giveTheKeyboardTo(_ field: XCUIElement, in app: XCUIApplication) {
        let theEndOfIt = CGVector(dx: 0.95, dy: 0.5)
        field.coordinate(withNormalizedOffset: theEndOfIt).tap()
        // Waited for and never required. A machine with a hardware keyboard
        // attached shows no software one and focuses the field just the same,
        // which is what the CI runners do and what a developer's Mac does
        // not — so asserting on it here failed a green app on the one leg
        // that could not have passed. What the wait is for is the other case:
        // where a keyboard does rise, it takes the sheet up with it, and the
        // second tap has to land after that rather than during it.
        _ = app.keyboards.element.waitForExistence(timeout: 5)
        field.coordinate(withNormalizedOffset: theEndOfIt).tap()
    }

    // MARK: - Theming

    /// What theming is, said the only way a running app can say it: a choice
    /// made on this screen is the app's, and it is still the app's after a
    /// relaunch.
    ///
    /// Which colour each accent resolves to in light and in dark, and what
    /// "serif at 22 points" comes out as once Dynamic Type has had it, are
    /// checked where a colour and a font exist to check them, in
    /// `AppearanceTests`. What only a running app can show is that the three
    /// controls reach the settings at all, and that what they wrote survives
    /// the process ending.
    func testHowAujourLooksIsChosenOnThisDeviceAndStaysChosen() throws {
        let app = launchApp()

        openHowItLooks(in: app)

        let specimen = app.staticTexts["editorFontSpecimen"]
        let asItComes = try XCTUnwrap(specimen.value as? String)

        app.segmentedControls["appearanceTheme"].buttons["Dark"].tap()
        app.buttons["accent.olive"].tap()
        app.segmentedControls["editorFontFamily"].buttons["Serif"].tap()
        app.segmentedControls["editorFontSize"].buttons["XL"].tap()

        XCTAssertEqual(app.staticTexts["accentInUse"].label, "Olive")
        let chosenFont = try XCTUnwrap(specimen.value as? String)
        XCTAssertTrue(
            chosenFont.hasPrefix("Serif, "),
            "the specimen is not in the chosen face — it says \(chosenFont)"
        )
        XCTAssertNotEqual(
            chosenFont, asItComes,
            "the size control moved nothing — the specimen still says \(chosenFont)"
        )

        relaunch(app)

        // The journal sheet says which accent is in force before it is opened,
        // which is the shortest proof that the choice outlived the process.
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "the app never came back")
        settings.tap()

        let howItLooks = app.buttons["openHowItLooks"]
        scrollTo(howItLooks, in: app)
        XCTAssertTrue(howItLooks.label.contains("Olive"), "the accent did not survive a relaunch")
        howItLooks.tap()

        XCTAssertTrue(
            app.segmentedControls["appearanceTheme"].buttons["Dark"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.segmentedControls["appearanceTheme"].buttons["Dark"].isSelected,
            "the appearance did not survive a relaunch"
        )
        XCTAssertEqual(app.staticTexts["accentInUse"].label, "Olive")
        XCTAssertEqual(app.staticTexts["editorFontSpecimen"].value as? String, chosenFont)
    }

    /// The sheet the appearance is changed on is drawn in it too, while it is
    /// still up.
    ///
    /// A sheet is its own presentation: the appearance the window is asking
    /// for reaches it when it is put up, and an already-open one went on
    /// sitting there in the appearance it opened in. Which made *this* sheet
    /// the worst possible one to have it happen to — the control that had just
    /// been moved was on it, and nothing under the finger changed.
    ///
    /// Asked as a brightness, because there is no other way to ask a running
    /// app what colour scheme it is actually drawing in: an element that is
    /// dark grey on a dark page and light grey on a light one comes out of a
    /// screenshot as two very different numbers, and one that never followed
    /// comes out as the same one twice.
    func testTheSheetIsDrawnInTheAppearanceBeingChosenOnIt() throws {
        // Said rather than assumed, because Auto below is only worth asking
        // about against a device that is doing something known.
        XCUIDevice.shared.appearance = .light
        // Left light rather than unspecified, which the runner refuses:
        // light is what a simulator boots in, so this is putting it back.
        addTeardownBlock { XCUIDevice.shared.appearance = .light }

        let app = launchApp()
        openHowItLooks(in: app)
        let theme = app.segmentedControls["appearanceTheme"]

        theme.buttons["Dark"].tap()
        let inDark = try brightness(of: theme)

        theme.buttons["Light"].tap()
        let inLight = try brightness(of: theme)

        XCTAssertGreaterThan(
            inLight, inDark + 0.2,
            "the sheet did not follow the appearance — it was \(inDark) in dark "
                + "and \(inLight) in light, which is the same page twice"
        )

        // And back to Auto, which is the one of the three that is not an
        // instruction. The device is light, so the sheet has to be — and this
        // is the step that stays wrong longest, because "no preference" is not
        // the same as "light": a sheet told to be dark and then told nothing
        // goes on being dark.
        theme.buttons["Dark"].tap()
        _ = try brightness(of: theme)
        theme.buttons["Auto"].tap()
        let inAuto = try brightness(of: theme)

        XCTAssertGreaterThan(
            inAuto, inDark + 0.2,
            "the sheet stayed dark when the appearance went back to Auto on a "
                + "light device — it was \(inAuto), against \(inDark) in dark "
                + "and \(inLight) in light"
        )
    }

    /// The claim the identity's type scale is built on: chrome answers the
    /// system's text size, and the screen still holds together when the reader
    /// has turned it all the way up.
    ///
    /// Asked of the page the token layer is adopted on, because that is where
    /// there is something to ask it of. Two launches and not one — a size only
    /// means something against another size, and a page that ignored Dynamic
    /// Type entirely would pass every "is it on screen" check ever written.
    ///
    /// The overlap half is the part that a scale alone does not give you: a
    /// stack whose gaps are fixed while its labels have trebled is a stack
    /// whose sentence is sitting on top of the control above it, and it looks
    /// perfectly correct at the size it was designed at.
    func testTheAppearancePageHoldsTogetherAtTheLargestTextSize() throws {
        let atTheFactorySetting = launchApp()
        openHowItLooks(in: atTheFactorySetting)
        let smallPrint = atTheFactorySetting.staticTexts["appearanceIsDeviceLocal"]
        scrollTo(smallPrint, in: atTheFactorySetting)
        let ordinaryHeight = smallPrint.frame.height
        atTheFactorySetting.terminate()

        let app = launchApp(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openHowItLooks(in: app)

        // It grew. Measured on the smallest lettering on the page, because the
        // caption is the one a reader who needs this most cannot read, and the
        // one an app is likeliest to have pinned.
        let turnedUp = app.staticTexts["appearanceIsDeviceLocal"]
        scrollTo(turnedUp, in: app)
        XCTAssertGreaterThan(
            turnedUp.frame.height, ordinaryHeight,
            "the page's small print did not grow with the system text size — "
                + "it was \(ordinaryHeight) points tall and is now \(turnedUp.frame.height)"
        )

        // And nothing on it has climbed on top of anything else, or slid off
        // the side. Checked over what is on screen at each stop of a scroll
        // down the page, since an element that has not been scrolled to has no
        // frame worth comparing.
        // Named by what is in it rather than taken as the first one on screen:
        // this suite runs on iPad too, where the page is inside a form sheet
        // and "the first scroll view" is not a promise anybody made.
        let page = app.scrollViews.containing(.segmentedControl, identifier: "appearanceTheme")
            .firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the appearance page has no scroll view")
        page.swipeDown(velocity: .slow)

        for _ in 0..<4 {
            assertTheLayoutHolds(on: page)
            page.swipeUp(velocity: .fast)
        }
        assertTheLayoutHolds(on: page)
    }

    /// The other half of what S/M/L/XL is: a *writing* preference, so it moves
    /// the day's own words and nothing else on the screen.
    ///
    /// Asked of the Entry and not of the specimen on the settings page. The
    /// specimen shows what a step is worth; this is the claim the step is made
    /// for — that the words the user is actually writing came out the way they
    /// asked, and that the date over them did not move an inch.
    ///
    /// Measured on the prompt over an unwritten day, because that is the one
    /// thing on this screen drawn in the editor's own face that a running app
    /// can be asked the size of — a `UITextView`'s frame is the box it is in,
    /// not the type in it.
    ///
    /// The two controls are moved one at a time and not together. A sentence
    /// set bigger *and* in another face comes out a different width either
    /// way, and a single measurement of both says only that something reached
    /// the words.
    ///
    /// Measured after the sheet goes away, which is the one thing here that is
    /// not the claim: on a phone the sheet is full height, so there is no
    /// moment where the day and the control are both on screen to photograph.
    /// That a change lands at once rather than on dismissal is held where it
    /// is decided — `DeviceAppearance` publishes every choice as it is made
    /// and there is no apply step to defer it to (`AppearanceTests`, "the
    /// editor is told about a change the moment it is made").
    func testTheEditorsFaceAndSizeMoveTheDaysOwnWordsAndNoneOfTheChrome() throws {
        let app = launchApp()

        let daysWords = app.staticTexts["aBlankPage"]
        XCTAssertTrue(daysWords.waitForExistence(timeout: 30), "today's blank page never appeared")
        // The date over the entry: chrome, on screen beside the words the whole
        // time, so the two are asked the same question at the same moment.
        //
        // The pill and not a navigation title. The day's name is on the glass
        // now and the bar carries only the ways out of the day, so the pill is
        // what has to hold still — it is set in the system's text size, and the
        // writing's is none of its business.
        let chrome = app.buttons["datePill"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 10), "the day's date was never on screen")

        let asTheyCome = daysWords.frame
        let chromeAsItComes = chrome.frame

        // The size alone.
        openHowItLooks(in: app)
        app.segmentedControls["editorFontSize"].buttons["XL"].tap()
        backToTheDay(in: app)
        let atXL = daysWords.frame
        XCTAssertGreaterThan(
            atXL.height, asTheyCome.height,
            "the day's own words did not grow — they were \(asTheyCome.height) points tall "
                + "at M and are \(atXL.height) at XL"
        )

        // And the face alone, at the size just chosen — so what moves now is
        // the typeface and nothing else.
        openHowItLooks(in: app)
        app.segmentedControls["editorFontFamily"].buttons["Mono"].tap()
        backToTheDay(in: app)
        let inMono = daysWords.frame
        XCTAssertNotEqual(
            inMono.width, atXL.width,
            "the same sentence measures the same in mono as in sans — \(atXL.width) points "
                + "either way — so the face never reached the day's own words"
        )

        XCTAssertEqual(
            chrome.frame, chromeAsItComes,
            "the date over the entry moved with the editor's controls — it was at "
                + "\(chromeAsItComes) and is now at \(chrome.frame). Chrome follows the "
                + "system's text size, not the one the writing is set in"
        )
    }

    /// Out of the appearance page, off the journal sheet, and back to the day,
    /// where what was just chosen can be measured.
    ///
    /// Each step by name and never by position. While the sheet is up there
    /// are two navigation bars in the tree — the day's, behind it, and the
    /// sheet's own — so "the first button on the first bar" is a button on the
    /// wrong one: it opened the calendar on one device and dismissed the whole
    /// sheet on another, and neither left anything called Done to press.
    private func backToTheDay(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the appearance page had no way back")
        back.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the journal sheet had no way out")
        done.tap()

        XCTAssertTrue(
            app.staticTexts["aBlankPage"].waitForExistence(timeout: 10), "the day never came back"
        )
    }

    /// That everything the page is showing has a frame of its own: within the
    /// page's width, and touching nothing else's.
    ///
    /// Asked of the page rather than of the window, and of the leaves rather
    /// than of everything. Stacks are left out because a stack's frame is the
    /// union of what is in it and overlaps every one of them by definition,
    /// and the navigation bar is left out because scrolling content passing
    /// under a translucent bar is what a translucent bar is.
    ///
    /// Only the width is a containment claim. A page taller than the screen is
    /// what a scroll view is for — an element hanging off the bottom has been
    /// scrolled to, not clipped — but one hanging off the *side* has nowhere
    /// to go, and is the failure a fixed width causes when a label trebles.
    private func assertTheLayoutHolds(on page: XCUIElement) {
        let visible = page.frame
        // Every property read here is a round trip to the app under test, and
        // a screenful of them compared against each other is that squared. So
        // each frame is read exactly once, into a plain value, and the pairwise
        // arithmetic happens off the snapshot. The labels are never read at
        // all unless something fails — an assertion's message is an
        // autoclosure, so the element only gets asked what it says on the way
        // to a failure report.
        let laidOut =
            (page.staticTexts.allElementsBoundByIndex
            + page.segmentedControls.allElementsBoundByIndex
            + page.buttons.allElementsBoundByIndex)
            .map { (element: $0, frame: $0.frame) }
            .filter { !$0.frame.isEmpty }
            // Whatever is wholly on screen right now. One that is half
            // scrolled past has a frame the page is deliberately not showing
            // all of, and comparing it against its neighbour's says nothing.
            .filter { visible.minY <= $0.frame.minY && $0.frame.maxY <= visible.maxY }

        for element in laidOut {
            XCTAssertTrue(
                element.frame.minX >= visible.minX - 1 && element.frame.maxX <= visible.maxX + 1,
                "\"\(element.element.label)\" is at \(element.frame), off a page \(visible) wide"
            )
        }

        for (index, one) in laidOut.enumerated() {
            for other in laidOut.dropFirst(index + 1) {
                // One frame inside another is a thing inside its container —
                // a segmented control holds the three buttons it is made of —
                // and is the shape of correct nesting rather than of a
                // collision. What is being looked for is a *partial* overlap:
                // two things that were each laid out as though the other were
                // not there.
                //
                // Two points of slack and not one, because a container is not
                // always the larger of the two: UIKit draws a segment a point
                // taller than the control holding it, and a point of slack
                // then misses containment by the width of a rounding error —
                // which reads as a segmented control sitting on top of its own
                // "Sans". Nothing that is really two things laid out over each
                // other overlaps by only two points.
                let roomToSpare = one.frame.insetBy(dx: -2, dy: -2)
                guard
                    !roomToSpare.contains(other.frame),
                    !other.frame.insetBy(dx: -2, dy: -2).contains(one.frame)
                else { continue }
                // And a hair of tolerance on the rest: two adjacent rows whose
                // frames share an edge are laid out correctly, and
                // floating-point arithmetic makes a shared edge a half-point
                // overlap often enough.
                let shared = one.frame.intersection(other.frame)
                XCTAssertTrue(
                    shared.isNull || shared.width < 1 || shared.height < 1,
                    "\"\(one.element.label)\" at \(one.frame) is sitting on top of "
                        + "\"\(other.element.label)\" at \(other.frame)"
                )
            }
        }
    }

    /// The way in: the journal sheet, and the one row on it that is not about
    /// the journal.
    private func openHowItLooks(in app: XCUIApplication) {
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "the settings button never appeared")
        settings.tap()

        let howItLooks = app.buttons["openHowItLooks"]
        scrollTo(howItLooks, in: app)
        howItLooks.tap()

        XCTAssertTrue(
            app.segmentedControls["appearanceTheme"].waitForExistence(timeout: 10),
            "the appearance page never appeared"
        )
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func entryCountFromTheSettingsSheet(_ app: XCUIApplication) -> String {
        let settings = app.buttons["openSettings"]
        guard settings.waitForExistence(timeout: 30) else {
            return "the settings button never appeared"
        }
        settings.tap()

        let entryCount = app.staticTexts["journalEntryCount"]
        guard entryCount.waitForExistence(timeout: 5) else { return "no entry count was shown" }
        return entryCount.label
    }

    /// Opens the month on the date pill and steps it to the month a day is in.
    ///
    /// One step at most, because the days these tests are about are either
    /// side of today — and the step is needed at all only on the 1st and the
    /// last of a month, which is exactly when a calendar gets it wrong.
    ///
    /// Stepped by the name over the grid and not by counting from today: the
    /// pill opens over whichever day the app is *on*, and a test that has
    /// already picked one out of the grid is not where it started.
    private func openTheMonth(_ app: XCUIApplication, showing day: Date) {
        openTheDatePill(app, to: "Month")
        XCTAssertTrue(
            app.staticTexts["pillMonth"].waitForExistence(timeout: 10),
            "the month never came out of the pill"
        )

        // Which month is out is asked of the grid and not of the name over it.
        // The name is in the app's language and this test runs in the Mac's,
        // and the two are not the same machine's idea of August.
        //
        // The 15th of a month is on that month's grid and on no other: six
        // whole weeks reach at most five days into the month after and six
        // into the month before, so neither ever carries a 15th but its own.
        let middle = app.buttons["day-\(entryName(for: theMiddleOf(day)))"]
        guard !middle.exists else { return }

        // At most one step either way, because the days these tests are about
        // are either side of today — and a step is needed at all only on the
        // 1st and the last of a month, which is exactly when a calendar gets
        // it wrong.
        app.buttons["pillNextMonth"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        guard !middle.exists else { return }

        // And back past where it started, which is the other direction.
        app.buttons["pillPreviousMonth"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["pillPreviousMonth"].tap()
        XCTAssertTrue(
            middle.waitForExistence(timeout: 5),
            "the pill would not step to the month of \(entryName(for: day))"
        )
    }

    /// The 15th of the month a day falls in.
    private func theMiddleOf(_ day: Date) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month], from: day)
        parts.day = 15
        return Calendar.current.date(from: parts)!
    }

    /// Puts the calendar away, which is done by going back to the day's own
    /// words rather than by a button: the pill is over the page and not a
    /// screen on top of it.
    private func shutTheDatePill(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(app.buttons["datePill"], toHaveValue: "Closed")
    }

    /// Opens the date pill on the week or on the month, a tap at a time.
    private func openTheDatePill(_ app: XCUIApplication, to state: String) {
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")

        // Two taps at most: a shut pill opens on the week, and from there a
        // tap goes between the week and the month.
        for _ in 0..<3 where pill.value as? String != state {
            pill.tap()
            // Given the settle a moment to finish, so the next tap steps from
            // where this one left it rather than from mid-flight.
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertEqual(pill.value as? String, state, "the date pill would not open to \(state)")
    }

    /// Draws a finger across something — rightwards for a positive distance —
    /// and lets go.
    ///
    /// The wait is for the pages to land: the walk is only taken once the page
    /// being carried in has arrived, so a question asked before the snap has
    /// finished is asked of the page that is on its way out.
    private func swipe(_ element: XCUIElement, across distance: CGFloat) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(
            forDuration: 0.2,
            thenDragTo: from.withOffset(CGVector(dx: distance, dy: 0))
        )
        Thread.sleep(forTimeInterval: 1)
    }

    /// Draws a finger sideways across the shut date pill — rightwards for a
    /// positive distance — deliberately, and holds still before letting go.
    ///
    /// Held at the end because the app reads where the finger was *going* as
    /// well as where it got to, so that a flick turns the day. A synthesized
    /// drag that stops dead at its destination is still travelling as far as
    /// the gesture is concerned, and a test of the threshold asked with one
    /// would be asking about the harness's velocity rather than about the
    /// distance it was given.
    ///
    /// Begun at the pill's own middle, which is the middle of the screen: the
    /// pill is a couple of inches of glass, and a finger that started at its
    /// edge would spend half the swipe deciding whether it had begun on it.
    private func swipeTheDay(_ app: XCUIApplication, across distance: CGFloat) {
        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")
        XCTAssertEqual(pill.value as? String, "Closed", "the pill was not shut to be walked")

        let from = pill.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(
            // Moving from the first instant, because a scroll view delays
            // content touches: a finger that rests before it travels is handed
            // to whatever is under it, and a row that has taken the touch does
            // not give it back for a pan. On iPad, where the rows run wider,
            // that was every drag on the settings sheet doing nothing at all.
            forDuration: 0,
            thenDragTo: from.withOffset(CGVector(dx: distance, dy: 0)),
            withVelocity: .slow,
            thenHoldForDuration: 0.4
        )
        // The spring, and the day either side being opened behind it.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Draws a finger across the week strip, along the row a given day is on.
    ///
    /// Begun from a column of the *screen* rather than from that day's own
    /// cell, which is what this used to do. Today is whichever weekday it
    /// happens to be, and a swipe begun on the last column of an iPhone runs a
    /// hundred points off the side before it has gone far enough to turn a
    /// page — so the test passed all week and failed on Saturdays, and passed
    /// on the iPad every day because there the screen is wide enough to
    /// swallow it. Which cell the finger lands on does not matter: the gesture
    /// that walks the pages belongs to the panel and not to any day in it.
    private func swipeTheWeekStrip(
        _ app: XCUIApplication,
        alongside day: XCUIElement,
        across distance: CGFloat
    ) {
        let window = app.windows.firstMatch.frame
        let from = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: distance > 0 ? window.width * 0.2 : window.width * 0.8,
                    dy: day.frame.midY
                )
            )
        from.press(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: distance, dy: 0)))
        // The snap, and the page it lands on being taken.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Waits for something to become true, for the settle a swipe or a tap
    /// leaves behind.
    private func waitFor(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// Pulls something down (or up, for a negative distance) and lets go.
    private func drag(_ element: XCUIElement, by distance: CGFloat) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(
            forDuration: 0.2,
            thenDragTo: from.withOffset(CGVector(dx: 0, dy: distance))
        )
        // The spring, which the next assertion would otherwise catch part-way
        // through.
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Opens the search screen, and waits for it to be there.
    private func openSearch(_ app: XCUIApplication) {
        let search = app.buttons["openSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "the search button never appeared")
        search.tap()
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForExistence(timeout: 10),
            "the search screen never appeared"
        )
    }

    /// Types a query into the search field, as somebody looking for a day
    /// would.
    private func search(for query: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        field.tap()
        // Cleared first, so that a second search in one test is that search
        // and not the two queries run together.
        if let typed = field.value as? String, !typed.isEmpty, typed != field.placeholderValue {
            field.buttons.firstMatch.tap()
        }
        field.typeText(query)
    }

    /// Back up one screen — the way out of a day, and out of search.
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

    /// How bright something on screen came out, from 0 for black to 1 for
    /// white — the whole of it averaged, so it is the page it is on being
    /// asked about and not one pixel of it.
    ///
    /// Averaged by drawing it into a single grey pixel, which is what a
    /// downsample to one point is.
    private func brightness(of element: XCUIElement) throws -> Double {
        // The animation between two appearances, which a screenshot taken
        // mid-way through would catch half of.
        Thread.sleep(forTimeInterval: 1)

        let drawn = try XCTUnwrap(element.screenshot().image.cgImage)
        var grey: UInt8 = 0
        let onePixel = try XCTUnwrap(
            CGContext(
                data: &grey,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 1,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        )
        onePixel.interpolationQuality = .high
        onePixel.draw(drawn, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Double(grey) / 255
    }

    private func dayBeforeToday() -> Date? {
        daysBeforeToday(1)
    }

    /// A day far enough back to be somewhere a search is the way to: a journal
    /// with a past in it is what searching one is for.
    private func daysBeforeToday(_ days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    private func dayAfterToday() -> Date? {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())
    }

    /// Brings something into view in a sheet that scrolls.
    ///
    /// Steered rather than swiped at: the journal sheet is long, and on a
    /// small screen one full-speed swipe can carry the thing being looked for
    /// straight past the visible strip — after which a loop that only ever
    /// swipes one way is chasing it in the wrong direction. So each swipe asks
    /// where it has got to, and goes the way that closes the gap.
    ///
    /// Swiped on the scroll view and not on the screen, because an iPad
    /// presents this sheet as a form sheet with the app showing around it, and
    /// a gesture aimed at the screen is a gesture at whatever is behind.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) never appeared")

        let sheet = app.scrollViews.firstMatch
        let scroller = sheet.exists ? sheet : app

        // Where a tap on this element would actually land, which is the
        // question this helper is being asked — and not the same question as
        // `isHittable`. An element swiped a little past either end of a
        // scroll view goes on reporting itself hittable while it sits under
        // the navigation bar, or under the buttons pinned below it: the
        // element was found, and it was never touched. That surfaces several
        // lines later as "neither element nor any descendant has keyboard
        // focus", or as a switch that did not flip and so offered no time.
        //
        // Whether it happens at all depends on how far one swipe carries,
        // which is a property of the screen — so it can be true on the small
        // phone CI runs the suite on and false on every simulator here.
        //
        // The margin is two points and not a share of the height, and that is
        // the whole of the tuning. A swipe travels most of a screen, so a band
        // any narrower than the screen is a band a single swipe steps over —
        // and an element that is below the band, swiped, then above it, is an
        // element the loop puts back where it was, forever.
        func aTapWouldLand() -> Bool {
            let visible = scroller.frame.insetBy(dx: 0, dy: 2)
            return element.isHittable && visible.contains(
                CGPoint(x: element.frame.midX, y: element.frame.midY)
            )
        }

        // Flung while the element is more than a screen away, and dragged the
        // rest of the way in.
        //
        // A swipe hands the page momentum and lets the page decide where that
        // lands, which is fine while there is a content end to clamp against:
        // the clamp is what used to land an element sitting a few points under
        // the fold, and it is why this worked for as long as the settings
        // sheet was short. Add a row past the fold and nothing clamps — the
        // fling runs clean over the element, the loop brings it back, and
        // forty swipes later it is still going, two and a half minutes in and
        // nowhere. It happens on the small phone CI runs the suite on and on
        // no simulator here, which is the worst way to find it.
        //
        // A drag that holds before it lifts imparts no velocity at all: the
        // page stops where it was put (`scrollContent(of:by:)`). A step that
        // cannot overshoot cannot oscillate, so the close-in work is done with
        // those and the fling is left to cover ground.
        var moves = 0
        while !aTapWouldLand(), moves < 20 {
            let delta = scroller.frame.midY - element.frame.midY
            if abs(delta) > scroller.frame.height {
                if delta > 0 { scroller.swipeDown(velocity: .slow) }
                else { scroller.swipeUp(velocity: .slow) }
            } else if !scrollContent(of: scroller, in: app, by: delta) {
                // Nowhere on the page to begin a drag with room to run. One
                // fling and try again: it is the coarse instrument, but a
                // coarse move is better than the same refusal twenty times.
                if delta > 0 { scroller.swipeDown(velocity: .slow) }
                else { scroller.swipeUp(velocity: .slow) }
            }
            moves += 1
        }
        XCTAssertTrue(
            aTapWouldLand(),
            "\(element) never came into view — it is at \(element.frame), "
                + "and the sheet it is in is at \(scroller.frame)"
        )
    }

    /// Moves a scroll view's content by a chosen number of points, exactly —
    /// which the pill's own `drag(_:by:)` above is not for: that one pulls a
    /// thing and lets go, and this one is trying very hard not to let go.
    ///
    /// Pressed, dragged and then *held* before the finger lifts. The hold is
    /// the whole point: a gesture that lifts while still moving hands the page
    /// its speed and the page carries on, which is a swipe by another name.
    /// Held first, there is no speed to hand over, and the content stops where
    /// the drag put it.
    ///
    /// Begun somewhere the page will actually take it — see
    /// ``aClearPlaceToDragFrom(in:of:near:)``, which is most of the work — and
    /// carried only as far as there is room between that point and the edge it
    /// is heading for. A step too big to make in one is made in several: the
    /// caller is a loop.
    ///
    /// - Returns: whether it moved anything, so the caller can stop asking.
    @discardableResult
    private func scrollContent(
        of scroller: XCUIElement,
        in app: XCUIApplication,
        by delta: CGFloat
    ) -> Bool {
        let frame = scroller.frame
        // Away from the edge it is heading for, because that is where the room
        // to travel is.
        guard
            let from = aClearPlaceToDragFrom(in: scroller, of: app, near: delta < 0 ? 0.85 : 0.15)
        else { return false }
        let room =
            delta < 0
            ? from.screenPoint.y - frame.minY - 8
            : frame.maxY - from.screenPoint.y - 8
        guard room > 24 else { return false }

        let step = delta < 0 ? -min(room, -delta) : min(room, delta)
        from.press(
            forDuration: 0,
            thenDragTo: from.withOffset(CGVector(dx: 0, dy: step)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
        return true
    }

    /// Somewhere in a scroll view a drag can begin without a control taking it
    /// for itself.
    ///
    /// A gesture is delivered wherever it starts, and a text field claims a
    /// press-drag for its cursor: the page does not move however many times it
    /// is asked, and the keyboard that comes up is a second "Done" button on
    /// the screen for the next line of the test to find two of. A button or a
    /// row does *not* do this — a pan beginning over one is handed to the page,
    /// which is why swiping has always worked and why only the swipes are being
    /// replaced.
    ///
    /// So the ones that do are asked where they are, and the drag begins
    /// somewhere they are not: from the end it was asked for, then inwards.
    ///
    /// Nowhere at all is a real answer, and the caller flings instead. It
    /// happens on the settings sheet at the largest text size, where the
    /// fields are big enough to leave no band between them — and flinging is
    /// what carried that page before any of this, because the page is long
    /// enough that nothing there sits a few points under the fold.
    private func aClearPlaceToDragFrom(
        in scroller: XCUIElement,
        of app: XCUIApplication,
        near preferred: CGFloat
    ) -> XCUICoordinate? {
        let claimed =
            (app.textFields.allElementsBoundByIndex
                + app.secureTextFields.allElementsBoundByIndex
                + app.segmentedControls.allElementsBoundByIndex
                + app.sliders.allElementsBoundByIndex)
            .map { $0.frame }
        let frame = scroller.frame

        let bands = stride(from: 0.1, through: 0.9, by: 0.05)
            .map { CGFloat($0) }
            .sorted { abs($0 - preferred) < abs($1 - preferred) }
        let clear = bands.first { band in
            let point = CGPoint(x: frame.midX, y: frame.minY + frame.height * band)
            return !claimed.contains { $0.insetBy(dx: -4, dy: -4).contains(point) }
        }
        return clear.map { scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: $0)) }
    }

    /// Where today's photograph lands, said the way the Entry points at it —
    /// the default templates, two folders up and across.
    private func todaysPhotograph(named extension: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        return "../../attachments/\(formatter.string(from: Date()))"
            + "/\(todaysEntryName()).\(`extension`)"
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
