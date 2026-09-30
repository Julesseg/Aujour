import AujourCore
import SwiftUI
import UIKit
import XCTest

@testable import Aujour

/// Holds a real entry read at its data source, rather than adding a delay to
/// the app. The screenshots exercise ContentView's actual opening branch.
@MainActor
final class LaunchPresentationTests: XCTestCase {
    func testTheSplashLastsOnlyUntilTodaysEntryIsReady() async throws {
        try await withTemporaryFolder { root in
            try root.seed("The day is ready.\n{{events}}", at: "templates/Daily.md")
            let settings = JournalSettingsStore.inMemory()
            settings.update { $0.contentTemplateFile = "templates/Daily.md" }
            let reading = expectation(description: "today's entry is being read")
            let source = SuspendedLaunchItems(reading: reading)
            let journal = makeJournal(root: root, settings: settings, dayData: DayData([.events: source]))
            let window = show(journal)
            defer {
                window.isHidden = true
                window.rootViewController = nil
                Task { await source.release() }
            }

            await fulfillment(of: [reading], timeout: 10)
            XCTAssertEqual(journal.state, .opening, "Finding the folder must not dismiss the splash before the entry is ready")
            XCTAssertNotNil(journal.store, "The folder should already have opened in the background")
            XCTAssertFalse(journal.today?.state.isEditing ?? true)
            try await capture(window, named: "loading-light", style: .light)
            try await capture(window, named: "loading-dark", style: .dark)

            await source.release()
            // A bound on the test, not a duration the app waits to display.
            for _ in 0..<100 where !journal.isOpen {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(journal.isOpen)
            XCTAssertTrue(journal.today?.state.isEditing ?? false)
            XCTAssertTrue(journal.today?.content.contains("The day is ready.") ?? false)
            try await capture(window, named: "ready-dark", style: .dark)
            try await capture(window, named: "ready-light", style: .light)
        }
    }

    func testAFailedFolderLeavesTheSplashForRecovery() async throws {
        try await withTemporaryFolder { folders in
            let root = folders.appending(path: "not-a-folder")
            try Data("a file".utf8).write(to: root)
            let journal = makeJournal(root: root)
            let window = show(journal)
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            for _ in 0..<100 where journal.state == .opening {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard case .unavailable = journal.state else {
                XCTFail("A folder failure must replace the splash with recovery")
                return
            }
            try await capture(window, named: "recovery-light", style: .light)
            try await capture(window, named: "recovery-dark", style: .dark)
        }
    }

    func testTheSystemLaunchScreenMatchesTheLoadingScreen() async throws {
        let bundle = Bundle(for: Journal.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String, "LaunchScreen")
        let icons = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        let controller = try XCTUnwrap(UIStoryboard(name: "LaunchScreen", bundle: bundle).instantiateInitialViewController())
        let window = makeWindow(controller)
        defer { window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded()
        let icon = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertNotNil(icon.image)
        XCTAssertEqual(icon.bounds.width, 112, accuracy: 0.5)
        XCTAssertEqual(icon.center.x, controller.view.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(icon.center.y, controller.view.bounds.midY, accuracy: 0.5)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let actual = try XCTUnwrap(UIColor(named: "LaunchBackground", in: bundle, compatibleWith: traits))
            for (actual, expected) in zip(components(actual, traits), components(Palette.background, traits)) {
                XCTAssertEqual(actual, expected, accuracy: 0.00001)
            }
            try await capture(window, named: style == .dark ? "system-launch-dark" : "system-launch-light", style: style)
        }
    }

    private func makeJournal(
        root: URL,
        settings: JournalSettingsStore = .inMemory(),
        dayData: DayData = DayData()
    ) -> Journal {
        let device = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        device.update { $0.hasBeenWelcomed = true }
        return Journal(
            locator: JournalRootLocator(
                iCloudDocuments: { root }, onThisDeviceDocuments: { root },
                lastUsedLocation: { .iCloudDrive }, rememberLocation: { _ in }
            ),
            settings: settings, templateElsewhere: .unpicked, dayData: dayData,
            deviceSettings: device, nudges: ADeviceThatIsNeverRung()
        )
    }

    private func components(_ color: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    private func show(_ journal: Journal) -> UIWindow {
        let appearance = DeviceAppearance(settings: journal.deviceSettings)
        return makeWindow(UIHostingController(rootView:
            ContentView(journal: journal, appearance: appearance)
                .tint(appearance.accentColor)
                .environment(\.editorLook, appearance.editorLook)
        ))
    }

    private func makeWindow(_ controller: UIViewController) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    private func capture(_ window: UIWindow, named name: String, style: UIUserInterfaceStyle) async throws {
        window.overrideUserInterfaceStyle = style
        // Let SwiftUI commit the trait change for the screenshot, in tests only.
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private actor SuspendedLaunchItems: DayItemSource {
    nonisolated var access: DayDataAccess { .allowed }
    let reading: XCTestExpectation
    private var continuation: CheckedContinuation<[DayItem], Never>?
    private var released = false

    init(reading: XCTestExpectation) { self.reading = reading }

    func items(during day: DateInterval) async -> [DayItem] {
        reading.fulfill()
        if released { return [] }
        return await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume(returning: [])
        continuation = nil
    }
}
