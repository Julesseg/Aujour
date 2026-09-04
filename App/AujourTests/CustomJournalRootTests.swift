import Foundation
import Testing
import AujourCore

@testable import Aujour

// M2's promise: point Aujour at a folder in an Obsidian vault, and the daily
// notes there and the Journal become the same files — while the thousands of
// other notes in the vault are never read, written, moved or counted.
//
// The half of that promise about *which files are Entries* is decided in Core
// and proved there (`VaultSafetyTests`). This is the half only a device has:
// a folder outside the app's own container is reachable only through a
// security-scoped bookmark, and it is the bookmark that has to survive a
// relaunch, a rename, and the user changing their mind.

/// Where a bookmark is kept between launches. `UserDefaults` in the app;
/// here, a box a test can hand to a second `CustomJournalRoot` — which is
/// what a relaunch is.
///
/// Unchecked because the box is behind a lock; the closures it hands out are
/// read from whatever task the locator is running on.
private final class RememberedBookmark: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    /// A chosen folder over this storage — a new one every time, because that
    /// is what a relaunch hands the app: nothing but the bookmark.
    func customRoot() -> CustomJournalRoot {
        CustomJournalRoot(
            storedBookmark: {
                self.lock.lock()
                defer { self.lock.unlock() }
                return self.data
            },
            rememberBookmark: { bookmark in
                self.lock.lock()
                defer { self.lock.unlock() }
                self.data = bookmark
            }
        )
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return data == nil
    }
}

@Suite("The folder the user pointed Aujour at")
struct CustomJournalRootBookmarkTests {
    @Test("with nothing chosen, the journal is the one Aujour found for itself")
    func nothingChosenLeavesAujoursOwnFolderInCharge() async throws {
        try await withTemporaryFolder { folders in
            let remembered = RememberedBookmark()
            let device = folders.appending(path: "Device/Documents", directoryHint: .isDirectory)

            let root = try locator(device: device, chosen: remembered.customRoot()).locate()

            #expect(root.location == .aujoursOwn(.onThisDevice))
            #expect(root.url == device.standardizedFileURL)
        }
    }

    @Test("a folder the user picked becomes the Journal Root")
    func aPickedFolderBecomesTheJournalRoot() async throws {
        try await withTemporaryFolder { folders in
            let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
            try vault.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let remembered = RememberedBookmark()

            try remembered.customRoot().choose(vault)
            let root = try locator(
                device: folders.appending(path: "Device"),
                chosen: remembered.customRoot()
            ).locate()

            #expect(root.location == .customFolder(name: "Journal"))
            #expect(root.url == vault.standardizedFileURL)
            // Taken as it was found: nothing is written into it, and the
            // Entries already there are the journal from now on.
            let store: any JournalStore = FileJournalStore(root: root.url)
            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        }
    }

    @Test("the folder is still the journal after a relaunch")
    func aChosenFolderSurvivesARelaunch() async throws {
        try await withTemporaryFolder { folders in
            let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            let remembered = RememberedBookmark()
            try remembered.customRoot().choose(vault)

            // Nothing carried over from the launch that chose it but the
            // bookmark, which is all a relaunch or a reboot leaves.
            let afterRelaunch = try locator(
                device: folders.appending(path: "Device"),
                chosen: remembered.customRoot()
            ).locate()

            #expect(afterRelaunch.location == .customFolder(name: "Journal"))
            #expect(afterRelaunch.url == vault.standardizedFileURL)
        }
    }

    @Test("a folder renamed under the app is still found, by its new name")
    func aRenamedFolderIsFollowed() async throws {
        try await withTemporaryFolder { folders in
            let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
            try vault.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let remembered = RememberedBookmark()
            try remembered.customRoot().choose(vault)

            // A bookmark names the folder itself and not the path to it,
            // which is most of why a bookmark is what gets kept.
            let renamed = folders.appending(path: "Obsidian/Daybook", directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: vault, to: renamed)

            let root = try locator(
                device: folders.appending(path: "Device"),
                chosen: remembered.customRoot()
            ).locate()

            #expect(root.url == renamed.standardizedFileURL)
            #expect(root.location == .customFolder(name: "Daybook"))
        }
    }

