import AujourCore
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class ReminderOpening {
    struct Request: Equatable {
        let id = UUID()
        let day: JournalDay
    }

    private(set) var request: Request?

    func receive(identifier: String, action: String) {
        guard action == UNNotificationDefaultActionIdentifier,
            let day = DeviceNudges.day(in: identifier)
        else { return }
        request = Request(day: day)
    }

    func consume(_ request: Request) {
        guard self.request == request else { return }
        self.request = nil
    }
}

final class AujourAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let reminderOpening = ReminderOpening()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        await reminderOpening.receive(identifier: identifier, action: action)
    }
}
