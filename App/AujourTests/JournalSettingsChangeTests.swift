import Foundation
import Testing
import AujourCore

@testable import Aujour

// Changing a journal-shaping setting from the app, over a real folder. What
// each setting *means* is Core's and proved there; what is left here is what
// changing one does to the journal that is open — which words are written
// where before the ground moves, what the folder holds afterwards, and, for
// the Content Template, how a file the user pointed at is reached at all.

@MainActor
@Suite("Changing what shapes the journal")
struct JournalSettingsChangeTests {
    @Test("a template file inside the folder is what today starts from, and travels")
    func aTemplateInsideTheFolderIsSpawnedFromAndSynced() async throws {
        try await withAJournal { aujour in
            try aujour.root.seed("## Morning\n\n## Evening\n", at: "templates/Daily.md")
            await aujour.journal.open()
            #expect(aujour.journal.today?.content == "")

            await aujour.journal.useAsTheContentTemplate(
                aujour.root.appending(path: "templates/Daily.md")
            )

            #expect(aujour.journal.today?.content == "## Morning\n\n## Evening\n")
            // Inside the folder, so it is a path the user's other devices can
            // follow — the folder syncs, and the file goes with it (ADR 0003).
            #expect(aujour.settings.settings.contentTemplateFile == "templates/Daily.md")
            #expect(aujour.journal.contentTemplateName == "templates/Daily.md")
            #expect(aujour.journal.theTemplateIsOutOfReach == false)
        }
    }

    @Test("a template file anywhere else is spawned from too, and stays on this device")
    func aTemplateOutsideTheFolderIsSpawnedFromAndKeptLocal() async throws {
        try await withAJournal { aujour in
            // Somewhere else entirely: not in the journal folder, and reachable
            // only through the bookmark the pick leaves behind (ADR 0005).
            try aujour.folders.seed("# {{title}}\n\nWoke at {{time}}.\n", at: "Notes/Daily.md")

            await aujour.journal.open()
            await aujour.journal.useAsTheContentTemplate(
                aujour.folders.appending(path: "Notes/Daily.md")
            )

            #expect(aujour.journal.today?.content.hasPrefix("# ") == true)
            #expect(aujour.journal.contentTemplateName == "Daily.md")
            // And nothing about it travels: a bookmark means nothing on the
            // iPad, so the synced setting stays empty rather than naming a
            // path that device would read as one of its own (ADR 0003).
            #expect(aujour.settings.settings.contentTemplateFile.isEmpty)
            #expect(aujour.bookmark.isSet)
        }
    }

    @Test("the template is read where it lies on the next launch too")
    func aTemplateOutsideTheFolderSurvivesARelaunch() async throws {
        try await withAJournal { aujour in
            try aujour.folders.seed("# Yesterday's shape\n", at: "Notes/Daily.md")
            await aujour.journal.open()
            await aujour.journal.useAsTheContentTemplate(
                aujour.folders.appending(path: "Notes/Daily.md")
            )

            // The file changes under the app, the way it does when it is
            // edited in Obsidian — and the app relaunches over the same
            // bookmark.
            try aujour.folders.seed("# Today's shape\n", at: "Notes/Daily.md")
            let afterARelaunch = Journal(
                locator: .test(iCloudDocuments: aujour.root, folders: aujour.folders),
                settings: aujour.settings,
                templateElsewhere: aujour.bookmark
            )
            await afterARelaunch.open()

            #expect(afterARelaunch.today?.content == "# Today's shape\n")
        }
    }

    @Test("picking no template at all leaves the day blank, and forgets the file")
    func noTemplateLeavesTheDayBlank() async throws {
        try await withAJournal { aujour in
            try aujour.folders.seed("# {{title}}\n", at: "Notes/Daily.md")
            await aujour.journal.open()
            await aujour.journal.useAsTheContentTemplate(
                aujour.folders.appending(path: "Notes/Daily.md")
            )

            await aujour.journal.useAsTheContentTemplate(nil)

            #expect(aujour.journal.today?.content == "")
            #expect(aujour.journal.contentTemplateName == nil)
            #expect(aujour.bookmark.isSet == false)
        }
    }

