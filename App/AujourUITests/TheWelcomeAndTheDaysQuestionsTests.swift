import UIKit
import XCTest

// The first run, and the day's own questions: three welcome pages and out,
// the screens that say a journal is empty rather than showing it blank, and
// the placeholders a template leaves in the file — literal text until they
// are answered, the mood and the location among them.
final class TheWelcomeAndTheDaysQuestionsTests: AujourUITestCase {
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
        openTheJournalFolder(in: app)
        expect(app.staticTexts["journalEntryCount"], toBeShowing: "1 entry")
        backToTheSettings(in: app)
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
        closeSearch(app)

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
}
