import UIKit
import XCTest

final class TheLayoutAndTheWalkTests: AujourUITestCase {

    // MARK: - The layout the window is wide enough for

    /// Aujour ships one app for iPhone and iPad, and the difference between
    /// them is not a difference between devices: above roughly 820 points of
    /// *window* the month lives in a sidebar and the day is set at a measure,
    /// and below it the date pill is the calendar — on an iPad in Slide Over
    /// exactly as on a phone.
    ///
    /// Which side of the line a given width falls on is `JournalLayout`, and
    /// it is decided against every window a real device hands the app there
    /// rather than here. What only a running app can show is the rest: that a
    /// sidebar is a way into a day, that the day beside it is set at a measure
    /// rather than stretched across the glass, and that a window resized past
    /// the line changes presentation without losing the day being written.
    ///
    /// Both presentations are asked for on both families. The suite cannot
    /// resize a window — an iPad's own widths are whichever iPad the runner
    /// had — so a test that is about one presentation says which one it means,
    /// and the one test that is about the crossing itself rotates the device,
    /// which is the one resize a UI test can perform.
    func testTheSidebarIsTheCalendarOnAWindowWithRoomForOne() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            layout: .sidebar,
            entries: "\(entryName(for: yesterday)) Walked to the harbour and back.\n"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")

        // The month is simply there, and the pill that a narrow window pulls
        // it out of is not: a pill over a sidebar already showing that month
        // is the calendar drawn twice.
        XCTAssertTrue(
            app.buttons["sidebarNextMonth"].waitForExistence(timeout: 15),
            "a window wide enough for a sidebar had no calendar in it"
        )
        XCTAssertFalse(
            app.buttons["datePill"].exists,
            "the date pill was still over a page with a sidebar calendar beside it"
        )

        // The day's words are beside the calendar rather than under it.
        XCTAssertGreaterThan(
            editor.frame.minX,
            0,
            "the day's words began at the window's edge, so nothing was beside them"
        )

        // And it is a way *into* a day, which is the whole of what the pill's
        // grid is for on a narrow window.
        showInTheSidebar(app, yesterday)
        let cell = app.buttons["day-\(entryName(for: yesterday))"]
        expect(cell, toHaveValue: "Written")
        cell.tap()

        let written = try XCTUnwrap(theWordsOnScreen(app, timeout: 15))
        XCTAssertTrue(
            written.contains("Walked to the harbour and back."),
            "the sidebar did not open the day it was tapped on, it opened: \(written)"
        )

        // And the pane names the day, the way the pill names it on a narrow
        // window: a filled cell in a grid is a day pointed at rather than a
        // day named, and an Entry is its date.
        let named = app.staticTexts["sidebarDay"]
        XCTAssertTrue(
            named.waitForExistence(timeout: 10),
            "nothing on screen said which day was being written"
        )
        XCTAssertFalse(named.label.isEmpty, "the calendar named no day at all")

