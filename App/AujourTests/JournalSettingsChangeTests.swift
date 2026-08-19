import Foundation
import Testing
import AujourCore

@testable import Aujour

// Changing a journal-shaping setting from the app, over a real folder. What
// each setting *means* is Core's and proved there; what is left here is what
// changing one does to the journal that is open — which words are written
// where before the ground moves, and what the folder holds afterwards.

@MainActor
@Suite("Changing what shapes the journal")
struct JournalSettingsChangeTests {
    @Test("a new Content Template is what today starts as, when today is still unwritten")
    func anUnwrittenTodayIsRespawnedFromTheNewTemplate() async throws {
        try await withAJournal { journal, root in
            await journal.open()
            #expect(journal.today?.content == "")

            await journal.changeTheContentTemplate(to: "## Morning\n\n## Evening\n")

            #expect(journal.today?.content == "## Morning\n\n## Evening\n")
            // And still nothing in the folder: a day nobody has written is a
            // day with no file, whatever it is showing (ADR 0001).
            let inTheFolder = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(inTheFolder.isEmpty)
        }
    }

    @Test("a day already written keeps its words when the Content Template changes")
    func wordsAreNeverReplacedByANewTemplate() async throws {
        try await withAJournal { journal, root in
            await journal.open()
            let today = try #require(journal.today)
            today.content = "Walked to the market.\n"

            await journal.changeTheContentTemplate(to: "## Morning\n")

            // The words were written on the way through, and read back from
            // the file — a template is what a day starts as, not what it
            // becomes.
            #expect(journal.today?.content == "Walked to the market.\n")
            let written = try String(
                contentsOf: root.appending(path: PathTemplate.default.render(today.day)),
                encoding: .utf8
            )
            #expect(written == "Walked to the market.\n")
        }
    }

    @Test("the Rollover Hour changes which day is being written, and the entries stay put")
    func theDayFollowsTheRolloverHour() async throws {
        try await withAJournal { journal, _ in
            await journal.open()
            let atMidnight = try #require(journal.today?.day)

            // 11 at night: for every hour of the day but that one, today's
            // Journal Day is yesterday's date afterwards.
            let lateRollover = try #require(RolloverHour(hour: 23))
            await journal.changeTheRolloverHour(to: lateRollover)

            #expect(journal.rolloverHour == lateRollover)
            #expect(
                journal.today?.day
                    == JournalDay.current(at: Date(), in: .current, rolloverHour: lateRollover)
            )
            // Said as the claim rather than as arithmetic: before 11 at night
            // the day being written has gone back one.
            if Calendar.current.component(.hour, from: Date()) < 23 {
                #expect(journal.today?.day != atMidnight)
            }
        }
    }

    @Test("words typed under one Rollover Hour are written to the day they were written in")
    func wordsGoToTheDayTheyWereWrittenIn() async throws {
        try await withAJournal { journal, root in
            await journal.open()
            let today = try #require(journal.today)
            let dayBeingWritten = today.day
            today.content = "Written before the day was moved.\n"

            await journal.changeTheRolloverHour(to: try #require(RolloverHour(hour: 23)))

            let written = try String(
                contentsOf: root.appending(path: PathTemplate.default.render(dayBeingWritten)),
                encoding: .utf8
            )
            #expect(written == "Written before the day was moved.\n")
        }
    }

    @Test("where photos go changes for the next one, and moves none of the ones there")
    func theAttachmentFolderChangesForTheNextPhotograph() async throws {
        try await withAJournal { journal, root in
            try root.seed("a picture, near enough", at: "attachments/2026/03/2026-03-01.jpg")
            await journal.open()

            let assets = try AttachmentPathTemplate("[assets]")
            await journal.changeTheAttachmentPathTemplate(to: assets)

            #expect(journal.attachmentPathTemplate == "[assets]")
            // The day that embeds it names where it is; a picture that moved
            // would leave that day pointing at nothing.
            #expect(
                FileManager.default.fileExists(
                    atPath: root.appending(path: "attachments/2026/03/2026-03-01.jpg").path
                )
            )
        }
    }

    /// A journal over a folder of its own, with settings that live and die
    /// with the test — never this machine's real ones.
    private func withAJournal(_ body: (Journal, URL) async throws -> Void) async throws {
        try await withTemporaryFolder { folders in
            let root = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try await body(
                Journal(
                    locator: .test(iCloudDocuments: root, folders: folders),
                    settings: .inMemory()
                ),
                root
            )
        }
    }
}
