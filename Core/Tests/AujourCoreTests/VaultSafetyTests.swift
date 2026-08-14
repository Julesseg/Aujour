import Foundation
import Testing

@testable import AujourCore

// The promise that makes a custom Journal Root safe to point at an Obsidian
// vault: of the thousands of files in it, the only ones Aujour reads, writes
// or counts as journaled are the ones the *current* Path Template names.
// Everything else — someone else's notes, Obsidian's own configuration, a
// sync conflict's leftovers, another app's daily notes — is left exactly
// where and as it was.
//
// This is the whole of it, stated at the seam where it is decided: a Journal
// Store is a folder of files, a Path Template says which of them are Entries
// (ADR 0002), and nothing above either can widen that. It lives in Core
// rather than in a UI test because it is a claim about the domain, and
// because it is the one claim a bug in would cost somebody else's writing.

/// A vault as a user would actually have it — the journal is a corner of it,
/// and the rest belongs to Obsidian and to them.
private let vault: [String: String] = [
    // Obsidian's own configuration. A user would notice this rewritten even
    // if nothing it said had changed.
    ".obsidian/app.json": "{ \"promptDelete\": false }\n",
    ".obsidian/workspace.json": "{ \"main\": {} }\n",

    // Notes nobody would call a journal entry.
    "Inbox/Meeting with Robin.md": "- ship M2\n",
    "Projects/Aujour.md": "A journaling app built on markdown files.\n",
    "Attachments/market.jpg": "not really a JPEG, but not text either",

    // Entries, under the default Path Template `YYYY/MM/YYYY-MM-DD`.
    "2026/03/2026-03-01.md": "Walked to the market.\n",
    "2026/03/2026-03-14.md": "Rained all day.\n",

    // Entry-*shaped*, and not Entries. Each is a way a path can come within
    // one character of the template and still name somebody else's file.
    "Daily/2026-03-02.md": "Obsidian's own daily note for the 2nd.\n",
    "2026/03/2026-3-3.md": "The 3rd, unpadded, from some other tool.\n",
    "2026/03/2026-03-04.markdown": "The 4th, with the long extension.\n",
    "2026/03/2026-03-05.md.bak": "The 5th, backed up by hand.\n",
    "2026/03/2026-03-14 (conflicted copy).md": "Rained all day\n",
]

/// The default Path Template's Entries in `vault`, by the day they belong to.
private let entriesInTheVault: [JournalDay: String] = [
    JournalDay(year: 2026, month: 3, day: 1): "2026/03/2026-03-01.md",
    JournalDay(year: 2026, month: 3, day: 14): "2026/03/2026-03-14.md",
]

@MainActor
@Suite("Journaling into somebody else's vault")
struct VaultSafetyTests {
    @Test("only the files the Path Template names are Entries")
    func onlyTemplateMatchingFilesAreEntries() async {
        let session = VaultSession()
        let calendar = session.calendar()

        await calendar.scan()

        // Every other note in the vault dated to a day in March — the
        // unpadded one, the long extension, the conflicted copy, Obsidian's
        // own daily folder — leaves its day unmarked, because a file is an
        // Entry exactly when its path is what the template renders.
        #expect(
            calendar.month.days.filter(\.isJournaled).map(\.day)
                == [
                    JournalDay(year: 2026, month: 3, day: 1),
                    JournalDay(year: 2026, month: 3, day: 14),
                ]
        )
        #expect(session.store.writes.isEmpty)
        #expect(session.store.moves.isEmpty)
    }

    @Test("writing a day that has no Entry adds one file and touches nothing else")
    func backfillingADayLeavesTheRestOfTheVaultAlone() async {
        let session = VaultSession()
        // A day another app has a note for, under its own layout — the case
        // where a vault-unsafe app would find that note and edit it.
        let theSecond = JournalDay(year: 2026, month: 3, day: 2)
        let editor = session.editor(for: theSecond)

        await editor.open()
        editor.content = "Filled in the next morning."
        await editor.save()

        #expect(session.store.writes.map(\.path) == ["2026/03/2026-03-02.md"])
        #expect(session.store.moves.isEmpty)
        await session.expectTheVaultIsUntouched(exceptFor: ["2026/03/2026-03-02.md"])
        // Obsidian's note for the same day still says what it said.
        #expect(
            await session.text(at: "Daily/2026-03-02.md")
                == "Obsidian's own daily note for the 2nd.\n"
        )
    }

    @Test("writing a day that has an Entry rewrites that file and no other")
    func editingAnEntryLeavesTheRestOfTheVaultAlone() async {
        let session = VaultSession()
        let editor = session.editor(for: JournalDay(year: 2026, month: 3, day: 14))

        await editor.open()
        #expect(editor.content == "Rained all day.\n")
        editor.content = "Rained all day, and then it stopped.\n"
        await editor.save()

        #expect(session.store.writes.map(\.path) == ["2026/03/2026-03-14.md"])
        #expect(session.store.moves.isEmpty)
        await session.expectTheVaultIsUntouched(exceptFor: ["2026/03/2026-03-14.md"])
    }

    @Test("a sync conflict's copy beside an Entry is not the Entry")
    func aConflictedCopyIsNotAnEntry() async {
        let session = VaultSession()
        let editor = session.editor(for: JournalDay(year: 2026, month: 3, day: 14))

        await editor.open()

        // The copy is a file in the folder and nothing more: it is not what
        // the day opens to, and writing the day does not write it.
        #expect(editor.content == "Rained all day.\n")
        editor.content = "Rained all day, and then it stopped.\n"
        await editor.save()
        #expect(
            await session.text(at: "2026/03/2026-03-14 (conflicted copy).md")
                == "Rained all day\n"
        )
    }

    @Test("which files are Entries follows the current Path Template, and only it")
    func changingTheTemplateChangesWhichFilesAreEntries() async {
        // The same vault, read by a journal configured the way the user who
        // came from Obsidian's daily notes would have it. Now the `Daily`
        // folder holds the Entries and `2026/03` holds files that are not.
        let session = VaultSession(pathTemplate: "[Daily]/YYYY-MM-DD")
        let calendar = session.calendar()

        await calendar.scan()

        #expect(
            calendar.month.days.filter(\.isJournaled).map(\.day)
                == [JournalDay(year: 2026, month: 3, day: 2)]
        )

        // And the day that *was* an Entry under the other template is now a
        // day to be written from scratch — into the file this template names,
        // leaving the old one where it is. Moving it is a migration, which
        // the user is asked about (ADR 0002); nothing here does it silently.
        let editor = session.editor(for: JournalDay(year: 2026, month: 3, day: 1))
        await editor.open()
        editor.content = "Walked to the market, again.\n"
        await editor.save()

        #expect(session.store.writes.map(\.path) == ["Daily/2026-03-01.md"])
        #expect(session.store.moves.isEmpty)
        await session.expectTheVaultIsUntouched(exceptFor: ["Daily/2026-03-01.md"])
    }

    @Test("a day nobody writes on leaves the vault exactly as it was")
    func openingADayWithoutWritingChangesNothing() async {
        let session = VaultSession()

        // Opened and left: the calendar scanned, a past day looked at, and
        // today spawned from the template and not typed into.
        let calendar = session.calendar()
        await calendar.scan()
        for day in [JournalDay(year: 2026, month: 3, day: 1), JournalDay(year: 2026, month: 3, day: 7)] {
            let editor = session.editor(for: day)
            await editor.open()
            await editor.save()
        }

        #expect(session.store.writes.isEmpty)
        #expect(session.store.moves.isEmpty)
        await session.expectTheVaultIsUntouched()
    }

    @Test("every Entry in the vault reads back as the file has it")
    func entriesReadBackFromTheFilesThatHoldThem() async {
        let session = VaultSession()

        for (day, path) in entriesInTheVault {
            let editor = session.editor(for: day)
            await editor.open()
            #expect(editor.content == vault[path])
        }
    }
}