        // The way back to today is the same way back it is on a phone, said
        // in the same word — and it is offered only once the journal is off
        // today, which is what makes it a way back rather than a badge.
        let today = app.buttons["backToToday"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "there was no way back to today")
        today.tap()
        XCTAssertTrue(
            today.waitForNonExistence(timeout: 10),
            "the way back to today was still offered from today"
        )
    }

    /// The other half of the sidebar layout: the day beside the calendar is
    /// *set* rather than stretched.
    ///
    /// How wide 65 characters of the reader's own face come out is measured
    /// headlessly, where a font can be asked; what only a running app can show
    /// is that the number reaches the page. Which needs a window with
    /// appreciably more room than a measure in it, and that is an iPad: at the
    /// default face 65 characters is around 550 points, so a thousand-point
    /// window whose day came out under 700 is one the cap reached, and one
    /// whose day filled the room would be over 800.
    func testTheDayBesideTheSidebarIsSetAtAMeasureRatherThanStretched() throws {
        let app = launchApp(layout: .sidebar)
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        // On its side, because that is the widest window any one device has —
        // and on a phone it is still not wide enough, which is what the skip
        // below says out loud rather than passing quietly.
        rotate(app, to: .landscapeLeft)
        try XCTSkipUnless(
            app.frame.width >= 1000,
            "this device's widest window is \(app.frame.width) points, which is a calendar and "
                + "a measure with nothing left over to cap"
        )

        XCTAssertLessThan(
            editor.frame.width,
            700,
            "the day's words were set \(editor.frame.width) points wide in a "
                + "\(app.frame.width)-point window, which is a stretched page and not a measure"
        )
    }


    /// The sidebar at the far end of Dynamic Type, where the month's name, the
    /// weekday initials and the sentence under the grid have all grown and the
    /// column has not.
    ///
    /// Seven columns is seven columns whatever the text size, so what a cell
    /// must never do is spill onto the day beside it or off the side of the
    /// calendar — and what the calendar must never do is take room off the
    /// page of words it is beside.
    func testTheSidebarHoldsTogetherAtTheLargestTextSize() throws {
        let app = launchApp(layout: .sidebar, textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        XCTAssertTrue(
            app.buttons["sidebarNextMonth"].waitForExistence(timeout: 15),
            "the sidebar calendar never appeared"
        )

        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-'"))
        XCTAssertGreaterThan(cells.count, 0, "the month had no days on it")

        for cell in cells.allElementsBoundByIndex {
            let frame = cell.frame
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                app.frame.minX - 0.5,
                "a day of the month hangs off the left of the screen: \(cell.label) at \(frame)"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                editor.frame.minX + 0.5,
                "a day of the month is over the page beside it: \(cell.label) at \(frame)"
            )
        }
    }

    /// The rule the whole feature is: which presentation the app is in follows
    /// the window it is in, and a window that changes width changes
    /// presentation under the same day.
    ///
    /// Unpinned, so the app measures a real window. Rotation is the resize —
    /// the only one a UI test can perform — and what it proves depends on the
    /// device, which is the point: an iPad mini crosses the line turning on
    /// its side, a phone stays on the page presentation both ways up because
    /// a landscape phone is wide enough for a sidebar and nowhere near tall
    /// enough for one, and a large iPad has room either way. Three different
    /// devices, one rule, read off the window every time.
    func testTheWindowDecidesWhichPresentationTheJournalIsReadIn() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(
            layout: nil,
            entries: "\(entryName(for: yesterday)) Stood in the hall with my coat on.\n"
        )
        XCTAssertTrue(
            app.textViews["entryEditor"].waitForExistence(timeout: 30),
            "today's entry never appeared"
        )
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        let started = presentationOf(app)
        XCTAssertEqual(
            started,
            presentationExpected(of: app),
            "a \(app.frame.size) window was read in the \(started) presentation"
        )

        // The day being written, before anything is resized — reached the way
        // whichever presentation is on screen reaches it.
        showTheMonth(app, containing: yesterday)
        app.buttons["day-\(entryName(for: yesterday))"].tap()
        let opened = try XCTUnwrap(theWordsOnScreen(app, timeout: 15))
        XCTAssertTrue(
            opened.contains("Stood in the hall with my coat on."),
            "the day picked out of the calendar never opened, the screen holds: \(opened)"
        )

        // The resize. Out and back, so the journal is asked the question in
        // both of the rooms this device has.
        rotate(app, to: .landscapeLeft)
        let sideways = presentationOf(app)
        XCTAssertEqual(
            sideways,
            presentationExpected(of: app),
            "a \(app.frame.size) window was read in the \(sideways) presentation"
        )

        rotate(app, to: .portrait)
        XCTAssertEqual(presentationOf(app), presentationExpected(of: app))

        // And the day survived both resizes, whether or not they crossed
        // anything: which day the journal is on is the calendar's, and the
        // calendar outlives a window.
        let survived = try XCTUnwrap(theWordsOnScreen(app, timeout: 15))
        XCTAssertTrue(
            survived.contains("Stood in the hall with my coat on."),
            "the day being written was lost across the resize, the screen holds: \(survived)"
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
        //
        // In one `typeText` and not two, because the pair is racing the
        // autosave: a second of quiet after a keystroke is a file, and two
        // separate calls are two rounds of event synthesis that a slow
        // runner holds more than a second apart — at which point the 'x' is
        // written, the delete writes the spawned words over it, and a day
        // this test is about to swear has no file has one. Sent together,
        // the keystrokes land milliseconds apart and the quiet never comes.
        editor.typeText("x" + XCUIKeyboardKey.delete.rawValue)
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
}