    @Test("a chosen folder that has gone is a failure, not a quiet return to Aujour's own")
    func aMissingChosenFolderIsAPresentableFailure() async throws {
        try await withTemporaryFolder { folders in
            let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            let remembered = RememberedBookmark()
            try remembered.customRoot().choose(vault)
            try FileManager.default.removeItem(at: vault)

            // Journaling into Aujour's own folder instead would leave the
            // user looking at an empty journal while their Entries sit in the
            // vault, and nothing said about it (ADR 0004).
            #expect(throws: JournalRootError.customRootUnavailable) {
                try locator(
                    device: folders.appending(path: "Device"),
                    chosen: remembered.customRoot()
                ).locate()
            }
        }
    }

    @Test("going back to Aujour's own folder leaves the chosen one where it is")
    func forgettingAFolderDoesNotTouchIt() async throws {
        try await withTemporaryFolder { folders in
            let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
            try vault.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let device = folders.appending(path: "Device/Documents", directoryHint: .isDirectory)
            let remembered = RememberedBookmark()
            let chosen = remembered.customRoot()
            try chosen.choose(vault)

            chosen.forget()

            let root = try locator(device: device, chosen: chosen).locate()
            #expect(root.location == .aujoursOwn(.onThisDevice))
            #expect(remembered.isEmpty)
            // Their words are files, and files do not go anywhere because an
            // app stopped looking at them (ADR 0001).
            let store: any JournalStore = FileJournalStore(root: vault)
            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        }
    }

    @Test("a file is not a folder to journal into, and picking one changes nothing")
    func aFileCannotBeTheJournalRoot() async throws {
        try await withTemporaryFolder { folders in
            try folders.seed("Not a folder.\n", at: "note.md")
            let remembered = RememberedBookmark()

            #expect(throws: JournalRootError.customRootUnavailable) {
                try remembered.customRoot().choose(folders.appending(path: "note.md"))
            }
            #expect(remembered.isEmpty)
        }
    }

    private func locator(device: URL, chosen: CustomJournalRoot) -> JournalRootLocator {
        JournalRootLocator(
            // No iCloud, so that what a chosen folder is being preferred over
            // is unambiguous.
            iCloudDocuments: { nil },
            onThisDeviceDocuments: { device },
            lastUsedLocation: { .onThisDevice },
            rememberLocation: { _ in },
            customRoot: chosen
        )
    }
}

