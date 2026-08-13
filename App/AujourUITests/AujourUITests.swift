import XCTest

// The acceptance-level claim of M1's storage: someone who has just installed
// Aujour, and been asked nothing, is looking at a journal folder that exists.
// Everything about *what* a folder of files means lives in Core, where
// `swift test` covers it fast; what only a running app can show is that the
// folder was found on launch with no configuration at all.
final class AujourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAFreshInstallFindsAJournalFolderWithoutBeingConfigured() throws {
        let app = XCUIApplication()
        app.launch()

        // Asking iCloud for the app's container is slow the first time on a
        // device, so this is a wait rather than an assertion about a frame.
        let location = app.staticTexts["journalRootLocation"]
        XCTAssertTrue(
            location.waitForExistence(timeout: 30),
            "the app did not settle on a journal folder — it is showing: "
                + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
        )
        XCTAssertFalse(location.label.isEmpty)

        // And it can say where it is, in a path the user could go and find.
        let path = app.staticTexts["journalRootPath"]
        XCTAssertTrue(path.exists)
        XCTAssertTrue(path.label.hasPrefix("/"), "expected a folder path, got \(path.label)")

        // A folder it could not read would have been a problem notice instead.
        XCTAssertTrue(app.staticTexts["journalFileCount"].exists)
        XCTAssertFalse(app.staticTexts["storageProblem"].exists)
    }
}
