import UIKit
import XCTest

final class TheDatePillTests: AujourUITestCase {

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

    /// A day scrolled up goes behind the pill rather than stopping at it — and
    /// its first line still rests clear of the glass while it is at rest.
    ///
    /// The pill is glass, and glass over a page that ended where the glass
    /// began has nothing to refract: a reader scrolling a long day up would
    /// watch the words meet a hard edge and vanish.
    ///
    /// Asked of the screen and not of the tree, because the tree cannot answer
    /// it: a text view laid out up under the pill reports the same frame
    /// whether the words up there are drawn or clipped away, and clipped away
    /// is exactly what they were. What is looked at is the strip of row
    /// between the pill and the menu beside it — page, at rest, and full of
    /// the words going past once the day has been scrolled.
    func testADayScrolledUpGoesBehindThePillsGlass() throws {
        let words = (1...80)
            .map { "Line \($0) — the quick brown fox jumps over the lazy dog." }
            .joined(separator: "\n")
        let app = launchApp(todaysEntry: words + "\n")

        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        let more = app.buttons["moreActions"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the menu never appeared")

        XCTAssertLessThan(
            editor.frame.minY, pill.frame.minY,
            "the page begins below the pill rather than running up behind it — "
                + "the page is at \(editor.frame) and the pill at \(pill.frame)"
        )

        // Two strips of the top of the screen, and the day has to reach both:
        // the pill's own row, between the pill and the menu, and the band
        // above the pill, which is the status bar's.
        let alongsideThePill = CGRect(
            x: pill.frame.maxX + 4,
            y: pill.frame.minY,
            width: more.frame.minX - pill.frame.maxX - 8,
            height: pill.frame.height
        )
        let aboveThePill = CGRect(
            x: app.frame.width * 0.3,
            y: 0,
            width: app.frame.width * 0.3,
            height: pill.frame.minY - 2
        )

        let besideAtRest = inkAcross(alongsideThePill, of: app)
        XCTAssertLessThan(
            besideAtRest, 0.02,
            "something is drawn beside the pill on a day at its top — \(besideAtRest) of it"
        )
        // Nothing is asked of the band above the pill at rest, because what is
        // up there is not the app's: a phone with a Dynamic Island puts the
        // clock off to one side and this band is empty, and one without puts
        // it in the middle and this band is the clock. What both have in
        // common is that the clock does not move when the day does — so what
        // the day reaching up there looks like is the *difference*, and the
        // reading at rest is the ground it is measured from.
        let aboveAtRest = inkAcross(aboveThePill, of: app)

        _ = scrollContent(of: editor, in: app, by: -140)

        let besideScrolled = inkAcross(alongsideThePill, of: app)
        XCTAssertGreaterThan(
            besideScrolled, 0.05,
            "the day stopped at the pill rather than going up behind it: the row "
                + "beside the pill is still bare — \(besideScrolled) of it is ink"
        )
        let aboveScrolled = inkAcross(aboveThePill, of: app)
        XCTAssertGreaterThan(
            aboveScrolled - aboveAtRest, 0.05,
            "the day stopped under the status bar rather than running up behind "
                + "it — the band above the pill went from \(aboveAtRest) ink to "
                + "\(aboveScrolled), and scrolling a day through it should put "
                + "far more there than that"
        )
    }

    /// The first line of a day rests clear of the glass, so that a day nobody
    /// has scrolled reads as a page and not as words half under a pane.
    ///
    /// The invitation over a day nobody has written stands in for that first
    /// character: it is drawn exactly where the typing will start
    /// (``MarkdownEditor/whereTheFirstCharacterGoes``), which makes it the one
    /// thing on an empty page whose position can be asked for.
    func testTheFirstLineOfADayRestsClearOfThePill() throws {
        let app = launchApp()

        let pill = app.buttons["datePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the journal never opened")

        let invitation = app.staticTexts["aBlankPage"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 30), "the empty day said nothing")
        XCTAssertGreaterThan(
            invitation.frame.minY, pill.frame.maxY,
            "the day's first line is under the glass at rest — "
                + "it is at \(invitation.frame) and the pill at \(pill.frame)"
        )
    }

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
        // Two days of the month the grid opens onto, rather than two counted
        // back from today. The grid reaches back only as far as the week the
        // 1st falls in, so a day two back from today is on the month before's
        // grid for the first two days of every month — which is a test that
        // fails on the 1st and the 2nd and nowhere else.
        //
        // The 1st for the day that was written, because it is the one day of
        // the month that is never in the future, so a folder holding it is a
        // folder somebody could have written. The 2nd needs no such care: a
        // day nobody has written is unwritten whether or not it has arrived.
        let written = try XCTUnwrap(dayOfTheMonthOnScreen(1))
        let unwritten = try XCTUnwrap(dayOfTheMonthOnScreen(2))
        let app = launchApp(
            entries: "\(entryName(for: written)) Walked to the market with Robin."
        )

        openTheDatePill(app, to: "Month")