@MainActor
@Suite("Journaling into a folder of the user's own")
struct CustomJournalRootTests {
    @Test("picking a folder switches the journal, and Entries are read and written there")
    func pickingAFolderSwitchesTheJournal() async throws {
        try await withTemporaryFolder { folders in
            let vault = try vaultFolder(in: folders)
            let session = Session(folders: folders)

            await session.journal.use(vault)

            #expect(session.root?.location == .customFolder(name: "Journal"))
            #expect(session.journal.hasACustomFolder)
            #expect(session.journal.folderProblem == nil)

            // Read from there: today's Entry is whatever that folder holds
            // for today, and this vault holds one.
            let today = try #require(session.journal.today)
            #expect(today.content == "Written in Obsidian this morning.\n")

            // And written there: the words go into the vault's own file, not
            // into the folder the journal was in a moment ago — which is
            // never even made.
            today.content = "Written in Obsidian this morning, and in Aujour tonight.\n"
            await today.save()
            #expect(
                try String(contentsOf: vault.appending(path: todaysEntryPath), encoding: .utf8)
                    == "Written in Obsidian this morning, and in Aujour tonight.\n"
            )
            #expect(!FileManager.default.fileExists(atPath: session.defaultFolder.path))
        }
    }

    @Test("the calendar is rebuilt by scanning the folder that was picked")
    func theCalendarRebuildsFromTheChosenFolder() async throws {
        try await withTemporaryFolder { folders in
            let vault = try vaultFolder(in: folders)
            let session = Session(folders: folders)
            // A day this month that the folder Aujour started in has and the
            // vault does not, so a calendar holding anything from before the
            // switch would still be showing it.
            let anotherDay = JournalDay(
                year: today.year,
                month: today.month,
                day: today.day == 1 ? 2 : 1
            )
            try session.defaultFolder.seed(
                "Nothing to do with the vault.\n",
                at: PathTemplate.default.render(anotherDay)
            )

            await session.journal.open()
            let before = try #require(session.journal.calendar)
            await before.scan()
            #expect(anotherDay.isJournaled(in: before))

            await session.journal.use(vault)

            let after = try #require(session.journal.calendar)
            await after.scan()
            #expect(after.problem == nil)
            #expect(today.isJournaled(in: after))
            #expect(!anotherDay.isJournaled(in: after))
        }
    }

    @Test("the folder is still the journal after a relaunch")
    func theChosenFolderSurvivesARelaunch() async throws {
        try await withTemporaryFolder { folders in
            let vault = try vaultFolder(in: folders)
            let session = Session(folders: folders)
            await session.journal.use(vault)

            // The app again, over the same device, with nothing kept from the
            // launch that chose the folder.
            session.relaunch()
            await session.journal.open()

            #expect(session.root?.location == .customFolder(name: "Journal"))
            #expect(session.journal.today?.content == "Written in Obsidian this morning.\n")
        }
    }

    @Test("the user can go back to the folder Aujour found for itself")
    func revertingToAujoursOwnFolder() async throws {
        try await withTemporaryFolder { folders in
            let vault = try vaultFolder(in: folders)
            let session = Session(folders: folders)
            await session.journal.use(vault)

            await session.journal.useAujoursOwnFolder()

            #expect(session.root?.location == .aujoursOwn(.onThisDevice))
            #expect(!session.journal.hasACustomFolder)
            // Today is a day to be written from scratch again, because the
            // folder Aujour is back in has never been written in.
            #expect(session.journal.today?.content == "")

            // It sticks, the way choosing did.
            session.relaunch()
            await session.journal.open()
            #expect(session.root?.location == .aujoursOwn(.onThisDevice))
            // And the vault keeps every word that was ever written into it.
            #expect(
                try String(contentsOf: vault.appending(path: todaysEntryPath), encoding: .utf8)
                    == "Written in Obsidian this morning.\n"
            )
        }
    }

    @Test("words still in the editor go to the folder they were written in, before it is left")
    func unsavedWordsLandBeforeTheFolderChanges() async throws {
        try await withTemporaryFolder { folders in
            let vault = try vaultFolder(in: folders)
            let session = Session(folders: folders)
            await session.journal.open()
            let today = try #require(session.journal.today)
            // Typed and not waited out: the autosave is still holding these
            // words, so nothing is on disk yet — and the editor holding them
            // is about to be replaced.
            today.content = "Written in Aujour's own folder."

            await session.journal.use(vault)

            #expect(session.root?.location == .customFolder(name: "Journal"))
            #expect(
                try String(
                    contentsOf: session.defaultFolder.appending(path: todaysEntryPath),
                    encoding: .utf8
                ) == "Written in Aujour's own folder."
            )
        }
    }

    @Test("a folder change waits rather than leaving words that could not be written")
    func aSaveThatWillNotGoStopsTheMove() async throws {
        try await withTemporaryFolder { folders in
            let vault = try vaultFolder(in: folders)
            let session = Session(folders: folders)
            await session.journal.open()
            let today = try #require(session.journal.today)
            today.content = "Words that cannot land."
            // The folder goes out from under the editor, so those words exist
            // nowhere but on screen.
            try FileManager.default.removeItem(at: session.defaultFolder)

            await session.journal.use(vault)

            // Moving would have thrown them away with the editor holding them
            // (v1-decisions: no words are ever silently discarded).
            #expect(session.root?.location == .aujoursOwn(.onThisDevice))
            #expect(session.journal.today?.content == "Words that cannot land.")
            #expect(session.journal.folderProblem != nil)
            #expect(!session.journal.hasACustomFolder)
        }
    }

    @Test("a folder that cannot be taken on leaves the journal that is open alone")
    func aFailedPickLeavesTheOpenJournalAlone() async throws {
        try await withTemporaryFolder { folders in
            let session = Session(folders: folders)
            await session.journal.open()
            try folders.seed("Not a folder.\n", at: "note.md")

            await session.journal.use(folders.appending(path: "note.md"))

            #expect(session.root?.location == .aujoursOwn(.onThisDevice))
            #expect(session.journal.today != nil)
            // Said rather than swallowed: the request did not happen.
            #expect(session.journal.folderProblem != nil)
            #expect(!session.journal.hasACustomFolder)
        }
    }

    @Test("journaling into a vault touches nothing in it that is not an Entry")
    func journalingIntoAVaultLeavesTheRestOfItAlone() async throws {
        try await withTemporaryFolder { folders in
            let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
            let notes = [
                "Inbox/Meeting with Robin.md": "- ship M2\n",
                "Projects/Aujour.md": "A journaling app built on markdown files.\n",
                // Dated like an Entry, and filed the way another app files it.
                "Daily/2026-03-02.md": "Obsidian's own daily note.\n",
            ]
            for (path, text) in notes { try vault.seed(text, at: path) }
            // Obsidian's own configuration, which a user would notice being
            // rewritten even if nothing it said had changed.
            let configuration = "{ \"promptDelete\": false }\n"
            try vault.seed(configuration, at: ".obsidian/app.json")

            let session = Session(folders: folders)
            await session.journal.use(vault)

            // How much journal is in the folder is its Entries, not its files:
            // a vault's other notes are not the size of anybody's journal, and
            // Obsidian's daily note is filed where the Path Template does not
            // look.
            #expect(session.entryCount == 0)

            let today = try #require(session.journal.today)
            today.content = "Walked to the market.\n"
            await today.save()

            // Exactly one file arrived, at the path the Path Template names.
            let store: any JournalStore = FileJournalStore(root: vault)
            #expect(try await store.listFiles() == (Array(notes.keys) + [todaysEntryPath]).sorted())
            for (path, text) in notes {
                #expect(
                    try String(contentsOf: vault.appending(path: path), encoding: .utf8) == text,
                    "\(path) was modified"
                )
            }
            #expect(
                try String(
                    contentsOf: vault.appending(path: ".obsidian/app.json"),
                    encoding: .utf8
                ) == configuration
            )
        }
    }

    /// A vault with a journal folder in it holding today's Entry — the folder
    /// of someone who has been keeping daily notes in Obsidian.
    private func vaultFolder(in folders: URL) throws -> URL {
        let vault = folders.appending(path: "Obsidian/Journal", directoryHint: .isDirectory)
        try vault.seed("Written in Obsidian this morning.\n", at: todaysEntryPath)
        try vault.seed("- ship M2\n", at: "Inbox/Meeting with Robin.md")
        return vault
    }

    private var today: JournalDay {
        JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    }

    /// Where today's Entry belongs under the default Path Template.
    private var todaysEntryPath: String {
        PathTemplate.default.render(today)
    }
}

