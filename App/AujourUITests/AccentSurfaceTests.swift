import UIKit
import XCTest

final class AccentSurfaceTests: AujourUITestCase {
    @MainActor
    func testSettingsSubpageSafeAreasUseTheAccent() throws {
        continueAfterFailure = true
        let app = launchApp()
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 30))

        for mode in ["Light", "Dark"] {
            var toolbars: [[String: [UInt8]]] = []
            for accent in ["olive", "harbour"] {
                var colors: [String: [UInt8]] = [:]
                openHowItLooks(in: app)
                app.segmentedControls["appearanceTheme"].buttons[mode].tap()
                app.buttons["accent.\(accent)"].tap()
                app.buttons["BackButton"].tap()
                let reminders = app.buttons["dataPlaceholder-reminders"]
                scrollTo(reminders, in: app)
                reminders.tap()
                XCTAssertTrue(app.textFields["linePrefixField"].waitForExistence(timeout: 10))

                for position in ["top", "scrolled"] {
                    if position == "scrolled" { theScroller(in: app).swipeUp() }
                    let page = theScroller(in: app).frame
                    colors[position] = try mostCommonColor(of: app.navigationBars.firstMatch)
                    capture(app, named: "chrome-\(mode)-\(accent)-\(position)")
                    if page.maxY >= app.frame.maxY - 1 {
                        let paper = try color(in: app, at: CGPoint(x: page.minX + 4, y: page.midY))
                        let bottom = try color(in: app, at: CGPoint(x: page.minX + 4, y: page.maxY - 4))
                        XCTAssertEqual(bottom, paper, "The bottom edge differs from the sheet: \(mode), \(accent), \(position)")
                    }
                }
                toolbars.append(colors)
                app.buttons["BackButton"].tap()
                app.buttons["Done"].tap()
            }
            for position in ["top", "scrolled"] {
                XCTAssertNotEqual(
                    toolbars[0][position], toolbars[1][position],
                    "The \(position) toolbar ignored the selected accent in \(mode) mode"
                )
            }
        }
    }

    func testTheAccentTintsSettingsAndFrontmatterSurfaces() throws {
        continueAfterFailure = true
        XCUIDevice.shared.appearance = .light
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let app = launchApp(
            todaysEntry: "---\nmood: 7\ndone: true\ntags: [walk, market]\n---\n# A walk\nA quiet morning.\n"
        )
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 30))

        for mode in ["Light", "Dark"] {
            var surfaces: [[String: [UInt8]]] = []
            for accent in ["olive", "harbour"] {
                openHowItLooks(in: app)
                app.segmentedControls["appearanceTheme"].buttons[mode].tap()
                app.buttons["accent.\(accent)"].tap()
                let page = theScroller(in: app).frame
                var colors = [
                    "Appearance background": try color(
                        in: app, at: CGPoint(x: page.minX + 4, y: page.midY)
                    )
                ]
                capture(app, named: "\(mode)-\(accent)-appearance")

                app.buttons["BackButton"].tap()
                let row = app.buttons["openEntryPath"]
                scrollTo(row, in: app)
                colors["Settings background"] = try color(
                    in: app, at: CGPoint(x: page.minX + 4, y: page.midY)
                )
                colors["Settings card"] = try color(
                    in: app, at: CGPoint(x: row.frame.midX, y: row.frame.maxY - 5)
                )
                capture(app, named: "\(mode)-\(accent)-settings")

                app.buttons["Done"].tap()
                let key = app.textFields["propertyKey-mood"]
                XCTAssertTrue(key.waitForExistence(timeout: 10))
                colors["Frontmatter card"] = try color(
                    in: app, at: CGPoint(x: key.frame.maxX + 4, y: key.frame.midY)
                )
                XCTAssertGreaterThanOrEqual(
                    try contrast(of: app.staticTexts["walk"]), 4.5,
                    "Frontmatter chip text is below the contrast floor in \(mode) with \(accent)"
                )
                capture(app, named: "\(mode)-\(accent)-properties")
                surfaces.append(colors)
            }
            for name in surfaces[0].keys.sorted() {
                XCTAssertNotEqual(
                    surfaces[0][name], surfaces[1][name],
                    "\(name) ignored the selected accent in \(mode) mode"
                )
            }
        }
    }

    @MainActor
    private func mostCommonColor(of element: XCUIElement) throws -> [UInt8] {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let rgba = try pixels(in: image)
        var counts: [Int: Int] = [:]
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let rgb = Int(rgba[offset]) << 16 | Int(rgba[offset + 1]) << 8 | Int(rgba[offset + 2])
            counts[rgb, default: 0] += 1
        }
        let rgb = try XCTUnwrap(counts.max { $0.value < $1.value }?.key)
        return [UInt8(rgb >> 16), UInt8((rgb >> 8) & 255), UInt8(rgb & 255)]
    }

    private func color(in app: XCUIApplication, at point: CGPoint) throws -> [UInt8] {
        Thread.sleep(forTimeInterval: 1)
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(
            x: (point.x - app.frame.minX) * scale,
            y: (point.y - app.frame.minY) * scale,
            width: 1, height: 1
        )))
        return Array(try pixels(in: pixel).prefix(3))
    }

    private func contrast(of element: XCUIElement) throws -> Double {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let rgba = try pixels(in: image)
        var darkest = 1.0
        var lightest = 0.0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let channels = (0..<3).map { channel -> Double in
                let value = Double(rgba[offset + channel]) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
            darkest = min(darkest, luminance)
            lightest = max(lightest, luminance)
        }
        return (lightest + 0.05) / (darkest + 0.05)
    }

    private func pixels(in image: CGImage) throws -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return rgba
    }
}