        expect(app.buttons["day-\(entryName(for: written))"], toHaveValue: "Written")
        expect(
            app.buttons["day-\(entryName(for: unwritten))"],
            toHaveValue: "Not written"
        )
    }

    /// The one thing in Aujour that takes a day out of the folder, driven the
    /// way anybody would find it: hold a day that has something on it.
    ///
    /// The mark is what is asserted afterwards and not the file, because the
    /// mark is a scan of the folder and nothing else (ADR 0001) — a day that
    /// reads "Not written" on a grid the app has just re-read is a day whose
    /// file is gone.
    func testAWrittenDayIsDeletedByHoldingItOnTheDatePill() throws {
        // The 1st, for the reason the marks test picks it: it is the one day
        // of the month that is never in the future, so a folder holding it is
        // a folder somebody could have written.
        let written = try XCTUnwrap(dayOfTheMonthOnScreen(1))
        let app = launchApp(
            entries: "\(entryName(for: written)) Walked to the market with Robin."
        )

        openTheMonth(app, showing: written)
        let cell = app.buttons["day-\(entryName(for: written))"]
        expect(cell, toHaveValue: "Written")

        deleteTheEntry(on: cell, in: app)

        expect(cell, toHaveValue: "Not written")
        // And the month is still out: deleting a day is not choosing one, so
        // there is nothing for the pill to have shut itself over.
        expect(app.buttons["datePill"], toHaveValue: "Month")
    }

    /// The other half of the same offer: a day nobody wrote has nothing to
    /// delete, so holding it asks nothing rather than putting up a button that
    /// would do nothing.
    func testHoldingADayNobodyWroteOffersNothing() throws {
        let written = try XCTUnwrap(dayOfTheMonthOnScreen(1))
        let unwritten = try XCTUnwrap(dayOfTheMonthOnScreen(2))
        let app = launchApp(
            entries: "\(entryName(for: written)) Walked to the market with Robin."
        )

        openTheMonth(app, showing: unwritten)
        let cell = app.buttons["day-\(entryName(for: unwritten))"]
        expect(cell, toHaveValue: "Not written")

        cell.press(forDuration: 1.0)

        XCTAssertFalse(
            app.buttons["confirmDeleteEntry"].firstMatch.waitForExistence(timeout: 3),
            "a day with no entry offered to delete one"
        )
        // What the press did instead is what the tap at the end of it does:
        // it opened the day. Nothing came up to swallow that tap, because
        // there was nothing to ask about — so a finger held on a day with
        // nothing to delete lands on the day rather than on a button saying
        // no, which is the right dead end to have.
        XCTAssertTrue(
            app.buttons["backToToday"].waitForExistence(timeout: 10),
            "holding a day with nothing to delete neither asked anything nor opened it"
        )
        expect(app.buttons["datePill"], toHaveValue: "Closed")
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



    /// A pill is a pane sized to the room it is in, and the room it is in is
    /// not always a phone's: everything below the sidebar threshold gets one,
    /// which runs from Slide Over to an iPad mini stood up. A month grid
    /// stretched across the wide end of that is a week of Tuesdays with a
    /// hand's width between them, so the open pill stops growing well before
    /// the window does.
    ///
    /// Asserted as the thing the cap is *for* rather than as the number it is:
    /// a day may be half again as wide as it is tall and no wider. That holds
    /// on every window, so it needs no device to be true on — and on a narrow
    /// one it is true for the other reason, which is that there was never room
    /// to spread.
    func testTheOpenPillDoesNotSpreadItsDaysAcrossAWideWindow() throws {
        let app = launchApp(layout: .page)
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        openTheMonth(app, showing: Date())
        assertTheDaysAreNotSpreadOut(in: app)

        // And on its side, which is the widest window any one device has and
        // so the one the cap is really for. Pinned to the page presentation,
        // because a window this wide would otherwise have a sidebar and no
        // pill at all.
        rotate(app, to: .landscapeLeft)
        openTheMonth(app, showing: Date())
        assertTheDaysAreNotSpreadOut(in: app)

        // The grid stops well short of the glass it is on. Half is a generous
        // line — a square month is 324 points at the factory text size, which
        // is well under half of any window wide enough to be worth capping —
        // drawn where it cannot be met by a month that merely has margins.
        let span = theSpanOfTheMonth(in: app)
        XCTAssertLessThan(
            span,
            app.frame.width * 0.5,
            "the month spanned \(span) of a \(app.frame.width)-point window, which is a grid "
                + "stretched to the glass rather than a calendar"
        )
    }

    /// A window that changes size puts the pill away.
    ///
    /// On *any* resize and not only on one that crosses the threshold: the
    /// pill is sized to the room it is in, and a window dragged narrower under
    /// an open one is a month relaying itself out under the finger that opened
    /// it. Pinned to the page presentation so that this is the resize being
    /// asked about and not the crossing — which is a resize too, and is
    /// covered where the presentations are.
    func testTheDatePillIsPutAwayWhenTheWindowIsResized() throws {
        let app = launchApp(layout: .page)
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        openTheDatePill(app, to: "Month")
        rotate(app, to: .landscapeLeft)

        expect(app.buttons["datePill"], toHaveValue: "Closed")
    }
}
