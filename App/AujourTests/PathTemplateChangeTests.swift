import Foundation
import Testing
import AujourCore

@testable import Aujour

// Changing where entries go, over a real folder. What the change *is* — which
// file moves where, and what happens when something is already at a day's new
// path — is arithmetic, and lives in Core with the rest of it. What is left
// here is the part only a running app has: today's words are written before
// anything moves, the files land, and the journal comes back open onto them.

/// A vault that keeps its daily notes in one flat folder — where somebody
/// pointing Aujour at an Obsidian vault would want their entries to go.
private let flat = try! PathTemplate("[Journal]/YYYY-MM-DD")

@MainActor
@Suite("Changing where entries go")
struct PathTemplateChangeTests {
    @Test("moving the entries puts every one of them where the new template says")
    func theEntriesMoveToTheNewTemplate() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try iCloud.seed("Rain all day.\n", at: "2026/02/2026-02-28.md")
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory()
            )
            await journal.open()

            let plan = try await journal.planChangingThePathTemplate(to: flat)
            let outcome = await journal.changeThePathTemplate(to: flat, movingEntriesBy: plan)

            #expect(outcome?.moved.count == 2)
            let moved = try String(
                contentsOf: iCloud.appending(path: "Journal/2026-03-01.md"),
                encoding: .utf8
            )
            #expect(moved == "Walked to the market.\n")
            #expect(!FileManager.default.fileExists(atPath: iCloud.appending(path: "2026/03/2026-03-01.md").path))
            // And the journal is open onto them: they are Entries again,
            // under the template that is now in force.
            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 2))
            #expect(journal.pathTemplate == flat.format)
        }
    }

    @Test("today's unsaved words go with the migration rather than staying behind")
    func todaysWordsAreWrittenBeforeAnythingMoves() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory()
            )
            await journal.open()
            // Typed and not yet autosaved — today's Entry is not even a file.
            let today = try #require(journal.today)
            today.content = "Written just before changing the path.\n"

            let plan = try await journal.planChangingThePathTemplate(to: flat)
            await journal.changeThePathTemplate(to: flat, movingEntriesBy: plan)

            let reopened = try #require(journal.today)
            #expect(reopened.content == "Written just before changing the path.\n")
            let atTheNewPath = try String(
                contentsOf: iCloud.appending(path: flat.render(reopened.day)),
                encoding: .utf8
            )
            #expect(atTheNewPath == "Written just before changing the path.\n")
        }
    }

    @Test("a day whose new path is taken keeps both files, and the one there stays the entry")
    func acollisionKeepsBothAndParksTheIncomingFile() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("What Aujour has for the 1st.\n", at: "2026/03/2026-03-01.md")
            try iCloud.seed("What the vault already had.\n", at: "Journal/2026-03-01.md")
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory()
            )
            await journal.open()

            let plan = try await journal.planChangingThePathTemplate(to: flat)
            #expect(plan.collisions.count == 1)
            let outcome = await journal.changeThePathTemplate(to: flat, movingEntriesBy: plan)

            #expect(outcome?.parked.map(\.name) == ["2026-03-01_1.md"])
            let stayed = try String(
                contentsOf: iCloud.appending(path: "Journal/2026-03-01.md"),
                encoding: .utf8
            )
            let parked = try String(
                contentsOf: iCloud.appending(path: "Journal/2026-03-01_1.md"),
                encoding: .utf8
            )
            #expect(stayed == "What the vault already had.\n")
            #expect(parked == "What Aujour has for the 1st.\n")
            // One day, one Entry: the Parked File beside it is not one
            // (ADR 0002). Today's Entry is the other.
            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 1))
        }
    }

    @Test("skipping leaves every file where it was, and none of them is an entry afterwards")
    func skippingLeavesTheFilesAndUnsurfacesThem() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try iCloud.seed("Rain all day.\n", at: "2026/02/2026-02-28.md")
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory()
            )
            await journal.open()

            await journal.changeThePathTemplate(to: flat, movingEntriesBy: nil)

            // The files are exactly as they were — nothing is ever deleted
            // (ADR 0001) — and none of them is an Entry any more, so nothing
            // in the app surfaces them.
            let untouched = try String(
                contentsOf: iCloud.appending(path: "2026/03/2026-03-01.md"),
                encoding: .utf8
            )
            #expect(untouched == "Walked to the market.\n")
            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 0))

            let calendar = try #require(journal.calendar)
            await calendar.scan()
            #expect(calendar.month.days.allSatisfy { !$0.isJournaled })
        }
    }

    @Test("entry identity follows the new template at once, on the day being written")
    func todaysEntryIsAtItsNewPathImmediately() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory()
            )
            await journal.open()

            await journal.changeThePathTemplate(to: flat, movingEntriesBy: nil)

            let today = try #require(journal.today)
            today.content = "The first words under the new path.\n"
            await today.save()

            let written = try String(
                contentsOf: iCloud.appending(path: flat.render(today.day)),
                encoding: .utf8
            )
            #expect(written == "The first words under the new path.\n")
        }
    }

    @Test("a template changed on another device reshapes this one without being asked")
    func aTemplateArrivingFromAnotherDeviceIsAdopted() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("Already moved by the iPad.\n", at: "Journal/2026-03-01.md")
            let kvs = InMemorySyncedKeyValueStore()
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: JournalSettingsStore(syncedThrough: kvs)
            )
            await journal.open()
            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 0))

            // The iPad changed the template and moved the files; iCloud
            // brings the setting down. Nothing here migrates anything — the
            // other device already did (ADR 0003).
            kvs.receiveFromAnotherDevice(["aujour.journal.pathTemplate": flat.format])
            // The reopening the change set going, waited out the way a screen
            // would wait for it: by looking again.
            try await untilTheJournalHolds(1, in: journal)

            #expect(journal.pathTemplate == flat.format)
            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 1))
        }
    }

    /// Waits for the journal to be open onto this many Entries.
    ///
    /// A settings change reopens the journal on a task of its own, so there is
    /// a moment where the count is the old one — the same moment a screen sees
    /// as a spinner.
    private func untilTheJournalHolds(_ entries: Int, in journal: Journal) async throws {
        for _ in 0..<100 {
            if case .open(_, let count) = journal.state, count == entries { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("the journal never reopened onto \(entries) entries — it is \(journal.state)")
    }
}
