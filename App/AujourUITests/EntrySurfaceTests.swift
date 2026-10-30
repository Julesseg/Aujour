import UIKit
import XCTest

final class EntrySurfaceTests: AujourUITestCase {
    func testWritingSurfacesInBothAppearances() throws {
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let frontmatter = "---\nmood: calm\nlocation: Paris\ntags: [everyday, autumn]\n---\n"
        let body = "# A slower day\nA quiet morning by the canal.\n"
        let fixtures = [
            ("written", frontmatter + body),
            ("empty-body", frontmatter),
            ("source", "---\nweather:\n  sky: clear\n---\n" + body),
            ("no-frontmatter", body),
        ]

        for (mode, appearance, expected) in [
            ("light", XCUIDevice.Appearance.light, [250, 249, 248]),
            ("dark", XCUIDevice.Appearance.dark, [23, 22, 18]),
        ] {
            XCUIDevice.shared.appearance = appearance
            for (state, entry) in fixtures {
                let app = launchApp(layout: nil, todaysEntry: entry)
                let editor = app.textViews["entryEditor"]
                XCTAssertTrue(editor.waitForExistence(timeout: 30))
                if state == "written" {
                    openHowItLooks(in: app)
                    app.segmentedControls["appearanceTheme"].buttons[mode.capitalized].tap()
                    app.buttons["BackButton"].tap()
                    app.buttons["Done"].tap()
                }
                if state == "source" {
                    XCTAssertTrue(app.textViews["frontmatterSource"].waitForExistence(timeout: 10))
                } else if state != "no-frontmatter" {
                    let section = app.otherElements["frontmatterSection"]
                    XCTAssertTrue(section.waitForExistence(timeout: 10))
                    let toggle = app.buttons["frontmatterSourceToggle"]
                    XCTAssertTrue(toggle.isHittable)
                    let lastProperty = app.otherElements["property-tags"]
                    XCTAssertTrue(lastProperty.exists)
                    XCTAssertGreaterThanOrEqual(toggle.frame.minY, lastProperty.frame.maxY)
                    let add = app.buttons["addProperty"]
                    XCTAssertTrue(add.isHittable)
                    XCTAssertGreaterThanOrEqual(add.frame.minY, lastProperty.frame.maxY)
                    let underControls = try pixel(
                        in: app,
                        at: CGPoint(x: editor.frame.minX + 64, y: toggle.frame.midY)
                    )
                    let page = try pixel(
                        in: app,
                        at: CGPoint(x: editor.frame.minX + 2, y: toggle.frame.midY)
                    )
                    XCTAssertEqual(underControls, page)
                    let color = try pixel(
                        in: app,
                        at: CGPoint(x: editor.frame.minX + 20, y: section.frame.maxY + 80)
                    )
                    for channel in 0..<3 {
                        XCTAssertLessThanOrEqual(abs(Int(color[channel]) - expected[channel]), 2)
                    }
                } else {
                    XCTAssertTrue(app.buttons["addFirstProperty"].exists)
                    XCTAssertFalse(app.buttons["addFirstProperty"].isHittable)
                }
                capture(app, named: "entry-surfaces-\(mode)-\(state)")
                app.terminate()
            }
        }
    }

    private func pixel(in app: XCUIApplication, at point: CGPoint) throws -> [UInt8] {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(
            x: (point.x - app.frame.minX) * scale,
            y: (point.y - app.frame.minY) * scale,
            width: 1, height: 1
        )))
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }
}
