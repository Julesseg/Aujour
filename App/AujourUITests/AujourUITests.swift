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

        // Asking iCloud for the app's container is slow the first time on a
        // device, so this is a wait rather than an assertion about a frame.
        let theJournal = app.buttons["openTheJournalSheet"]
        XCTAssertTrue(
            theJournal.waitForExistence(timeout: 30),
            "the app did not settle on a journal folder — it is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
        theJournal.tap()

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
        XCTAssertEqual(entryCountAfterOpeningTheJournalSheet(app), "0 entries")
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
        XCTAssertEqual(entryCountAfterOpeningTheJournalSheet(app), "1 entry")
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
        XCTAssertEqual(entryCountAfterOpeningTheJournalSheet(app), "1 entry")
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
        XCTAssertEqual(entryCountAfterOpeningTheJournalSheet(app), "1 entry")
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

        openTheJournalSheet(app)
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

        openCalendar(app, showingTheMonthOf: yesterday)
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

        openTheJournalSheet(app)
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
        openTheJournalSheet(app)
        let noTemplate = app.buttons["noContentTemplate"]
        scrollTo(noTemplate, in: app)
        noTemplate.tap()
        app.buttons["Done"].tap()
        expect(editor, toHaveValue: "")
    }

    func testTheRolloverHourChosenIsTheOneStillInForceAfterARelaunch() throws {
        let app = launchApp()
        openTheJournalSheet(app)

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
        openTheJournalSheet(app)
        let afterARelaunch = app.buttons["rolloverHour"]
        XCTAssertTrue(afterARelaunch.waitForExistence(timeout: 15), "settings never came back")
        // The end of the label rather than any of it: an hour that merely
        // appears in "When the day turns, 14:00" is not the hour it turns at.
        XCTAssertTrue(
            afterARelaunch.label.hasSuffix(", \(fourInTheMorning)"),
            "expected the day to still turn at \(fourInTheMorning), got \(afterARelaunch.label)"
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
        openCalendar(app, showingTheMonthOf: yesterday)

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
        openTheJournalSheet(app)
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
        openTheJournalSheet(app)
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
            app.staticTexts["parkedFileNames"].label.contains(parkedName),
            "the notice did not name \(parkedName): "
                + app.staticTexts["parkedFileNames"].label
        )

        // The Parked File is beside the journal and not in it: one day
        // written, one entry, whatever else is in the folder (ADR 0002).
        XCTAssertEqual(entryCountAfterOpeningTheJournalSheet(app), "1 entry")
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

        openTheJournalSheet(app)
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
        XCTAssertEqual(entryCountAfterOpeningTheJournalSheet(app), "1 entry")
        XCTAssertEqual(app.textFields["entryPathField"].value as? String, "[Journal]/YYYY-MM-DD")
    }

    func testSkippingTheMigrationLeavesTheOldFilesWhereTheyAreAndUnsurfaced() throws {
        let app = launchApp(todaysEntry: "Walked to the market.")
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )

        openTheJournalSheet(app)
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

        openTheJournalSheet(app)
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
        contentTemplate: String? = nil,
        folderToPick: String? = nil,
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
        placesAccess: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AUJOUR_UITEST_JOURNAL_FOLDER"] = journalFolder
        // Only when a test asks for one. Seeded on every launch, it would be
        // set again on the relaunch that is supposed to prove a template set
        // through the app is still there.
        if let contentTemplate {
            app.launchEnvironment["AUJOUR_UITEST_CONTENT_TEMPLATE"] = contentTemplate
        }
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
        app.launch()
        return app
    }

    /// Opens the one sheet: where the journal is kept, and every setting that
    /// shapes what goes into it.
    private func openTheJournalSheet(_ app: XCUIApplication) {
        let theJournal = app.buttons["openTheJournalSheet"]
        XCTAssertTrue(theJournal.waitForExistence(timeout: 30), "the journal never opened")
        theJournal.tap()
        XCTAssertTrue(
            app.staticTexts["journalRootLocation"].waitForExistence(timeout: 10),
            "the journal sheet never appeared"
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
    private func onTheClock(hour: Int) -> String {
        let midnight = Calendar.current.startOfDay(for: Date())
        let atThatHour =
            Calendar.current.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
        return atThatHour.formatted(date: .omitted, time: .shortened)
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

    private func entryCountAfterOpeningTheJournalSheet(_ app: XCUIApplication) -> String {
        let theJournal = app.buttons["openTheJournalSheet"]
        guard theJournal.waitForExistence(timeout: 30) else { return "the journal never opened" }
        theJournal.tap()

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
        var swipes = 0
        while !element.isHittable, swipes < 12 {
            if element.frame.minY < scroller.frame.minY {
                scroller.swipeDown(velocity: .slow)
            } else {
                scroller.swipeUp(velocity: .slow)
            }
            swipes += 1
        }
        XCTAssertTrue(
            element.isHittable,
            "\(element) never came into view — it is at \(element.frame), "
                + "and the sheet it is in is at \(scroller.frame)"
        )
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
