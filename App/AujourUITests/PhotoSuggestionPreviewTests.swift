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

        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
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
        for index in 0..<3 {
            expectLoadedThumbnail(app.buttons["photoSuggestion\(index)"])
        }
        capture(app, named: "individual-photo-grid")

        for index in [1, 2, 0] {
            let photo = app.buttons["photoSuggestion\(index)"]
            let label = photo.label
            let width = photo.frame.width
            let color = try centerPixel(of: photo)
            let thumbnailPixels = try coloredPixels(in: app, matching: color)
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
            let add = app.buttons["Add to document"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            capture(app, named: "individual-photo-preview-\(index)")
            let preview = app.otherElements["Preview"].descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 10), "Holding photo \(index) previewed a different photo")
            XCTAssertGreaterThan(preview.frame.width, width)
            XCTAssertFalse(app.keyboards.firstMatch.exists, "Previewing a photo reopened the editor keyboard")
            XCTAssertGreaterThan(try coloredPixels(in: app, matching: color), thumbnailPixels * 2,
                                 "The enlarged preview did not show photo \(index)'s pixels")
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

    func testThumbnailsLoadWhenReopeningSuggestionsOnDifferentDays() throws {
        let yesterday = try XCTUnwrap(dayBeforeToday())
        let app = launchApp(photoLibrary:
            "\(todaysEntryName()) 09:15\n\(todaysEntryName()) 12:30\n\(entryName(for: yesterday)) 18:40"
        )
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        let suggestions = app.buttons["openSuggestions"]
        for opening in 0..<2 {
            editor.tap()
            XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
            suggestions.tap()
            for index in 0..<2 {
                let photo = app.buttons["photoSuggestion\(index)"]
                XCTAssertTrue(photo.waitForExistence(timeout: 10))
                expectLoadedThumbnail(photo)
            }
            capture(app, named: "loaded-thumbnails-opening-\(opening)")
            app.buttons["cancelSuggestions"].tap()
        }
        swipeTheDay(app, across: 160)
        XCTAssertTrue(app.buttons["backToToday"].waitForExistence(timeout: 10))
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
        suggestions.tap()
        let photo = app.buttons["photoSuggestion0"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        expectLoadedThumbnail(photo)
        XCTAssertFalse(app.buttons["photoSuggestion1"].exists)
        let color = try centerPixel(of: photo)
        let thumbnailPixels = try coloredPixels(in: app, matching: color)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Add to document"].waitForExistence(timeout: 10))
        let preview = app.otherElements["Preview"].descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", photo.label)).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(try coloredPixels(in: app, matching: color), thumbnailPixels * 2)
        capture(app, named: "previous-day-photo-preview")
    }

    private func expectLoadedThumbnail(_ photo: XCUIElement) {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let rgb = try? self.centerPixel(of: photo),
                  let brightest = rgb.max(), let darkest = rgb.min() else { return false }
            return Int(brightest) - Int(darkest) > 50
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed,
                       "\(photo.identifier) stayed grey instead of loading its colored fixture")
    }

    private func coloredPixels(in app: XCUIApplication, matching color: [UInt8]) throws -> Int {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 0, to: rgba.count, by: 4).reduce(into: 0) { count, pixel in
            if (0..<3).allSatisfy({ abs(Int(rgba[pixel + $0]) - Int(color[$0])) <= 7 }) {
                count += 1
            }
        }
    }

    private func centerPixel(of element: XCUIElement) throws -> [UInt8] {
        let app = XCUIApplication()
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let screen = app.frame
        let frame = element.frame
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(
            x: (frame.midX - screen.minX) * CGFloat(image.width) / screen.width,
            y: (frame.midY - screen.minY) * CGFloat(image.height) / screen.height,
            width: 1, height: 1
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
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
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
