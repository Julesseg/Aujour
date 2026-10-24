import Foundation
import Testing
import UserNotifications

import AujourCore

@testable import Aujour

// What the daily reminder should be asking about is decided in Core, against
// an in-memory folder, and tested there. What is left is the wiring: the
// reminder is a question about a *folder* — which day is current, and whether
// that day's file exists — so every moment the app learns something new about
// the folder has to be a moment the reminder is reckoned again. These are
// those moments, over a real one.
@MainActor
@Suite("The daily reminder over the open journal")
struct DailyReminderWiringTests {
    @Test("A notification tap has a handler when the app launches")
    func notificationTapHasAHandler() throws {
        let delegate = try #require(UNUserNotificationCenter.current().delegate)
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))))
    }

    @Test("opening the journal is what books the reminder")
    func openingBooksIt() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            let journal = journal(in: folders, nudgedInto: device, remindingAt: lateTonight)

            await journal.open()

            // Nothing is written in this folder, so every day of the week
            // ahead is one worth asking about — and the device is holding
            // exactly what the reminder decided, which is the only list it is
            // ever handed.
            #expect(journal.dailyReminder.booked.count == DailyReminder.daysBookedAhead)
            #expect(device.booked == journal.dailyReminder.booked)
        }
    }

    @Test("the day just written is not one the reminder goes on asking about")
    func writingTodayDropsTodaysNudge() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            device.delivered = [today]
            let journal = journal(in: folders, nudgedInto: device, remindingAt: lateTonight)
            await journal.open()

            #expect(device.delivered == [today])

            let editor = try #require(journal.today)
            editor.content = "Walked to the market.\n"
            await editor.save()

            #expect(!journal.dailyReminder.booked.map(\.day).contains(today))
            #expect(!device.booked.map(\.day).contains(today))
            #expect(device.delivered.isEmpty)
        }
    }

    @Test("backfilled days dismiss their delivered reminders as soon as they save", arguments: [false, true])
    func backfillingDismissesItsReminder(fromCalendar: Bool) async throws {
        try await withTemporaryFolder { folders in
            let day = today.adding(days: -3)
            let unwritten = day.adding(days: 1)
            let device = ADeviceToNudge()
            device.delivered = [day, unwritten]
            let journal = journal(in: folders, nudgedInto: device, remindingAt: nil)
            await journal.open()
            let editor = try #require(
                fromCalendar ? journal.calendar?.editor(for: day) : journal.editor(for: day)
            )
            await editor.open()
            await editor.save()
            #expect(device.delivered == [day, unwritten])

            editor.content = "A few words about Monday.\n"
            await editor.save()

            #expect(device.delivered == [unwritten])
            #expect(device.booked.isEmpty)
        }
    }

    @Test("a failed save leaves its delivered reminder in place")
    func failedSaveKeepsTheReminder() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            device.delivered = [today]
            let journal = journal(in: folders, nudgedInto: device, remindingAt: nil)
            await journal.open()
            let editor = try #require(journal.today)
            let entry = folders.appending(path: "iCloud/Documents")
                .appending(path: PathTemplate.default.render(today))
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)

            editor.content = "These words could not be saved.\n"
            await editor.save()

            #expect(editor.saveProblem != nil)
            #expect(device.delivered == [today])
        }
    }

    @Test("a day another app wrote while Aujour was open is dropped too")
    func aDayWrittenElsewhereDropsItsNudge() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            device.delivered = [today]
            let journal = journal(in: folders, nudgedInto: device, remindingAt: lateTonight)
            await journal.open()

            try folders.appending(path: "iCloud/Documents")
                .seed("Written in Obsidian.\n", at: PathTemplate.default.render(today))
            await journal.cameBackToTheFront()

            #expect(!device.booked.map(\.day).contains(today))
            #expect(device.delivered.isEmpty)
        }
    }

    @Test("turning the reminder off takes away what was already pending")
    func turningItOffClearsWhatWasBooked() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            let journal = journal(in: folders, nudgedInto: device, remindingAt: nil)
            await journal.open()

            await journal.remindMeDaily(at: lateTonight)
            #expect(!device.booked.isEmpty)

            await journal.remindMeDaily(at: nil)

            #expect(device.booked.isEmpty)
            #expect(journal.dailyReminder.time == nil)
            #expect(device.timesAsked == 1, "turning it off is not a question")
        }
    }

    @Test("a reminder nobody has set a time for leaves the device holding nothing")
    func noTimeChosenBooksNothing() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            let journal = journal(in: folders, nudgedInto: device, remindingAt: nil)

            await journal.open()

            #expect(device.booked.isEmpty)
            // Booked all the same: an empty list is what takes away whatever a
            // previous launch left pending.
            #expect(device.bookings == 1)
            #expect(device.timesAsked == 0)
        }
    }

    /// The Journal Day it is, which is the one the reminder would be asking
    /// about — read the same way the app reads it.
    private var today: JournalDay {
        JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    }

    /// A minute to midnight, so that today's own nudge is still ahead whenever
    /// the suite happens to run — which is what leaves "today is not asked
    /// about" a claim about the Entry rather than about the clock.
    private var lateTonight: TimeOfDay { TimeOfDay(hour: 23, minute: 59)! }

    private func journal(
        in folders: URL,
        nudgedInto device: ADeviceToNudge,
        remindingAt time: TimeOfDay?
    ) -> Journal {
        let deviceSettings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        deviceSettings.update { $0.dailyReminder = time }
        return Journal(
            locator: .test(
                iCloudDocuments: folders.appending(path: "iCloud/Documents"),
                folders: folders
            ),
            settings: .inMemory(),
            templateElsewhere: .unpicked,
            deviceSettings: deviceSettings,
            nudges: device
        )
    }
}
