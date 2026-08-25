import UserNotifications

import AujourCore

/// The device's notification centre, as the daily reminder's seam over it.
///
/// The whole of Aujour's dealings with notifications, and deliberately so
/// small: one gentle reminder a day is the only thing this app ever puts in
/// front of somebody who is not looking at it, so there is nothing here to
/// categorise, no action to attach, and no badge — a number on the icon is a
/// count of days not written, which is the reproach the reminder exists not to
/// be.
///
/// ``book(_:)`` clears everything pending before it adds anything, which is
/// what makes "no other notifications of any kind" true by construction rather
/// than by inspection: there is no way through this type to leave a request
/// behind that the domain did not just ask for.
struct DeviceNudges: Nudges {
    /// What every request Aujour schedules is named after — the day it asks
    /// about, so that the identifiers are the days and a second request for
    /// one day is impossible.
    private static let namedFor = "aujour.dailyReminder"

    /// A banner and a sound, and nothing else. No badge, for the reason there
    /// is no badge in the content below.
    private static let asked: UNAuthorizationOptions = [.alert, .sound]

    func access() async -> NudgeAccess {
        switch await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
        {
        case .notDetermined: .undecided
        case .authorized, .provisional, .ephemeral: .allowed
        // `.denied`, and whatever a future iOS adds. A permission Aujour
        // cannot recognise is one it must not act as though it had.
        default: .refused
        }
    }

    func ask() async -> NudgeAccess {
        let allowed =
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: Self.asked))
            ?? false
        return allowed ? .allowed : .refused
    }

    func book(_ nudges: [Nudge]) async {
        let centre = UNUserNotificationCenter.current()
        centre.removeAllPendingNotificationRequests()
        for nudge in nudges {
            try? await centre.add(request(for: nudge))
        }
    }

    private func request(for nudge: Nudge) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = nudge.heading
        content.body = nudge.words
        content.sound = .default

        // A calendar trigger rather than a count of seconds: the reminder is a
        // time on a clock, and a device whose clock or zone moves before it
        // arrives should still ask at the time the user chose.
        let when = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nudge.at
        )
        return UNNotificationRequest(
            identifier: "\(Self.namedFor).\(nudge.day)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )
    }
}

/// A device that takes the daily reminder's bookings and rings nobody.
///
/// For a UI test and for a preview, which are the two things that open a
/// journal without being the app: a real booking would put notifications on
/// the simulator — or on the machine drawing the canvas — that outlive
/// whatever made them, and asking to be allowed would put a system alert from
/// another process in the middle of a test.
///
/// Allowed rather than refused, so that what is on screen is what somebody who
/// had said yes would see.
struct ADeviceThatIsNeverRung: Nudges {
    func access() async -> NudgeAccess { .allowed }

    func ask() async -> NudgeAccess { .allowed }

    func book(_ nudges: [Nudge]) async {}
}
