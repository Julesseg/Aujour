import XCTest

final class GlassPrototypeCaptureTests: AujourUITestCase {
    func testCapture() throws {
        for theme in ["light", "dark"] {
            for phase in ["before", "after", "radius36", "radius52"] {
                let app = XCUIApplication()
                app.launchEnvironment = [
                    "AUJOUR_UITEST_JOURNAL_FOLDER": UUID().uuidString,
                    "AUJOUR_UITEST_LAYOUT": "page",
                    "AUJOUR_UITEST_TODAYS_ENTRY": "# A little room to breathe\n\nWalked along the water this morning. The air was cool, and the city was only just waking up.\n\n## Things to keep\n\n- A slow start\n- Coffee with a friend\n- A few pages before bed\n\nSome days do not need much more than this.\n",
                    "AUJOUR_PROTOTYPE_ACCENT": "harbour",
                    "AUJOUR_PROTOTYPE_THEME": theme,
                    "AUJOUR_PROTOTYPE_TINT": phase == "before" ? "before" : "after",
                    "AUJOUR_PROTOTYPE_RADIUS": phase == "radius36" ? "36" : phase == "radius52" ? "52" : "22"
                ]
                app.launch()
                XCTAssertTrue(app.buttons["datePill"].waitForExistence(timeout: 30))
                if phase == "before" || phase == "after" { shot(app, "\(theme)-\(phase)-closed") }
                let frame = app.buttons["datePill"].frame
                let header = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.minY + 22 - app.frame.minY))
                header.tap()
                expect(app.buttons["datePill"], toHaveValue: "Week")
                shot(app, "\(theme)-\(phase)-week")
                header.tap()
                expect(app.buttons["datePill"], toHaveValue: "Month")
                shot(app, "\(theme)-\(phase)-month")
                if phase == "before" || phase == "after" {
                    shutTheDatePill(app)
                    app.textViews["entryEditor"].tap()
                    XCTAssertTrue(app.buttons["formatBold"].waitForExistence(timeout: 5))
                    shot(app, "\(theme)-\(phase)-keyboard")
                }
                app.terminate()
            }
            for phase in ["before", "after"] {
                let app = XCUIApplication()
                app.launchEnvironment = [
                    "AUJOUR_UITEST_JOURNAL_FOLDER": UUID().uuidString,
                    "AUJOUR_UITEST_LAYOUT": "sidebar",
                    "AUJOUR_UITEST_TODAYS_ENTRY": "# A little room to breathe\n\nThe journal and its calendar, side by side.\n",
                    "AUJOUR_UITEST_DIVERGED_VERSION": "# A little room to breathe\n\nA version from another device.\n",
                    "AUJOUR_PROTOTYPE_ACCENT": "harbour",
                    "AUJOUR_PROTOTYPE_THEME": theme,
                    "AUJOUR_PROTOTYPE_TINT": phase,
                ]
                app.launch()
                XCTAssertTrue(app.staticTexts["parkedFileNotice"].waitForExistence(timeout: 30))
                shot(app, "\(theme)-\(phase)-sidebar-notice")
                app.terminate()
            }
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
