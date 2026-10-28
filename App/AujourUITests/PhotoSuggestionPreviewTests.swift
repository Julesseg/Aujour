import XCTest

final class PhotoSuggestionPreviewTests: AujourUITestCase {
    func testPreviewBeforeAddingAPhotograph() {
        let app = launchApp(
            photoLibrary: "\(todaysEntryName()) 09:15\n\(todaysEntryName()) 18:40"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText("Walked to the market.")
        let suggestions = app.buttons["openSuggestions"]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
        suggestions.tap()
        let photo = app.buttons["photoSuggestion0"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        capture(app, named: "photo-suggestions-grid")

        photo.press(forDuration: 1.2)
        let add = app.buttons["Add to document"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["photoSuggestionPreviewImage"].waitForExistence(timeout: 10))
        capture(app, named: "photo-suggestion-preview")
        add.tap()
        XCTAssertTrue(app.buttons["cancelSuggestions"].waitForNonExistence(timeout: 10))
        expect(editor, toHaveValue: "Walked to the market.\n![](\(todaysPhotograph(named: "jpg")))")
    }

    func testDismissingAPreviewLeavesTheDocumentUnchanged() {
        let app = launchApp(
            photoLibrary: todaysEntryName()
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText("Walked to the market.")
        let suggestions = app.buttons["openSuggestions"]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
        suggestions.tap()
        let photo = app.buttons["photoSuggestion0"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.press(forDuration: 1.2)
        let add = app.buttons["Add to document"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.1)).tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 10))
        app.buttons["cancelSuggestions"].tap()
        expect(editor, toHaveValue: "Walked to the market.")
        capture(app, named: "document-after-dismissing-preview")

        XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
        suggestions.tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        expect(editor, toHaveValue: "Walked to the market.\n![](\(todaysPhotograph(named: "jpg")))")
    }
}
