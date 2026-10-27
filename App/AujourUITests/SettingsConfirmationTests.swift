import XCTest

final class SettingsConfirmationTests: AujourUITestCase {
    func testTheSettingsCheckmarksSaveAndReturnToSettings() throws {
        let app = launchApp(contentTemplate: "## Morning\n")
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 30))
        openSettings(app)

        let photoPath = app.buttons["openPhotoPath"]
        scrollTo(photoPath, in: app)
        photoPath.tap()
        replaceTheText(in: "attachmentPathField", with: "[Photos]/YYYY/MM", in: app)
        capture(app, named: "photo-path-before-checkmark")
        app.buttons["changeAttachmentPath"].tap()
        capture(app, named: "photo-path-after-checkmark")
        expectSettings(in: app)
        expect(photoPath, toBeShowing: "[Photos]/YYYY/MM")

        for placeholder in ["events", "reminders"] {
            let row = app.buttons["dataPlaceholder-\(placeholder)"]
            scrollTo(row, in: app)
            row.tap()
            replaceTheText(in: "linePrefixField", with: "* ", in: app)
            capture(app, named: "\(placeholder)-before-checkmark")
            app.buttons["changeHowItIsWritten"].tap()
            expectSettings(in: app)
            capture(app, named: "\(placeholder)-after-checkmark")
            scrollTo(row, in: app)
            row.tap()
            expect(app.textFields["linePrefixField"], toHaveValue: "* ")
            backToTheSettings(in: app)
        }

        openTheTemplate(in: app)
        let template = app.textViews["contentTemplateText"]
        XCTAssertTrue(template.waitForExistence(timeout: 10))
        giveTheKeyboardTo(template, in: app)
        template.typeText("## Evening\n")
        capture(app, named: "template-before-checkmark")
        app.buttons["saveContentTemplate"].tap()
        expectSettings(in: app)
        capture(app, named: "template-after-checkmark")
        openTheTemplate(in: app)
        expect(app.textViews["contentTemplateText"], toHaveValue: "## Morning\n## Evening\n")
        backToTheSettings(in: app)

        openTheEntryPath(in: app)
        typeEntryPath("[Journal]/YYYY-MM-DD", into: app)
        capture(app, named: "entry-path-before-checkmark")
        app.buttons["changeEntryPath"].tap()
        expectSettings(in: app)
        capture(app, named: "entry-path-after-checkmark")
        expect(app.buttons["openEntryPath"], toBeShowing: "[Journal]/YYYY-MM-DD")
    }

    func testCancellingAMigrationKeepsTheEntryPathPageAndItsDraft() throws {
        let app = launchApp(todaysEntry: "A quiet morning.")
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 30))
        openSettings(app)
        openTheEntryPath(in: app)
        typeEntryPath("[Journal]/YYYY-MM-DD", into: app)
        app.buttons["changeEntryPath"].tap()
        XCTAssertTrue(app.buttons["cancelEntryPathChange"].waitForExistence(timeout: 15))
        app.buttons["cancelEntryPathChange"].tap()
        expect(app.textFields["entryPathField"], toHaveValue: "[Journal]/YYYY-MM-DD")
        XCTAssertTrue(app.buttons["changeEntryPath"].isEnabled)
        capture(app, named: "entry-path-cancelled-migration")
    }

    private func expectSettings(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["openEntryPath"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["attachmentPathField"].exists)
        XCTAssertFalse(app.textFields["entryPathField"].exists)
        XCTAssertFalse(app.textViews["contentTemplateText"].exists)
        XCTAssertFalse(app.textFields["linePrefixField"].exists)
    }

}