/// A Journal over a vault, with the two seams that would otherwise be a
/// device: the folder, and the waiting between a keystroke and a save.
@MainActor
private final class VaultSession {
    let store: RecordingJournalStore
    private let settings: JournalSettings

    /// Late in March, so that every day the tests write to is in the past and
    /// the calendar's month is the one the vault has files in.
    private let now = instant(2026, 3, 20, 9, 30, in: paris)

    init(pathTemplate: String = JournalSettings.default.pathTemplate) {
        store = RecordingJournalStore(vault)
        settings = JournalSettings(pathTemplate: pathTemplate)
    }

    func calendar() -> JournalCalendar {
        JournalCalendar(
            store: store,
            settings: settings,
            timeZone: paris,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { self.now }
        )
    }

    func editor(for day: JournalDay) -> EntryEditor {
        EntryEditor(
            store: store,
            settings: settings,
            timeZone: paris,
            locale: Locale(identifier: "en_US_POSIX"),
            day: day,
            now: { self.now },
            // No second passes in a test: the debounce is waited out the
            // moment it starts.
            wait: { _ in try Task.checkCancellation() }
        )
    }

    func text(at path: String) async -> String? {
        try? await store.readText(at: path)
    }

    /// Asserts the vault is byte-for-byte what it was seeded as, apart from
    /// the paths named — no file added, removed, renamed or rewritten.
    func expectTheVaultIsUntouched(
        exceptFor written: Set<String> = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let paths = (try? await store.listFiles()) ?? []
        #expect(
            Set(paths) == Set(vault.keys).union(written),
            "the vault gained or lost files",
            sourceLocation: sourceLocation
        )
        for (path, contents) in vault where !written.contains(path) {
            #expect(
                await text(at: path) == contents,
                "\(path) was modified",
                sourceLocation: sourceLocation
            )
        }
    }
}

/// A Journal Store that keeps a record of every write and move made through
/// it, so a test can say "nothing else was even reached for" rather than only
/// "nothing else ended up different".
///
/// The stronger claim is the one that matters here: a write of identical
/// bytes leaves a file's content alone and still shows up in the user's vault
/// as a file Aujour touched.
///
/// Unchecked because the record is written by the code under test and read by
/// the test afterwards, never at the same moment.
private final class RecordingJournalStore: JournalStore, @unchecked Sendable {
    private let folder: InMemoryJournalStore

    private(set) var writes: [(path: String, text: String)] = []
    private(set) var moves: [(from: String, to: String)] = []

    init(_ files: [String: String]) {
        folder = InMemoryJournalStore(files)
    }

    func listFiles() async throws -> [String] {
        await folder.listFiles()
    }

    func fileExists(at relativePath: String) async throws -> Bool {
        try await folder.fileExists(at: relativePath)
    }

    func read(at relativePath: String) async throws -> Data {
        try await folder.read(at: relativePath)
    }

    func write(_ contents: Data, at relativePath: String) async throws {
        writes.append((relativePath, String(decoding: contents, as: UTF8.self)))
        try await folder.write(contents, at: relativePath)
    }

    func create(_ contents: Data, at relativePath: String) async throws {
        writes.append((relativePath, String(decoding: contents, as: UTF8.self)))
        try await folder.create(contents, at: relativePath)
    }

    func move(from source: String, to destination: String) async throws {
        moves.append((source, destination))
        try await folder.move(from: source, to: destination)
    }
}
