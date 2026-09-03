import UIKit
import XCTest

/// The cockpit every test in this suite drives the app from: a journal folder
/// of the test's own, `launchApp(...)` with the keys that seed a day, and the
/// helpers that steer what only a running app can show.
///
/// One base class under several feature classes, and the split is not
/// housekeeping: xcodebuild runs UI tests in parallel a *class* at a time, so
/// a suite that was one class was a suite nothing could run beside. The
/// helpers all live here — even one only a single feature uses — because a
/// helper that moves in with its tests is a helper the next class grows its
/// own copy of.
class AujourUITestCase: XCTestCase {
    /// A folder of this test's own, so that one test's Entries are never the
    /// next one's journal. Reused by every launch within the test, which is
    /// how a relaunch is a relaunch and not a fresh install.
    var journalFolder = ""

    /// What the Files app calls Aujour's own on-device folder *here*. The app
    /// names it after the device it is running on, so spelling "iPhone" into
    /// the expectation made the suite assert that the iPad build was wrong.
    /// Read the same way the app reads it (`UIDevice.current.model`) — the
    /// runner is an app on the same device.
    var aujoursOwnFolder: String { "On My \(UIDevice.current.model) › Aujour" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        journalFolder = UUID().uuidString
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
    ///   - layout: which of the two presentations to pin this launch to —
    ///     ``Presentation/page``, which is what every test that is not about
    ///     the layout wants, or ``Presentation/sidebar``. `nil` lets the window
    ///     decide, which is what the app does for everybody who is not a test
    ///     and what the tests about the layout itself ask for.
    ///
    ///     Pinned by default because the suite cannot resize a window: an
    ///     iPad's own idea of how wide it is depends on which iPad the runner
    ///     happened to have, and a test about the date pill would pass on a
    ///     mini and fail on a Pro for a reason that has nothing to do with
    ///     what it is testing.
    func launchApp(
        layout: Presentation? = .page,
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
        // Which presentation this launch is in. Set for nearly every test,
        // and left to the window for the ones about the layout itself.
        if let layout {
            app.launchEnvironment["AUJOUR_UITEST_LAYOUT"] = layout.rawValue
        }
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
    func openSettings(_ app: XCUIApplication) {
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
    func tapTheOption(labelled label: String, in app: XCUIApplication) {
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
    func onTheClock(hour: Int) -> String {
        onTheClock(hour: hour, minute: 0)
    }

    /// A reminder's time as this device's clock writes it — measured off a day
    /// with no daylight saving in it, which is how the app writes one
    /// (`TimeOfDay.spelledOut`): a clock face is a clock face on the two days
    /// a year the local one has an hour missing.
    func onTheClock(hour: Int, minute: Int) -> String {
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
    func typeEntryPath(_ path: String, into app: XCUIApplication) {
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
    func replaceTheText(
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
    func giveTheKeyboardTo(_ field: XCUIElement, in app: XCUIApplication) {
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

    /// Puts the system share sheet away, whichever way this device offers.
    ///
    /// The Close button where the activity controller draws one, and a swipe
    /// down where it does not — the sheet is presented by SwiftUI and is
    /// dismissible either way, and which of them is on screen differs between
    /// the two device families the suite runs on.
    func dismissTheShareSheet(_ app: XCUIApplication) {
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

    /// Out of the appearance page, off the journal sheet, and back to the day,
    /// where what was just chosen can be measured.
    ///
    /// Each step by name and never by position. While the sheet is up there
    /// are two navigation bars in the tree — the day's, behind it, and the
    /// sheet's own — so "the first button on the first bar" is a button on the
    /// wrong one: it opened the calendar on one device and dismissed the whole
    /// sheet on another, and neither left anything called Done to press.
    func backToTheDay(in app: XCUIApplication) {
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
    func assertTheLayoutHolds(on page: XCUIElement) {
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
    func openHowItLooks(in app: XCUIApplication) {
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

    func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    func entryCountFromTheSettingsSheet(_ app: XCUIApplication) -> String {
        let settings = app.buttons["openSettings"]
        guard settings.waitForExistence(timeout: 30) else {
            return "the settings button never appeared"
        }
        settings.tap()

        // Waited on as long as the journal itself is. The count is not a
        // label the sheet draws and then fills in — it arrives with the
        // journal, which has to find its folder and read it before there is a
        // number to say, and after a relaunch that is a cold start. Five
        // seconds is a machine with the folder already warm; on a slow runner
        // it is the sheet being asked before the journal has answered, which
        // reads as "no entry count was shown" and is not what went wrong.
        let entryCount = app.staticTexts["journalEntryCount"]
        guard entryCount.waitForExistence(timeout: 30) else { return "no entry count was shown" }
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
    func openTheMonth(_ app: XCUIApplication, showing day: Date) {
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
    func theMiddleOf(_ day: Date) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month], from: day)
        parts.day = 15
        return Calendar.current.date(from: parts)!
    }


    /// Every day on the open month, as the rectangles they came out at.
    func theDaysOfTheMonth(in app: XCUIApplication) -> [CGRect] {
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-'"))
        XCTAssertGreaterThan(cells.count, 0, "the month had no days on it")
        return cells.allElementsBoundByIndex.map { $0.frame }
    }

    /// How much of the window the month takes, edge of the first day to edge
    /// of the last.
    func theSpanOfTheMonth(in app: XCUIApplication) -> CGFloat {
        let days = theDaysOfTheMonth(in: app)
        return days.map { $0.maxX }.max()! - days.map { $0.minX }.min()!
    }

    /// That no day of the month is wider than it is tall.
    ///
    /// Which is the whole of the cap, said as the thing it is for: a day is a
    /// square either because the pill was capped to make it one or because the
    /// window was too narrow for it ever to be anything else. Half a point of
    /// slack, because these are two sums of the same scaled numbers and a cell
    /// exactly on the line has met it.
    func assertTheDaysAreNotSpreadOut(
        in app: XCUIApplication,
        line: UInt = #line
    ) {
        for day in theDaysOfTheMonth(in: app) {
            XCTAssertLessThanOrEqual(
                day.width,
                day.height + 0.5,
                "a day came out \(day.width) wide and \(day.height) tall, which is a number "
                    + "adrift in a column rather than a day on a grid",
                line: line
            )
        }
    }

    // MARK: - Which presentation the app is in

    /// One of Aujour's two layouts, as this suite talks about them.
    ///
    /// A type of its own rather than the two strings it is spelled with,
    /// because the strings are load-bearing in two directions at once — they
    /// are what a launch is pinned with and what a screen is read back as —
    /// and a typo in either is a test that quietly asks the wrong question.
    /// Declared here rather than imported: this suite drives the app from
    /// another target and imports nothing from it, the same way it spells out
    /// every launch key.
    enum Presentation: String {
        case page
        case sidebar

        /// What no presentation at all looks like, which is a screen that has
        /// neither a date pill nor a calendar on it. Never expected, and worth
        /// being able to name when a test fails.
        case neither
    }

    /// Which of the two is on screen, read off the one control that only that
    /// presentation has.
    func presentationOf(_ app: XCUIApplication) -> Presentation {
        // A short wait and not the usual long one: this is only ever asked of
        // an app that is already up and has already been laid out, and the
        // answer where there is no sidebar is a wait spent finding that out.
        if app.buttons["sidebarNextMonth"].waitForExistence(timeout: 5) { return .sidebar }
        if app.buttons["datePill"].exists { return .page }
        return .neither
    }

    /// Which one this window should be in, worked out from its shape the same
    /// way the app works it out — the *window's* shape, which is what
    /// `XCUIApplication.frame` is.
    ///
    /// Both measurements, because a sidebar needs both: a phone on its side
    /// clears the width and misses the height by four hundred points, which is
    /// the case a width alone gets wrong.
    ///
    /// The numbers are spelled out rather than shared, like every other
    /// constant in this suite: the UI target imports nothing from the app it
    /// drives, so a threshold that moved in `JournalLayout` and not here is a
    /// suite that says so.
    func presentationExpected(of app: XCUIApplication) -> Presentation {
        app.frame.width >= 820 && app.frame.height >= 600 ? .sidebar : .page
    }

    /// Turns the device, and waits for the app to have been laid out again.
    ///
    /// The wait is not politeness: a rotation is delivered over more than one
    /// frame, and a question asked in the middle of one is asked of a window
    /// that is neither width.
    func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        let before = app.frame.width
        XCUIDevice.shared.orientation = orientation

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, app.frame.width == before {
            Thread.sleep(forTimeInterval: 0.25)
        }
        // And a moment past the resize itself, for whatever the presentation
        // change puts on screen to have arrived.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Puts a day's month on screen, whichever presentation the app is in.
    ///
    /// The two calendars are reached differently — one has to be pulled open
    /// and the other is simply there — and every test above this one is about
    /// something else.
    func showTheMonth(_ app: XCUIApplication, containing day: Date) {
        if presentationOf(app) == .sidebar {
            showInTheSidebar(app, day)
        } else {
            openTheMonth(app, showing: day)
        }
    }

    /// Brings a day onto the sidebar's grid, stepping a month if it is not
    /// already there.
    ///
    /// A step is needed only at the turn of a month, and at most one: the grid
    /// is six whole weeks, so it carries the tail of the month before and the
    /// head of the month after.
    func showInTheSidebar(_ app: XCUIApplication, _ day: Date) {
        XCTAssertTrue(
            app.buttons["sidebarNextMonth"].waitForExistence(timeout: 30),
            "the sidebar calendar never appeared"
        )
        let cell = app.buttons["day-\(entryName(for: day))"]
        guard !cell.waitForExistence(timeout: 10) else { return }

        app.buttons["sidebarPreviousMonth"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        guard !cell.exists else { return }

        app.buttons["sidebarNextMonth"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["sidebarNextMonth"].tap()
        XCTAssertTrue(
            cell.waitForExistence(timeout: 5),
            "\(entryName(for: day)) was not on the sidebar's grid, a month either side of it"
        )
    }

    /// What the day on screen says — the editor's own text, once there is an
    /// editor to read it off.
    func theWordsOnScreen(_ app: XCUIApplication, timeout: TimeInterval) -> String? {
        let editor = app.textViews["entryEditor"]
        guard editor.waitForExistence(timeout: timeout) else { return nil }

        // The day is opened and then read, and reading a file is not instant:
        // an editor asked the moment it appears answers with the empty page it
        // came up as.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, (editor.value as? String).map(\.isEmpty) != false {
            Thread.sleep(forTimeInterval: 0.25)
        }
        return editor.value as? String
    }

    /// Puts the calendar away, which is done by going back to the day's own
    /// words rather than by a button: the pill is over the page and not a
    /// screen on top of it.
    func shutTheDatePill(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(app.buttons["datePill"], toHaveValue: "Closed")
    }

    /// Opens the date pill on the week or on the month, a tap at a time.
    func openTheDatePill(_ app: XCUIApplication, to state: String) {
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
    func swipe(_ element: XCUIElement, across distance: CGFloat) {
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
    func swipeTheDay(_ app: XCUIApplication, across distance: CGFloat) {
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
    func swipeTheWeekStrip(
        _ app: XCUIApplication,
        alongside day: XCUIElement,
        across distance: CGFloat
    ) {
        // Started against the grid and not against the window, because the two
        // are not the same width: the open pill is capped at seven square
        // columns, so on any window with room to spare it is a pane in the
        // middle with page either side of it. A finger that began a fifth of
        // the way across an iPad would begin on the page, where a walk is not
        // a walk at all.
        //
        // A sixth of the way in from the near end, which is far enough onto
        // the glass that the gesture is unambiguously the grid's. Where it
        // *ends* does not matter — a drag that began on the grid goes on being
        // the grid's wherever the finger travels.
        let days = theDaysOfTheMonth(in: app)
        let grid = (near: days.map(\.minX).min()!, far: days.map(\.maxX).max()!)
        let inset = (grid.far - grid.near) / 6
        let from = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: distance > 0 ? grid.near + inset : grid.far - inset,
                    dy: day.frame.midY
                )
            )
        from.press(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: distance, dy: 0)))
        // The snap, and the page it lands on being taken.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Waits for something to become true, for the settle a swipe or a tap
    /// leaves behind.
    func waitFor(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// Pulls something down (or up, for a negative distance) and lets go.
    func drag(_ element: XCUIElement, by distance: CGFloat) {
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
    func openSearch(_ app: XCUIApplication) {
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
    func search(for query: String, in app: XCUIApplication) {
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
    func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Waits for an element to say something. The folder is read after the
    /// words are saved, so an indicator arrives a moment after the day it
    /// belongs to has been written in.
    ///
    /// Polled rather than awaited on an `XCTestExpectation`: waiting on one
    /// hands the test case itself to the main actor, and a test case is not
    /// `Sendable`.
    func expect(
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
    func expect(
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
    func brightness(of element: XCUIElement) throws -> Double {
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

    func dayBeforeToday() -> Date? {
        daysBeforeToday(1)
    }

    /// A day far enough back to be somewhere a search is the way to: a journal
    /// with a past in it is what searching one is for.
    func daysBeforeToday(_ days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    func dayAfterToday() -> Date? {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())
    }

    /// A numbered day of the month the date pill opens onto.
    ///
    /// Every day of the month is on its own grid however far into the month
    /// today is — which a day counted back from today is not, since the grid
    /// reaches back only as far as the week the 1st falls in.
    func dayOfTheMonthOnScreen(_ day: Int) -> Date? {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month], from: Date())
        parts.day = day
        return calendar.date(from: parts)
    }

    /// Brings something into view in a sheet that scrolls.
    ///
    /// Steered rather than swiped at: the journal sheet is long, and on a
    /// small screen one full-speed swipe can carry the thing being looked for
    /// straight past the visible strip — after which a loop that only ever
    /// swipes one way is chasing it in the wrong direction. So each move asks
    /// where it has got to, and goes the way that closes the gap.
    ///
    /// Swiped on the scroll view and not on the screen, because an iPad
    /// presents this sheet as a form sheet with the app showing around it, and
    /// a gesture aimed at the screen is a gesture at whatever is behind.
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
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

        // Flung while the element is far away — until the first overshoot,
        // and never again after it.
        //
        // Both halves are earned. A swipe hands the page momentum and lets
        // the page decide where that lands, and how far a slow swipe carries
        // is a property of the simulator's frame timing: on the small phone
        // CI runs the suite on it carries more than the whole sheet, so an
        // element more than a sheet-height below, flung at, comes out more
        // than a sheet-height *above* — and a loop that flings whenever the
        // element is far spends its whole budget of moves batting it back
        // and forth over the visible strip and never once through it. That
        // is the oscillation: the moment a fling can outrun its own distance
        // threshold, "far enough to fling at" and "far enough to overshoot
        // from" are the same distance.
        //
        // But dragging the whole way is not the answer either. A drag is
        // clamped to the room inside the sheet, and at the largest text size
        // the sheet is three hundred points tall with the element nine
        // thousand points down — each drag lands exactly where it was sent,
        // and the loop still runs out of moves a sheet's-length of content
        // short. So the fling covers the ground, and the sign of the gap is
        // watched: the first time it flips, the fling has shown what it does
        // on this machine and is retired, and the held drags of
        // `scrollContent(of:by:)` — no momentum, no overshoot — close the
        // one bounce that remains. Thirty moves, not twenty, because the
        // bounce can happen at the end of the longest sheet, and the drags
        // that clean it up are moves the flings did not have to spend.
        var moves = 0
        var wasBelow: Bool?
        var flingIsTrusted = true
        while !aTapWouldLand(), moves < 30 {
            let delta = scroller.frame.midY - element.frame.midY
            if let below = wasBelow, below != (delta < 0) { flingIsTrusted = false }
            wasBelow = delta < 0
            if flingIsTrusted, abs(delta) > scroller.frame.height {
                if delta > 0 { scroller.swipeDown(velocity: .slow) }
                else { scroller.swipeUp(velocity: .slow) }
            } else if !scrollContent(of: scroller, in: app, by: delta) {
                // Nowhere on the page to begin a drag with room to run. One
                // fling and try again: it is the coarse instrument, but a
                // coarse move is better than the same refusal thirty times.
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
    func scrollContent(
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
    func aClearPlaceToDragFrom(
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
    func todaysPhotograph(named extension: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        return "../../attachments/\(formatter.string(from: Date()))"
            + "/\(todaysEntryName()).\(`extension`)"
    }

    /// The name a day's Entry file carries under the default Path Template —
    /// what `{{title}}` resolves to, and what the calendar names its cells by.
    func entryName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func todaysEntryName() -> String {
        entryName(for: Date())
    }
}
