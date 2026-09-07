import XCTest

// The Frontmatter above the day. Obsidian's rule for reading one, what each
// control writes and what it leaves alone are Core's and tested there against
// the text; what only a running app can show is that the block is cut off the
// body and shown as Properties, that a control reaches the file through the
// same autosave a keystroke does, and that fences typed by hand become a
// section once the caret has left them.
final class TheFrontmatterTests: AujourUITestCase {
    /// A seeded day with a block opens on its Properties, with the body and
    /// only the body in the text view.
    func testADayWithAFrontmatterShowsItsPropertiesAboveTheBody() throws {
        let app = launchApp(
            todaysEntry: "---\nmood: 7\ndone: false\ntags: [walk, market]\n---\n# A walk\n"
        )

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        expect(editor, toHaveValue: "# A walk\n", timeout: 30)

        XCTAssertTrue(app.otherElements["frontmatterSection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["propertyNumber-mood"].exists, "mood should be a number field")
        XCTAssertEqual(app.textFields["propertyNumber-mood"].value as? String, "7")
        XCTAssertTrue(app.switches["propertyToggle-done"].exists, "done should be a toggle")
        XCTAssertTrue(app.staticTexts["walk"].exists, "the list's items should be chips")
        XCTAssertTrue(app.staticTexts["market"].exists)

        // The control for a day with none is not on a day with one.
        XCTAssertFalse(app.buttons["addFirstProperty"].exists)
    }

    /// A toggle flip rewrites one line of the file, and the rest of it —
    /// the body and the other Properties — stays as it was.
    ///
    /// Typed rather than seeded, because a file the launch environment seeds
    /// is seeded again on the next launch — and this test is about what
    /// survives one.
    func testFlippingAToggleRewritesOneLineOfTheFile() throws {
        let app = launchApp()
        let editor = typeADay("---\nMood: 7\nDone: false\n---\n# A walk", into: app)

        let toggle = app.switches["propertyToggle-Done"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the toggle never appeared")
        expect(toggle, toHaveValue: "0")
        toggle.tap()
        expect(toggle, toHaveValue: "1")

        // The source is the block's own characters, and shows the one line
        // that changed.
        app.buttons["frontmatterSourceToggle"].tap()
        let source = app.textViews["frontmatterSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        expect(source, toHaveValue: "---\nMood: 7\nDone: true\n---")
        expect(editor, toHaveValue: "# A walk")

        // And the file has it, after the autosave nobody asked for.
        Thread.sleep(forTimeInterval: 4)
        relaunch(app)
        let reopened = app.switches["propertyToggle-Done"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 30))
        XCTAssertEqual(reopened.value as? String, "1")
        XCTAssertEqual(app.textFields["propertyNumber-Mood"].value as? String, "7")
        expect(app.textViews["entryEditor"], toHaveValue: "# A walk", timeout: 30)
    }

    /// The source is edited as text, and leaving it reads the block again:
    /// a Property typed into the source is a row afterwards.
    func testTheSourceRoundTripsIntoProperties() throws {
        let app = launchApp(todaysEntry: "---\nmood: 7\n---\nbody\n")

        let toggle = app.buttons["frontmatterSourceToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "the source toggle never appeared")
        toggle.tap()

        let source = app.textViews["frontmatterSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        expect(source, toHaveValue: "---\nmood: 7\n---")

        // The whole block replaced, because the caret is wherever the tap put
        // it and a test that typed at it would be a test of where that was.
        source.tap()
        selectAll(in: source, app: app)
        source.typeText("---\nmood: 7\ndone: true\n---")
        expect(source, toHaveValue: "---\nmood: 7\ndone: true\n---")

        toggle.tap()
        XCTAssertTrue(app.switches["propertyToggle-done"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["propertyToggle-done"].value as? String, "1")
        XCTAssertEqual(app.textFields["propertyNumber-mood"].value as? String, "7")
        expect(app.textViews["entryEditor"], toHaveValue: "body\n")
    }

    /// Fences and a Property typed at the top of a day that had none are a
    /// Frontmatter by the rule: held in the body while the caret is in them,
    /// and lifted into the section once it has left.
    ///
    /// Every line starts with a capital the test typed itself, so that
    /// autocapitalisation has nothing it could change.
    func testABlockTypedByHandLiftsIntoTheSection() throws {
        let app = launchApp()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()
        editor.typeText("---\nMood: 7\n---\n")

        // Still in the body: the caret is on the line the closing fence's
        // return opened, which is where somebody about to write is.
        expect(editor, toHaveValue: "---\nMood: 7\n---\n")
        XCTAssertFalse(app.otherElements["frontmatterSection"].exists)

        // The first word of the body takes the caret past the block.
        editor.typeText("Hello")
        XCTAssertTrue(app.otherElements["frontmatterSection"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["propertyNumber-Mood"].value as? String, "7")
        expect(editor, toHaveValue: "Hello")

        Thread.sleep(forTimeInterval: 4)
        relaunch(app)
        XCTAssertTrue(app.textFields["propertyNumber-Mood"].waitForExistence(timeout: 30))
        expect(app.textViews["entryEditor"], toHaveValue: "Hello", timeout: 30)
    }

    /// A day with no block has the small control above the text, in the
    /// accessibility tree the whole time and reached by scrolling up past the
    /// top — and adding through it asks the kind and makes the block.
    ///
    /// Seeded rather than typed, because the control is reached by pulling
    /// the page down, and a page with the keyboard in it is pulled by the
    /// caret instead. What reaches the file from here is what every other
    /// Property edit reaches it through, and the toggle's test relaunches.
    func testTheDiscreetControlAddsAFirstProperty() throws {
        let app = launchApp(todaysEntry: "Just words.\n")

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        expect(editor, toHaveValue: "Just words.\n", timeout: 30)

        let control = app.buttons["addFirstProperty"]
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the control should always be in the tree")
        XCTAssertFalse(control.isHittable, "the control should be tucked above the top at rest")
        XCTAssertFalse(app.otherElements["frontmatterSection"].exists)

        // Pulled into view by scrolling up past the top of the text.
        drag(editor, by: 160)
        XCTAssertTrue(control.isHittable, "the control never came into view")
        control.tap()
        tapTheOption(labelled: "Checkbox", in: app)

        let name = app.textFields["newPropertyKey"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "no row appeared for the new Property")
        XCTAssertFalse(app.switches["propertyToggle-done"].exists, "nothing is written until it is named")
        name.typeText("done\n")

        XCTAssertTrue(app.switches["propertyToggle-done"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["propertyToggle-done"].value as? String, "0")
        expect(editor, toHaveValue: "Just words.\n")

        app.buttons["frontmatterSourceToggle"].tap()
        let source = app.textViews["frontmatterSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        expect(source, toHaveValue: "---\ndone: false\n---")
    }

    /// The block goes with its last Property, fences included, and the
    /// discreet control is back.
    func testDeletingTheLastPropertyTakesTheBlockWithIt() throws {
        let app = launchApp()
        let editor = typeADay("---\nMood: 7\n---\nBody", into: app)

        let row = app.otherElements["property-Mood"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the row never appeared")
        row.swipeLeft()

        let delete = app.buttons["deleteProperty-Mood"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "swiping did not reveal the delete")
        delete.tap()

        XCTAssertTrue(app.otherElements["frontmatterSection"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["addFirstProperty"].waitForExistence(timeout: 10))
        expect(editor, toHaveValue: "Body")

        Thread.sleep(forTimeInterval: 4)
        relaunch(app)
        expect(app.textViews["entryEditor"], toHaveValue: "Body", timeout: 30)
        XCTAssertFalse(app.otherElements["frontmatterSection"].exists)
        XCTAssertTrue(app.buttons["addFirstProperty"].exists)
    }

    /// A date is read whole or not at all, so when a row runs out of room it
    /// is the name's column that gives and not the picker.
    ///
    /// At the largest text size a date and a time together want more than the
    /// column a row of this width has left over — and the row that handed the
    /// name a column of its own regardless drew the difference outside the
    /// card, with the date cropped or the card's own edge off the side of the
    /// screen. Asked as containment rather than in points, because how much
    /// room a picker asks for is the system's business and differs by device,
    /// by language and by every step of the text size.
    func testADateKeepsItsWidthWhenTheRowRunsOutOfRoom() throws {
        let app = launchApp(
            textSize: "UICTContentSizeCategoryXXXL",
            todaysEntry: "---\ncreated: 2025-09-04T13:50\nmood: 7\n---\n# A walk\n"
        )
        let card = app.otherElements["frontmatterSection"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "the section never appeared")

        let row = app.otherElements["property-created"]
        let name = app.textFields["propertyKey-created"]
        let picker = app.buttons["propertyDate-created"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the date never appeared")

        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(card.frame),
            "the card \(card.frame) reached off the side of the screen"
        )
        XCTAssertEqual(
            row.frame.width, app.otherElements["property-mood"].frame.width,
            "the row the date is in is wider than the rows that fit"
        )
        XCTAssertTrue(
            row.frame.contains(picker.frame),
            "the date \(picker.frame) reached outside its row \(row.frame)"
        )
        XCTAssertGreaterThanOrEqual(
            picker.frame.minX, name.frame.maxX,
            "the date was drawn over the name it belongs to"
        )
        // And the row that had room to spare is untouched: the column is a
        // column still, and only the row that could not afford one gave it up.
        XCTAssertGreaterThanOrEqual(
            app.textFields["propertyKey-mood"].frame.width, name.frame.width,
            "the name beside a number should be no narrower than the one beside a date"
        )
    }

    /// The day and the hour of a date-and-time Property are two controls, and
    /// each writes its own half of the moment: an hour moved leaves the day
    /// where it was.
    ///
    /// The minutes and never the hour, and read back off the block rather than
    /// off the screen — the pickers are spelled in the reader's own language
    /// and the file is spelled in YAML, which is the same in every language.
    func testMovingTheHourLeavesTheDayWhereItWas() throws {
        let app = launchApp(todaysEntry: "---\ncreated: 2025-09-04T13:50\n---\n# A walk\n")
        XCTAssertTrue(
            app.otherElements["frontmatterSection"].waitForExistence(timeout: 30),
            "the section never appeared"
        )

        let hour = app.datePickers["propertyTime-created"]
        XCTAssertTrue(hour.waitForExistence(timeout: 10), "the hour never appeared")
        // Thrown five minutes on from where it was and read back off the
        // clock rather than dictated: which minute it lands on is not what
        // this is about, and a wheel lands a row out often enough to be a
        // test that fails on a minute nobody chose.
        let landed = throwTheMinutes(of: hour, at: 55, in: app)
        XCTAssertNotEqual(landed, "50", "the clock never moved")

        app.buttons["frontmatterSourceToggle"].tap()
        let source = app.textViews["frontmatterSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        expect(source, toHaveValue: "---\ncreated: 2025-09-04T13:\(landed)\n---")
    }

    /// A date is said in words, at every width and in every language: never
    /// `04/09/2025`, which is what the system's own compact picker falls back
    /// to when it decides it is short of room.
    ///
    /// Asked as "letters and no slashes" rather than against a date spelled
    /// out here, because the app is running in English and the test process in
    /// this Mac's own language — a date this test formatted would be the wrong
    /// one in the right shape.
    func testADateIsAlwaysSaidInWordsAndNeverInNumbers() throws {
        for textSize in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launchApp(
                textSize: textSize,
                todaysEntry: "---\ncreated: 2025-09-04T13:50\nwhen: 2025-09-04\n---\n# A walk\n"
            )
            XCTAssertTrue(
                app.otherElements["frontmatterSection"].waitForExistence(timeout: 30),
                "the section never appeared"
            )
            for key in ["created", "when"] {
                let said = app.buttons["propertyDate-\(key)"].label
                XCTAssertFalse(
                    said.contains("/"), "\(key) was written in numbers at \(textSize ?? "the usual size"): \(said)"
                )
                XCTAssertNotNil(
                    said.rangeOfCharacter(from: .letters),
                    "\(key) had no month in letters at \(textSize ?? "the usual size"): \(said)"
                )
                XCTAssertTrue(said.contains("2025"), "\(key) was said without its year: \(said)")
            }
            app.terminate()
        }
    }

    /// A day picked out of the calendar behind the pill is written to the
    /// file — and the hour it was written at is still there afterwards, which
    /// is the other half of the moment the day's own control does not touch.
    func testADayPickedOutOfTheCalendarKeepsTheHourItWasWrittenAt() throws {
        let app = launchApp(todaysEntry: "---\ncreated: 2025-09-04T13:50\n---\n# A walk\n")
        let pill = app.buttons["propertyDate-created"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the date never appeared")
        pill.tap()

        let calendar = app.datePickers["propertyCalendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10), "the calendar never opened")
        // The fifteenth of the month on screen, which is the one day of it
        // whose name no other day's and no header's contains.
        let fifteenth = calendar.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "15")
        ).firstMatch
        XCTAssertTrue(fifteenth.waitForExistence(timeout: 10), "the month offered no fifteenth")
        fifteenth.tap()

        let dismiss = app.buttons["PopoverDismissRegion"]
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }

        app.buttons["frontmatterSourceToggle"].tap()
        let source = app.textViews["frontmatterSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        expect(source, toHaveValue: "---\ncreated: 2025-09-15T13:50\n---")
    }

    /// Types a day in from the top, block and all — the one way a UI test has
    /// of putting a Frontmatter in a file the next launch will not seed over.
    ///
    /// The block lifts on its own: the body's first character takes the
    /// caret past the closing fence, which is the caret leaving the block.
    /// Every line starts with a capital, so that autocapitalisation has
    /// nothing it could change.
    @discardableResult
    private func typeADay(_ text: String, into app: XCUIApplication) -> XCUIElement {
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "today's entry never appeared")
        editor.tap()
        editor.typeText(text)
        XCTAssertTrue(
            app.otherElements["frontmatterSection"].waitForExistence(timeout: 10),
            "the block typed in never lifted into the section"
        )
        return editor
    }

    /// Selects everything in a text view, so that what is typed next replaces
    /// it — the simulator has no hardware keyboard to select with.
    private func selectAll(in textView: XCUIElement, app: XCUIApplication) {
        textView.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 3) {
            selectAll.tap()
        } else {
            // Nothing to select from: the edit menu offers "Select All" only
            // beside a caret, so a text view with the whole text selected
            // already is a text view that offers "Cut" instead.
            XCTAssertTrue(app.menuItems["Cut"].exists, "the edit menu never came up")
        }
    }
}
