import UIKit
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
        let previewImage = app.otherElements["Preview"].descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", photo.label)).firstMatch
        XCTAssertTrue(previewImage.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(previewImage.frame.width, photo.frame.width)
        capture(app, named: "photo-suggestion-preview")
        add.tap()
        XCTAssertTrue(app.buttons["cancelSuggestions"].waitForNonExistence(timeout: 10))
        expect(editor, toHaveValue: "Walked to the market.\n![](\(todaysPhotograph(named: "jpg")))")
    }

    func testEachThumbnailPreviewsItsOwnPhotograph() throws {
        let app = launchApp(
            photoLibrary: "\(todaysEntryName()) 09:15\n\(todaysEntryName()) 12:30\n\(todaysEntryName()) 18:40"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText("Walked to the market.")
        let suggestions = app.buttons["openSuggestions"]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
        suggestions.tap()
        XCTAssertTrue(app.buttons["photoSuggestion2"].waitForExistence(timeout: 10))
        capture(app, named: "individual-photo-grid")

        for index in [1, 2, 0] {
            let photo = app.buttons["photoSuggestion\(index)"]
            let label = photo.label
            let width = photo.frame.width
            let color = try centerPixel(of: photo)
            photo.press(forDuration: 1.2)
            let add = app.buttons["Add to document"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            capture(app, named: "individual-photo-preview-\(index)")
            let preview = app.otherElements["Preview"].descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 10), "Holding photo \(index) previewed a different photo")
            XCTAssertGreaterThan(preview.frame.width, width)
            let previewColor = try centerPixel(of: preview)
            for channel in 0..<3 {
                XCTAssertEqual(Double(previewColor[channel]), Double(color[channel]), accuracy: 7)
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.1)).tap()
            XCTAssertTrue(add.waitForNonExistence(timeout: 10))
        }

        let first = app.buttons["photoSuggestion0"].frame
        let second = app.buttons["photoSuggestion1"].frame
        let gutter = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: (first.maxX + second.minX) / 2, dy: first.midY
        ))
        gutter.press(forDuration: 1.2)
        XCTAssertFalse(app.buttons["Add to document"].exists)
        capture(app, named: "photo-grid-gutter-has-no-preview")
        app.buttons["cancelSuggestions"].tap()
        expect(editor, toHaveValue: "Walked to the market.")
    }

    private func centerPixel(of element: XCUIElement) throws -> [UInt8] {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(
            x: image.width / 2, y: image.height / 2, width: 1, height: 1
        )))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(rgba.prefix(3))
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
