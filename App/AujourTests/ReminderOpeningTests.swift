import AujourCore
import SwiftUI
import UIKit
import UserNotifications
import XCTest

@testable import Aujour

@MainActor
final class ReminderOpeningTests: XCTestCase {
    func testTheBookingNamesTheJournalDayRatherThanTheDeliveryDate() {
        let day = JournalDay(year: 2026, month: 3, day: 14)
        let delivery = day.adding(days: 1).startOfDay(in: .current).addingTimeInterval(3600)
        let request = DeviceNudges().request(for: Nudge(day: day, at: delivery))
        XCTAssertEqual(DeviceNudges.day(in: request.identifier), day)
    }

    func testOnlyAValidReminderTapRequestsADay() {
        let opening = ReminderOpening()
        for identifier in ["unrelated.2026-03-14", "aujour.dailyReminder.2026-02-30", "aujour.dailyReminder."] {
            opening.receive(identifier: identifier, action: UNNotificationDefaultActionIdentifier)
            XCTAssertNil(opening.request)
        }
        opening.receive(identifier: "aujour.dailyReminder.2026-03-14", action: UNNotificationDismissActionIdentifier)
        XCTAssertNil(opening.request)
        opening.receive(identifier: "aujour.dailyReminder.2026-03-14", action: UNNotificationDefaultActionIdentifier)
        XCTAssertEqual(opening.request?.day, JournalDay(year: 2026, month: 3, day: 14))
    }

    func testAnOlderRequestCannotConsumeANewerTapOnTheSameDay() throws {
        let opening = ReminderOpening()
        opening.receive(identifier: "aujour.dailyReminder.2026-03-14", action: UNNotificationDefaultActionIdentifier)
        let first = try XCTUnwrap(opening.request)
        opening.receive(identifier: "aujour.dailyReminder.2026-03-14", action: UNNotificationDefaultActionIdentifier)
        opening.consume(first)
        XCTAssertNotNil(opening.request)
    }

    func testATapBeforeTheJournalOpensReachesItsDay() async throws {
        try await checkOpening(beforeLaunch: true)
    }

    func testATapWhileTheJournalIsOpenReachesItsDay() async throws {
        try await checkOpening(beforeLaunch: false)
    }

    func testATapWaitsUntilTheSceneReturnsToTheForeground() async throws {
        try await checkOpening(beforeLaunch: false, fromBackground: true)
    }

    private func checkOpening(beforeLaunch: Bool, fromBackground: Bool = false) async throws {
        try await withTemporaryFolder { root in
            let day = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight).adding(days: -2)
            try root.seed("The day the notification asked about.", at: PathTemplate.default.render(day))
            let device = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
            device.update { $0.hasBeenWelcomed = true }
            let journal = Journal(
                locator: JournalRootLocator(
                    iCloudDocuments: { root }, onThisDeviceDocuments: { root },
                    lastUsedLocation: { .iCloudDrive }, rememberLocation: { _ in }
                ),
                settings: .inMemory(), templateElsewhere: .unpicked,
                deviceSettings: device, nudges: ADeviceThatIsNeverRung()
            )
            let opening = ReminderOpening()
            let identifier = DeviceNudges().request(for: Nudge(day: day, at: .now)).identifier
            if beforeLaunch {
                opening.receive(identifier: identifier, action: UNNotificationDefaultActionIdentifier)
            }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let previous = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            let appearance = DeviceAppearance(settings: device)
            let screen = { (phase: ScenePhase) in
                ContentView(journal: journal, appearance: appearance, reminderOpening: opening)
                    .environment(\.scenePhase, phase)
                    .environment(\.editorLook, appearance.editorLook)
            }
            let host = UIHostingController(rootView: screen(fromBackground ? .background : .active))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previous?.makeKey()
            }
            if !beforeLaunch {
                for _ in 0..<200 where !journal.isOpen {
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertTrue(journal.isOpen)
                opening.receive(identifier: identifier, action: UNNotificationDefaultActionIdentifier)
                if fromBackground {
                    try await Task.sleep(for: .milliseconds(100))
                    XCTAssertNotNil(opening.request)
                    XCTAssertNotEqual(journal.calendar?.dayBeingWritten, day)
                    host.rootView = screen(.active)
                }
            }
            for _ in 0..<200 where journal.calendar?.dayBeingWritten != day || opening.request != nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(journal.calendar?.dayBeingWritten, day)
            XCTAssertNil(opening.request)
            for _ in 0..<100 where !editors(in: window).contains(where: { $0.text == "The day the notification asked about." }) {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(editors(in: window).contains(where: { $0.text == "The day the notification asked about." }))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = beforeLaunch ? "reminder-cold-opening" : fromBackground ? "reminder-foreground" : "reminder-open-journal"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func editors(in view: UIView) -> [UITextView] {
        (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { editors(in: $0) }
    }
}
