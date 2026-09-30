import XCTest

final class LaunchingTheJournalTests: AujourUITestCase {
    @MainActor
    func testAReadyJournalReplacesTheSplashAndStaysReadyOnResume() {
        let app = launchApp(layout: nil, todaysEntry: "The day is ready.\n")
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertTrue((editor.value as? String)?.contains("The day is ready.") ?? false)
        XCTAssertFalse(app.descendants(matching: .any)["openingJournal"].exists)
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "ready-after-launch"
        ready.lifetime = .keepAlways
        add(ready)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["openingJournal"].exists)
    }
}