    @Test("a template picked while a day has words never replaces them")
    func wordsAreNeverReplacedByANewTemplate() async throws {
        try await withAJournal { aujour in
            try aujour.root.seed("## Morning\n", at: "templates/Daily.md")
            await aujour.journal.open()
            let today = try #require(aujour.journal.today)
            today.content = "Walked to the market.\n"

            await aujour.journal.useAsTheContentTemplate(
                aujour.root.appending(path: "templates/Daily.md")
            )

            // The words were written on the way through, and read back from
            // the file — a template is what a day starts as, not what it
            // becomes.
            #expect(aujour.journal.today?.content == "Walked to the market.\n")
            let written = try String(
                contentsOf: aujour.root.appending(path: PathTemplate.default.render(today.day)),
                encoding: .utf8
            )
            #expect(written == "Walked to the market.\n")
        }
    }

    @Test("the Rollover Hour changes which day is being written, and the entries stay put")
    func theDayFollowsTheRolloverHour() async throws {
        try await withAJournal { aujour in
            await aujour.journal.open()
            let atMidnight = try #require(aujour.journal.today?.day)

            // 11 at night: for every hour of the day but that one, today's
            // Journal Day is yesterday's date afterwards.
            let lateRollover = try #require(RolloverHour(hour: 23))
            await aujour.journal.changeTheRolloverHour(to: lateRollover)

            #expect(aujour.journal.rolloverHour == lateRollover)
            #expect(
                aujour.journal.today?.day
                    == JournalDay.current(at: Date(), in: .current, rolloverHour: lateRollover)
            )
            // Said as the claim rather than as arithmetic: before 11 at night
            // the day being written has gone back one.
            if Calendar.current.component(.hour, from: Date()) < 23 {
                #expect(aujour.journal.today?.day != atMidnight)
            }
        }
    }

    @Test("words typed under one Rollover Hour are written to the day they were written in")
    func wordsGoToTheDayTheyWereWrittenIn() async throws {
        try await withAJournal { aujour in
            await aujour.journal.open()
            let today = try #require(aujour.journal.today)
            let dayBeingWritten = today.day
            today.content = "Written before the day was moved.\n"

            await aujour.journal.changeTheRolloverHour(to: try #require(RolloverHour(hour: 23)))

            let written = try String(
                contentsOf: aujour.root.appending(
                    path: PathTemplate.default.render(dayBeingWritten)
                ),
                encoding: .utf8
            )
            #expect(written == "Written before the day was moved.\n")
        }
    }

    @Test("where photos go changes for the next one, and moves none of the ones there")
    func theAttachmentFolderChangesForTheNextPhotograph() async throws {
        try await withAJournal { aujour in
            try aujour.root.seed("a picture, near enough", at: "attachments/2026/03/2026-03-01.jpg")
            await aujour.journal.open()

            let assets = try AttachmentPathTemplate("[assets]")
            await aujour.journal.changeTheAttachmentPathTemplate(to: assets)

            #expect(aujour.journal.attachmentPathTemplate == "[assets]")
            // The day that embeds it names where it is; a picture that moved
            // would leave that day pointing at nothing.
            #expect(
                FileManager.default.fileExists(
                    atPath: aujour.root.appending(path: "attachments/2026/03/2026-03-01.jpg").path
                )
            )
        }
    }

    @Test("how a data placeholder writes itself reaches the seam and the next spawn")
    func changingAPlaceholderFormatReachesTheNextSpawn() async throws {
        let yesterdaysList = ADayOfItems([
            DayItem(title: "Call the plumber", isDone: false),
            DayItem(title: "Buy bread", isDone: true),
        ])
        try await withAJournal(holding: DayData([.reminders: yesterdaysList])) { aujour in
            try aujour.root.seed("## To do\n{{reminders}}\n", at: "Daily.md")
            await aujour.journal.open()
            await aujour.journal.useAsTheContentTemplate(aujour.root.appending(path: "Daily.md"))

            await aujour.journal.changeHowItIsWritten(
                .reminders,
                to: DataPlaceholderFormat(
                    linePrefix: "* ",
                    donePrefix: "* ~~",
                    timeFormat: nil,
                    whenEmpty: "Nothing on the list."
                )
            )

            // The seam the user's other device reads (ADR 0003).
            #expect(aujour.settings.settings.dataPlaceholders[.reminders].linePrefix == "* ")
            #expect(aujour.settings.settings.dataPlaceholders[.reminders].donePrefix == "* ~~")
            #expect(aujour.journal.howItIsWritten(.reminders).whenEmpty == "Nothing on the list.")

            // And what the next day spawned is written with — a day with no
            // file yet, which is the only kind a spawn happens for.
            let editor = try #require(aujour.journal.editor(for: aujour.journal.dayOnScreen.adding(days: -3)))
            await editor.open()
            #expect(editor.content == "## To do\n* Call the plumber\n* ~~Buy bread\n")
        }
    }

    @Test("a day that held nothing is spawned with the empty text rather than a gap")
    func aDayThatHeldNothingSaysSo() async throws {
        try await withAJournal(holding: DayData([.events: ADayOfItems([])])) { aujour in
            try aujour.root.seed("## Today\n{{events}}\n", at: "Daily.md")
            await aujour.journal.open()
            await aujour.journal.useAsTheContentTemplate(aujour.root.appending(path: "Daily.md"))

            await aujour.journal.changeHowItIsWritten(
                .events,
                to: DataPlaceholderFormat(whenEmpty: "Nothing in the diary.")
            )

            let editor = try #require(aujour.journal.editor(for: aujour.journal.dayOnScreen.adding(days: -3)))
            await editor.open()
            #expect(editor.content == "## Today\nNothing in the diary.\n")
        }
    }

    /// A journal over folders of its own, with settings and a picked template
    /// that live and die with the test — never this machine's real ones.
    ///
    /// - Parameter dayData: what the device has to say about a day being
    ///   spawned. Nothing at all by default, which is every test here that is
    ///   not about the data placeholders.
    private func withAJournal(
        holding dayData: DayData = DayData(),
        _ body: (AJournalUnderTest) async throws -> Void
    ) async throws {
        try await withTemporaryFolder { folders in
            let root = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let settings = JournalSettingsStore.inMemory()
            let bookmark = BookmarkedTemplateFile.rememberedInMemory()
            try await body(
                AJournalUnderTest(
                    journal: Journal(
                        locator: .test(iCloudDocuments: root, folders: folders),
                        settings: settings,
                        templateElsewhere: bookmark,
                        dayData: dayData
                    ),
                    settings: settings,
                    bookmark: bookmark,
                    root: root,
                    folders: folders
                )
            )
        }
    }
}