/// One device: the folder Aujour would find for itself, and the bookmark the
/// device keeps between launches. The Journal over both — and a second one,
/// for what the next launch sees.
@MainActor
private final class Session {
    let defaultFolder: URL
    private let remembered = RememberedBookmark()

    private(set) var journal: Journal!

    init(folders: URL) {
        defaultFolder = folders.appending(path: "Device/Documents", directoryHint: .isDirectory)
        journal = makeJournal()
    }

    var root: JournalRoot? {
        guard case .open(let root, _) = journal.state else { return nil }
        return root
    }

    /// How much journal the open folder holds, as the folder sheet would say
    /// it. `nil` when there is no open journal to have counted.
    var entryCount: Int? {
        guard case .open(_, let entryCount) = journal.state else { return nil }
        return entryCount
    }

    /// The app again, with nothing kept but what the device remembers.
    func relaunch() {
        journal = makeJournal()
    }

    private func makeJournal() -> Journal {
        // Held as a local so the locator's closure captures the folder and
        // not this main-actor-bound session.
        let folder = defaultFolder
        return Journal(
            locator: JournalRootLocator(
                iCloudDocuments: { nil },
                onThisDeviceDocuments: { folder },
                lastUsedLocation: { .onThisDevice },
                rememberLocation: { _ in },
                customRoot: remembered.customRoot()
            ),
            // Settings and a template of this test's own: the machine running
            // it has an Aujour with settings of its own, and a template it
            // spawned days from would be somebody's real one.
            settings: .inMemory(),
            templateElsewhere: .unpicked
        )
    }
}

extension JournalDay {
    /// Whether this day is marked on a calendar that has been scanned.
    @MainActor
    fileprivate func isJournaled(in calendar: JournalCalendar) -> Bool {
        calendar.month.days.first { $0.day == self }?.isJournaled ?? false
    }
}
