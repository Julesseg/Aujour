import XCTest

@MainActor
final class TemplateSourceSettingsTests: AujourUITestCase {
    func testCompactFormattingRows() {
        let app = launchApp(
            contentTemplate: "{{events}}\n{{reminders}}",
            events: "personal|Personal meeting\nwork|Team meeting",
            reminders: "personal|Home task\nwork|Work task",
            eventLists: "personal|Personal|iCloud\nwork|Work|Exchange",
            reminderLists: "personal|Personal|iCloud\nwork|Work|Exchange"
        )
        openSettings(app)
        for placeholder in ["events", "reminders"] {
            openFormatting(placeholder, in: app)
            XCTAssertTrue(app.staticTexts["wholeDayExample"].waitForExistence(timeout: 10))
            XCTAssertTrue(waitFor { app.buttons["openTemplateLists"].label.contains("2 of 2") })
            capture("\(placeholder)-formatting-two")
            backToTheSettings(in: app)
        }
    }

    func testLongListsHaveTheirOwnPage() {
        let lists = (1...20).map { "list-\($0)|List \($0)|iCloud" }.joined(separator: "\n")
        let app = launchApp(eventLists: lists, reminderLists: lists)
        openSettings(app)
        for placeholder in ["events", "reminders"] {
            openFormatting(placeholder, in: app)
            let row = app.buttons["openTemplateLists"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            XCTAssertTrue(waitFor { row.label.contains("20 of 20") })
            XCTAssertFalse(app.switches["templateList-list-1"].exists)
            XCTAssertTrue(app.textFields["linePrefixField"].isHittable)
            capture("\(placeholder)-formatting-long")
            replaceTheText(in: "linePrefixField", with: "* ", in: app)
            scrollTo(row, in: app)
            row.tap()
            XCTAssertTrue(app.switches["templateList-list-1"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["changeHowItIsWritten"].exists)
            let first = app.switches["templateList-list-1"]
            flip(first)
            XCTAssertTrue(waitFor { first.value as? String == "0" })
            capture("\(placeholder)-lists-top")
            let last = app.switches["templateList-list-20"]
            scrollTo(last, in: app)
            XCTAssertTrue(last.isHittable)
            capture("\(placeholder)-lists-bottom")
            backToFormatting(in: app)
            XCTAssertTrue(waitFor { row.label.contains("19 of 20") })
            XCTAssertEqual(app.textFields["linePrefixField"].value as? String, "* ")
            capture("\(placeholder)-formatting-selected")
            row.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            XCTAssertEqual(first.value as? String, "0")
            backToFormatting(in: app)
            backToTheSettings(in: app)
        }
    }

    func testExcludedListsPersistAndAreLeftOutOfNewEntries() throws {
        let app = launchApp(
            contentTemplate: "{{events}}\n{{reminders}}",
            events: "personal|Personal meeting\nwork|Team meeting",
            reminders: "personal|Home task\nwork|Work task",
            eventLists: "personal|Personal|iCloud\nwork|Work|Exchange",
            reminderLists: "personal|Personal|iCloud\nwork|Work|Exchange"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertEqual(editor.value as? String, "- Personal meeting\n- Team meeting\n- [ ] Home task\n- [ ] Work task")
        openSettings(app)
        for placeholder in ["events", "reminders"] {
            open(placeholder, in: app)
            capture("\(placeholder)-included")
            let work = app.switches["templateList-work"]
            XCTAssertTrue(work.waitForExistence(timeout: 10))
            XCTAssertEqual(work.value as? String, "1")
            flip(work)
            XCTAssertEqual(work.value as? String, "0")
            capture("\(placeholder)-excluded")
            backFromListsToSettings(in: app)
        }
        relaunch(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertEqual(editor.value as? String, "- Personal meeting\n- [ ] Home task")
        capture("filtered-entry")
        openSettings(app)
        open("events", in: app)
        XCTAssertEqual(app.switches["templateList-work"].value as? String, "0")
        flip(app.switches["templateList-personal"])
        relaunch(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertEqual(editor.value as? String, "\n- [ ] Home task")
        openSettings(app)
        open("events", in: app)
        flip(app.switches["templateList-work"])
        relaunch(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertEqual(editor.value as? String, "- Team meeting\n- [ ] Home task")
    }

    func testChangingListsLeavesASavedEntryAsWritten() throws {
        let app = launchApp(
            contentTemplate: "{{events}}",
            events: "work|Team meeting",
            eventLists: "work|Work|Exchange"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText("\nMy notes")
        let written = try XCTUnwrap(editor.value as? String)
        Thread.sleep(forTimeInterval: 4)
        openSettings(app)
        open("events", in: app)
        flip(app.switches["templateList-work"])
        relaunch(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertEqual(editor.value as? String, written)
    }

    func testAccessRequiredAndDenied() {
        let app = launchApp(
            eventsAccess: "undecided", remindersAccess: "refused",
            eventLists: "personal|Personal|iCloud"
        )
        openSettings(app)
        open("events", in: app)
        XCTAssertTrue(app.buttons["allowTemplateListAccess"].waitForExistence(timeout: 10))
        capture("events-access-required")
        app.buttons["allowTemplateListAccess"].tap()
        XCTAssertTrue(app.switches["templateList-personal"].waitForExistence(timeout: 10))
        capture("events-access-granted")
        backFromListsToSettings(in: app)
        open("reminders", in: app)
        XCTAssertTrue(app.buttons["templateListSystemSettings"].waitForExistence(timeout: 10))
        capture("reminders-access-denied")
    }

    func testSourceSettingsScreens() {
        let app = launchApp()
        openSettings(app)
        capture("settings")
        for placeholder in ["events", "reminders"] {
            openFormatting(placeholder, in: app)
            XCTAssertTrue(app.staticTexts["wholeDayExample"].waitForExistence(timeout: 10))
            capture("\(placeholder)-formatting-empty")
            app.buttons["openTemplateLists"].tap()
            XCTAssertTrue(app.staticTexts["noTemplateLists"].waitForExistence(timeout: 10))
            capture("\(placeholder)-lists-empty")
            backFromListsToSettings(in: app)
        }
    }

    private func openFormatting(_ placeholder: String, in app: XCUIApplication) {
        let row = app.buttons["dataPlaceholder-\(placeholder)"]
        scrollTo(row, in: app)
        row.tap()
    }

    private func open(_ placeholder: String, in app: XCUIApplication) {
        openFormatting(placeholder, in: app)
        let row = app.buttons["openTemplateLists"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
    }

    private func backToFormatting(in app: XCUIApplication) {
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["openTemplateLists"].waitForExistence(timeout: 10))
    }

    private func backFromListsToSettings(in app: XCUIApplication) {
        backToFormatting(in: app)
        backToTheSettings(in: app)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