/// A day of items answered from memory, standing where EventKit stands in the
/// app — so that what a placeholder writes is a claim a test can make without
/// the machine's own calendar having anything on it.
private struct ADayOfItems: DayItemSource {
    let items: [DayItem]

    init(_ items: [DayItem]) { self.items = items }

    func items(during day: DateInterval) async -> [DayItem] { items }
}

/// One installation of Aujour as this suite has it: the journal, what it is
/// shaped by, the folder it journals into, and the wider folder standing in
/// for the rest of the device — where a template the user keeps somewhere else
/// entirely goes.
@MainActor
private struct AJournalUnderTest {
    let journal: Journal
    let settings: JournalSettingsStore
    let bookmark: BookmarkedTemplateFile
    let root: URL
    let folders: URL
}

extension BookmarkedTemplateFile {
    /// A picked template that lives and dies with the test: the bookmark the
    /// app keeps in `UserDefaults`, kept in memory instead — so that a second
    /// journal over the same one is a relaunch.
    static func rememberedInMemory() -> BookmarkedTemplateFile {
        let remembered = OneBookmark()
        return BookmarkedTemplateFile(
            storedBookmark: { remembered.data },
            rememberBookmark: { remembered.data = $0 }
        )
    }
}

/// Somewhere for one bookmark to sit for the length of a test.
///
/// Unchecked because the single value is behind a lock, and both the test and
/// the read that spawns a day reach it.
private final class OneBookmark: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    var data: Data? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
