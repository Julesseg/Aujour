import Foundation
import Testing

import AujourCore

@testable import Aujour

// Which page the welcome is on and what its offer means are decided in Core
// and tested there. What is left is the promise the whole first run is made of
// and only a real folder can show: while those three pages are on screen,
// Aujour has already found somewhere to write and opened today's Entry over it
// — so the welcome ending is the app being ready rather than the app starting
// to get ready.
@MainActor
@Suite("The welcome over the open journal")
struct WelcomeWiringTests {
    @Test("a fresh install is due a welcome, with today's entry already open behind it")
    func nothingHasToBeConfiguredFirst() async throws {
        try await withTemporaryFolder { folders in
            let journal = journal(in: folders, nudgedInto: ADeviceToNudge())

            await journal.open()

            #expect(journal.welcome.isDue)
            // Nobody has answered anything, and the journal is open over a
            // folder Aujour found for itself with today's Entry spawned onto
            // the screen behind the cover (ADR 0004).
            #expect(journal.today != nil)
            #expect(journal.store != nil)
            if case .open = journal.state {} else {
                Issue.record("the journal was not open behind the welcome: \(journal.state)")
            }
        }
    }

    @Test("the first entry is written with nothing configured, into the folder Aujour found")
    func theFirstEntryTakesNoConfiguring() async throws {
        try await withTemporaryFolder { folders in
            let journal = journal(in: folders, nudgedInto: ADeviceToNudge())
            await journal.open()

            // Everything a first run does, in order: the welcome is skipped,
            // and the words go straight into today's Entry.
            await journal.endTheWelcome(remindingAt: nil)
            let editor = try #require(journal.today)
            editor.content = "Walked to the market.\n"
            await editor.save()

            let entry = folders
                .appending(path: "iCloud/Documents")
                .appending(path: PathTemplate.default.render(today))
            #expect(FileManager.default.fileExists(atPath: entry.path))
            #expect(try String(contentsOf: entry, encoding: .utf8) == "Walked to the market.\n")
        }
    }

    @Test("taking the offer up sets the time and leaves the week booked")
    func takingTheOfferUp() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            let journal = journal(in: folders, nudgedInto: device)
            await journal.open()
            #expect(device.booked.isEmpty)

            await journal.endTheWelcome(remindingAt: TimeOfDay(hour: 21, minute: 0))

            // Set *and* booked, which is the whole reason ending the welcome
            // goes through the Journal: a time written down with nothing
            // pending is a reminder that would not arrive until the next
            // launch.
            #expect(journal.dailyReminder.time == TimeOfDay(hour: 21, minute: 0))
            #expect(device.booked.count == DailyReminder.daysBookedAhead)
            #expect(device.timesAsked == 1)
            #expect(!journal.welcome.isDue)
        }
    }

    @Test("skipping the offer leaves the reminder off and the device unasked")
    func skippingTheOffer() async throws {
        try await withTemporaryFolder { folders in
            let device = ADeviceToNudge()
            let journal = journal(in: folders, nudgedInto: device)
            await journal.open()

            await journal.endTheWelcome(remindingAt: nil)

            #expect(journal.dailyReminder.time == nil)
            #expect(device.booked.isEmpty)
            // The promise the first run is judged on: an app that has never
            // nudged anybody who did not ask it to has also never put a
            // notification permission alert in front of them.
            #expect(device.timesAsked == 0)
            #expect(!journal.welcome.isDue)
        }
    }

    @Test("a welcome that has been answered does not come back next launch")
    func overForGood() async throws {
        try await withTemporaryFolder { folders in
            // One device's settings across both journals, which is what a
            // relaunch is: the folder is opened again, and what the device
            // remembers is still what it remembers.
            let device = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
            let first = journal(in: folders, nudgedInto: ADeviceToNudge(), settings: device)
            await first.open()
            await first.endTheWelcome(remindingAt: nil)

            let second = journal(in: folders, nudgedInto: ADeviceToNudge(), settings: device)
            await second.open()

            #expect(!second.welcome.isDue)
        }
    }

    /// The Journal Day it is — the day a first entry belongs to, read the way
    /// the app reads it.
    private var today: JournalDay {
        JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    }

    private func journal(
        in folders: URL,
        nudgedInto device: ADeviceToNudge,
        settings: DeviceSettingsStore? = nil
    ) -> Journal {
        Journal(
            locator: .test(
                iCloudDocuments: folders.appending(path: "iCloud/Documents"),
                folders: folders
            ),
            settings: .inMemory(),
            templateElsewhere: .unpicked,
            // Nothing seeded into it: a device nobody has welcomed and no
            // reminder, which is a fresh install.
            deviceSettings: settings ?? DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device
        )
    }
}
