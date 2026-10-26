import XCTest

@MainActor
final class TemplateSourceSettingsTests: AujourUITestCase {
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
            backToTheSettings(in: app)
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
        backToTheSettings(in: app)
        open("reminders", in: app)
        XCTAssertTrue(app.buttons["templateListSystemSettings"].waitForExistence(timeout: 10))
        capture("reminders-access-denied")
    }

    func testSourceSettingsScreens() {
        let app = launchApp()
        openSettings(app)
        capture("settings")
        for placeholder in ["events", "reminders"] {
            let row = app.buttons["dataPlaceholder-\(placeholder)"]
            scrollTo(row, in: app)
            row.tap()
            XCTAssertTrue(app.staticTexts["wholeDayExample"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["noTemplateLists"].exists)
            capture(placeholder)
            backToTheSettings(in: app)
        }
    }

    private func open(_ placeholder: String, in app: XCUIApplication) {
        let row = app.buttons["dataPlaceholder-\(placeholder)"]
        scrollTo(row, in: app)
        row.tap()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
