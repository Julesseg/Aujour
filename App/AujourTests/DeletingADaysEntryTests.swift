import Foundation
import Testing

import AujourCore

@testable import Aujour

// Deleting a day's Entry — what the calendar does to the file, and what the
// Path Template says which file that is — is decided in Core and tested there
// against an in-memory folder. What is left is everything else a day leaving
// changes, over a real folder: the page that was over it, the search index,
// the reminder, and the marks.
//
// It is the one operation in Aujour that takes something away, so the claims
// worth making headlessly are the ones about it *not* coming back — an
// autosave that lands a moment late, a page whose next keystroke writes the
// old words where they were.
@MainActor
@Suite("Deleting a day's Entry from the open journal")
struct DeletingADaysEntryTests {
    @Test("the day's file goes, and the calendar stops marking it")
    func theFileAndTheMarkBothGo() async throws {
        try await withTemporaryFolder { folders in
            let journal = journal(in: folders)
            let day = yesterday
            try folders.appending(path: "iCloud/Documents")
                .seed("Rain all day.\n", at: PathTemplate.default.render(day))
            await journal.open()
            let calendar = try #require(journal.calendar)
            // What a calendar being put on screen does — the marks are a scan
            // of the folder and nothing else (ADR 0001).
            await calendar.scan()
            #expect(calendar.month.cells.first { $0.day == day }?.isJournaled == true)

            #expect(await journal.deleteTheEntry(for: day, onScreenIn: nil) == nil)

            #expect(calendar.month.cells.first { $0.day == day }?.isJournaled == false)
            #expect(try await #require(journal.store).listFiles().isEmpty)
        }
    }

    @Test("the page over the day goes back to being a day nobody has written")
    func thePageOverItIsPutBack() async throws {
        try await withTemporaryFolder { folders in
            // Today's, which is the page the app lives on and the only one an
            // editor is already open over.
            let journal = journal(in: folders)
            try folders.appending(path: "iCloud/Documents")
                .seed("Walked to the market.\n", at: PathTemplate.default.render(today))
            await journal.open()
            let editor = try #require(journal.today)
            #expect(editor.content == "Walked to the market.\n")

            #expect(await journal.deleteTheEntry(for: today, onScreenIn: editor) == nil)

            // Spawned afresh, and quiet — which is backfill, arrived at the
            // long way round. This journal has no Content Template, and a day
            // with no template is a blank page (ADR 0005).
            #expect(editor.content == "")
            #expect(editor.isUnwritten)
        }
    }

    @Test("words typed and not yet saved do not put the day back a moment later")
    func aPendingAutosaveDoesNotRestoreTheDay() async throws {
        try await withTemporaryFolder { folders in
            // The race this exists to lose: a keystroke that has not reached
            // the folder, and a delete on top of it. Whichever landed last
            // would decide whether the day is in the journal, and only one of
            // those is what anybody asked for.
            let journal = journal(in: folders)
            try folders.appending(path: "iCloud/Documents")
                .seed("Walked to the market.\n", at: PathTemplate.default.render(today))
            await journal.open()
            let editor = try #require(journal.today)
            editor.content = "Walked to the market, and then it rained.\n"

            #expect(await journal.deleteTheEntry(for: today, onScreenIn: editor) == nil)

            #expect(try await #require(journal.store).listFiles().isEmpty)
            #expect(editor.content == "")
            // And nothing lands afterwards either: what was in flight was
            // written before the file went, so there is no save left waiting.
            await editor.save()
            #expect(try await #require(journal.store).listFiles().isEmpty)
        }
    }

    @Test("the day stops being one a search finds")
    func theSearchIndexForgetsIt() async throws {
        try await withTemporaryFolder { folders in
            let journal = journal(in: folders)
            let day = yesterday
            try folders.appending(path: "iCloud/Documents")
                .seed("Walked to the market.\n", at: PathTemplate.default.render(day))
            await journal.open()
            let search = try #require(journal.search)
            await search.reindex()
            #expect(search.results(for: "market").map(\.day) == [day])

            #expect(await journal.deleteTheEntry(for: day, onScreenIn: nil) == nil)

            #expect(search.results(for: "market").isEmpty)
        }
    }

    @Test("deleting today's Entry makes today worth a nudge again")
    func theReminderComesBackForToday() async throws {
        try await withTemporaryFolder { folders in
            // Nothing else would ever say so: what the reminder asks about is
            // whether today's file exists, and it is asked at the moments the
            // app learns something new about the folder. A day deleted is one.
            let device = ADeviceToNudge()
            let journal = journal(in: folders, nudgedInto: device)
            try folders.appending(path: "iCloud/Documents")
                .seed("Walked to the market.\n", at: PathTemplate.default.render(today))
            await journal.open()
            #expect(!journal.dailyReminder.booked.map(\.day).contains(today))

            #expect(await journal.deleteTheEntry(for: today, onScreenIn: journal.today) == nil)

            #expect(journal.dailyReminder.booked.map(\.day).contains(today))
            #expect(device.booked == journal.dailyReminder.booked)
        }
    }

    @Test("a folder that will not let go of the day says so, and keeps the day")
    func aRefusalIsSaidAndChangesNothing() async throws {
        try await withTemporaryFolder { folders in
            let journal = journal(in: folders)
            let day = yesterday
            let root = folders.appending(path: "iCloud/Documents")
            try root.seed("Rain all day.\n", at: PathTemplate.default.render(day))
            await journal.open()
            let calendar = try #require(journal.calendar)
            await calendar.scan()

            // A folder nothing can be taken out of: readable, so the day is
            // still there and still marked, and not writable, so it cannot
            // leave. A vault on a read-only volume, or a permission the user
            // has since taken back.
            let enclosing = root
                .appending(path: PathTemplate.default.render(day), directoryHint: .notDirectory)
                .deletingLastPathComponent()
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: enclosing.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: enclosing.path
                )
            }

            let problem = await journal.deleteTheEntry(for: day, onScreenIn: nil)

            let said = try #require(problem)
            #expect(said.message.isEmpty == false)
            #expect(said.suggestion.isEmpty == false)
            // The day is still in the folder, so the calendar still says so — a
            // mark that came off a day whose file stayed would be the app
            // disagreeing with the folder (ADR 0001).
            #expect(calendar.month.cells.first { $0.day == day }?.isJournaled == true)
            #expect(try await #require(journal.store).fileExists(at: PathTemplate.default.render(day)))
        }
    }

    private var today: JournalDay {
        JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    }

    /// A day that is written and is not the one the app has an editor over —
    /// which is every day the calendar deletes but one.
    private var yesterday: JournalDay { today.adding(days: -1) }

    private func journal(
        in folders: URL,
        nudgedInto device: ADeviceToNudge = ADeviceToNudge()
    ) -> Journal {
        let deviceSettings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        // A minute to midnight, so today's own nudge is still ahead whenever
        // the suite happens to run.
        deviceSettings.update { $0.dailyReminder = TimeOfDay(hour: 23, minute: 59)! }
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
