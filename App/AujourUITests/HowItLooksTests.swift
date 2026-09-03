import UIKit
import XCTest

final class HowItLooksTests: AujourUITestCase {

    // MARK: - Theming

    /// What theming is, said the only way a running app can say it: a choice
    /// made on this screen is the app's, and it is still the app's after a
    /// relaunch.
    ///
    /// Which colour each accent resolves to in light and in dark, and what
    /// "serif at 22 points" comes out as once Dynamic Type has had it, are
    /// checked where a colour and a font exist to check them, in
    /// `AppearanceTests`. What only a running app can show is that the three
    /// controls reach the settings at all, and that what they wrote survives
    /// the process ending.
    func testHowAujourLooksIsChosenOnThisDeviceAndStaysChosen() throws {
        let app = launchApp()

        openHowItLooks(in: app)

        let specimen = app.staticTexts["editorFontSpecimen"]
        let asItComes = try XCTUnwrap(specimen.value as? String)

        app.segmentedControls["appearanceTheme"].buttons["Dark"].tap()
        app.buttons["accent.olive"].tap()
        app.segmentedControls["editorFontFamily"].buttons["Serif"].tap()
        app.segmentedControls["editorFontSize"].buttons["XL"].tap()

        XCTAssertEqual(app.staticTexts["accentInUse"].label, "Olive")
        let chosenFont = try XCTUnwrap(specimen.value as? String)
        XCTAssertTrue(
            chosenFont.hasPrefix("Serif, "),
            "the specimen is not in the chosen face — it says \(chosenFont)"
        )
        XCTAssertNotEqual(
            chosenFont, asItComes,
            "the size control moved nothing — the specimen still says \(chosenFont)"
        )

        relaunch(app)

        // The journal sheet says which accent is in force before it is opened,
        // which is the shortest proof that the choice outlived the process.
        fromTheMenu("openSettings", in: app)

        let howItLooks = app.buttons["openHowItLooks"]
        scrollTo(howItLooks, in: app)
        XCTAssertTrue(howItLooks.label.contains("Olive"), "the accent did not survive a relaunch")
        howItLooks.tap()

        XCTAssertTrue(
            app.segmentedControls["appearanceTheme"].buttons["Dark"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.segmentedControls["appearanceTheme"].buttons["Dark"].isSelected,
            "the appearance did not survive a relaunch"
        )
        XCTAssertEqual(app.staticTexts["accentInUse"].label, "Olive")
        XCTAssertEqual(app.staticTexts["editorFontSpecimen"].value as? String, chosenFont)
    }

    /// The sheet the appearance is changed on is drawn in it too, while it is
    /// still up.
    ///
    /// A sheet is its own presentation: the appearance the window is asking
    /// for reaches it when it is put up, and an already-open one went on
    /// sitting there in the appearance it opened in. Which made *this* sheet
    /// the worst possible one to have it happen to — the control that had just
    /// been moved was on it, and nothing under the finger changed.
    ///
    /// Asked as a brightness, because there is no other way to ask a running
    /// app what colour scheme it is actually drawing in: an element that is
    /// dark grey on a dark page and light grey on a light one comes out of a
    /// screenshot as two very different numbers, and one that never followed
    /// comes out as the same one twice.
    func testTheSheetIsDrawnInTheAppearanceBeingChosenOnIt() throws {
        // Said rather than assumed, because Auto below is only worth asking
        // about against a device that is doing something known.
        XCUIDevice.shared.appearance = .light
        // Left light rather than unspecified, which the runner refuses:
        // light is what a simulator boots in, so this is putting it back.
        addTeardownBlock { XCUIDevice.shared.appearance = .light }

        let app = launchApp()
        openHowItLooks(in: app)
        let theme = app.segmentedControls["appearanceTheme"]

        theme.buttons["Dark"].tap()
        let inDark = try brightness(of: theme)

        theme.buttons["Light"].tap()
        let inLight = try brightness(of: theme)

        XCTAssertGreaterThan(
            inLight, inDark + 0.2,
            "the sheet did not follow the appearance — it was \(inDark) in dark "
                + "and \(inLight) in light, which is the same page twice"
        )

        // And back to Auto, which is the one of the three that is not an
        // instruction. The device is light, so the sheet has to be — and this
        // is the step that stays wrong longest, because "no preference" is not
        // the same as "light": a sheet told to be dark and then told nothing
        // goes on being dark.
        theme.buttons["Dark"].tap()
        _ = try brightness(of: theme)
        theme.buttons["Auto"].tap()
        let inAuto = try brightness(of: theme)

        XCTAssertGreaterThan(
            inAuto, inDark + 0.2,
            "the sheet stayed dark when the appearance went back to Auto on a "
                + "light device — it was \(inAuto), against \(inDark) in dark "
                + "and \(inLight) in light"
        )
    }

    /// The claim the identity's type scale is built on: chrome answers the
    /// system's text size, and the screen still holds together when the reader
    /// has turned it all the way up.
    ///
    /// Asked of the page the token layer is adopted on, because that is where
    /// there is something to ask it of. Two launches and not one — a size only
    /// means something against another size, and a page that ignored Dynamic
    /// Type entirely would pass every "is it on screen" check ever written.
    ///
    /// The overlap half is the part that a scale alone does not give you: a
    /// stack whose gaps are fixed while its labels have trebled is a stack
    /// whose sentence is sitting on top of the control above it, and it looks
    /// perfectly correct at the size it was designed at.
    func testTheAppearancePageHoldsTogetherAtTheLargestTextSize() throws {
        let atTheFactorySetting = launchApp()
        openHowItLooks(in: atTheFactorySetting)
        let smallPrint = atTheFactorySetting.staticTexts["appearanceIsDeviceLocal"]
        scrollTo(smallPrint, in: atTheFactorySetting)
        let ordinaryHeight = smallPrint.frame.height
        atTheFactorySetting.terminate()

        let app = launchApp(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openHowItLooks(in: app)

        // It grew. Measured on the smallest lettering on the page, because the
        // caption is the one a reader who needs this most cannot read, and the
        // one an app is likeliest to have pinned.
        let turnedUp = app.staticTexts["appearanceIsDeviceLocal"]
        scrollTo(turnedUp, in: app)
        XCTAssertGreaterThan(
            turnedUp.frame.height, ordinaryHeight,
            "the page's small print did not grow with the system text size — "
                + "it was \(ordinaryHeight) points tall and is now \(turnedUp.frame.height)"
        )

        // And nothing on it has climbed on top of anything else, or slid off
        // the side. Checked over what is on screen at each stop of a scroll
        // down the page, since an element that has not been scrolled to has no
        // frame worth comparing.
        // Named by what is in it rather than taken as the first one on screen:
        // this suite runs on iPad too, where the page is inside a form sheet
        // and "the first scroll view" is not a promise anybody made.
        let page = app.scrollViews.containing(.segmentedControl, identifier: "appearanceTheme")
            .firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the appearance page has no scroll view")
        page.swipeDown(velocity: .slow)

        for _ in 0..<4 {
            assertTheLayoutHolds(on: page)
            page.swipeUp(velocity: .fast)
        }
        assertTheLayoutHolds(on: page)
    }

    /// The other half of what S/M/L/XL is: a *writing* preference, so it moves
    /// the day's own words and nothing else on the screen.
    ///
    /// Asked of the Entry and not of the specimen on the settings page. The
    /// specimen shows what a step is worth; this is the claim the step is made
    /// for — that the words the user is actually writing came out the way they
    /// asked, and that the date over them did not move an inch.
    ///
    /// Measured on the prompt over an unwritten day, because that is the one
    /// thing on this screen drawn in the editor's own face that a running app
    /// can be asked the size of — a `UITextView`'s frame is the box it is in,
    /// not the type in it.
    ///
    /// The two controls are moved one at a time and not together. A sentence
    /// set bigger *and* in another face comes out a different width either
    /// way, and a single measurement of both says only that something reached
    /// the words.
    ///
    /// Measured after the sheet goes away, which is the one thing here that is
    /// not the claim: on a phone the sheet is full height, so there is no
    /// moment where the day and the control are both on screen to photograph.
    /// That a change lands at once rather than on dismissal is held where it
    /// is decided — `DeviceAppearance` publishes every choice as it is made
    /// and there is no apply step to defer it to (`AppearanceTests`, "the
    /// editor is told about a change the moment it is made").
    func testTheEditorsFaceAndSizeMoveTheDaysOwnWordsAndNoneOfTheChrome() throws {
        let app = launchApp()

        let daysWords = app.staticTexts["aBlankPage"]
        XCTAssertTrue(daysWords.waitForExistence(timeout: 30), "today's blank page never appeared")
        // The date over the entry: chrome, on screen beside the words the whole
        // time, so the two are asked the same question at the same moment.
        //
        // The pill and not a navigation title. The day's name is on the glass
        // now and the bar carries only the ways out of the day, so the pill is
        // what has to hold still — it is set in the system's text size, and the
        // writing's is none of its business.
        let chrome = app.buttons["datePill"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 10), "the day's date was never on screen")

        let asTheyCome = daysWords.frame
        let chromeAsItComes = chrome.frame

        // The size alone.
        openHowItLooks(in: app)
        app.segmentedControls["editorFontSize"].buttons["XL"].tap()
        backToTheDay(in: app)
        let atXL = daysWords.frame
        XCTAssertGreaterThan(
            atXL.height, asTheyCome.height,
            "the day's own words did not grow — they were \(asTheyCome.height) points tall "
                + "at M and are \(atXL.height) at XL"
        )

        // And the face alone, at the size just chosen — so what moves now is
        // the typeface and nothing else.
        openHowItLooks(in: app)
        app.segmentedControls["editorFontFamily"].buttons["Mono"].tap()
        backToTheDay(in: app)
        let inMono = daysWords.frame
        XCTAssertNotEqual(
            inMono.width, atXL.width,
            "the same sentence measures the same in mono as in sans — \(atXL.width) points "
                + "either way — so the face never reached the day's own words"
        )

        XCTAssertEqual(
            chrome.frame, chromeAsItComes,
            "the date over the entry moved with the editor's controls — it was at "
                + "\(chromeAsItComes) and is now at \(chrome.frame). Chrome follows the "
                + "system's text size, not the one the writing is set in"
        )
    }
}
