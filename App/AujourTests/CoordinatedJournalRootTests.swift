import Foundation
import Testing
import AujourCore
@testable import Aujour

// The folder is shared — with Obsidian, and with the user's other devices
// through iCloud Drive. These are the claims that make that work: Aujour is
// told when somebody else writes in it, and is *not* told about its own
// writes, which would otherwise come back as news after every autosave.
//
// Only here can they be tested at all: file coordination is Apple's, and the
// in-memory folder every domain test journals into has nobody to share
// anything with.
//
// A folder per test, because a change is waited for by reading `changes`, and
// giving up on that wait is what ends the stream.
@Suite("The Journal Root, shared with other apps")
struct CoordinatedJournalRootTests {
    @Test("another app's write is reported")
    func somebodyElsesWriteIsNews() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }

            // Obsidian, saving the same daily note.
            try root.somebodyElseWrites(
                "Walked to the market, and back the long way.\n",
                at: "2026/03/2026-03-01.md"
            )

            #expect(await changeReported(by: folder) != nil)
        }
    }

    @Test("a day arriving from another device is reported")
    func aFileAppearingIsNews() async throws {
        try await withTemporaryFolder { root in
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }

            // A file the folder has never held — what iCloud bringing
            // yesterday's Entry down from the iPad looks like from here.
            try root.somebodyElseWrites("Rain all day.\n", at: "2026/02/2026-02-28.md")

            #expect(await changeReported(by: folder) != nil)
        }
    }

    @Test("a month arriving from another device is reported")
    func aFolderAppearingIsNews() async throws {
        try await withTemporaryFolder { root in
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }

            // A folder and not a file, which is the whole of what the system
            // says here — and is why a change to a folder is reported at all
            // rather than left to the Entries inside it. A month can arrive
            // before any of its days do, and a burst of another device's
            // writing is reported as the folders it touched and not as every
            // file in them.
            try root.somebodyElseMakesAFolder(at: "2026/04")

            // As the folder reporting, because no folder is ever an Entry:
            // naming `04` as the file a change was about would be a promise
            // about which day it was that the change cannot keep.
            #expect(await changeReported(by: folder) == .theFolder)
        }
    }

    @Test("another app deleting a day is reported")
    func somebodyElsesDeletionIsNews() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }

            // The day deleted in Obsidian. Here on its own because it is the
            // one thing the folder cannot check the file about: the file is
            // still there when Aujour is told, wearing the dates it wore
            // before anybody started watching, and what is happening to it is
            // that it is about to stop existing.
            try root.somebodyElseDeletes(at: "2026/03/2026-03-01.md")

            #expect(await changeReported(by: folder) != nil)
        }
    }

    @Test("a folder nobody has touched reports nothing")
    func aQuietFolderIsQuiet() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }

            // The floor every other claim here stands on: presenting a folder
            // is not itself news about it, or "somebody else wrote" would mean
            // nothing.
            let reported = await changeReported(by: folder, within: 2)
            #expect(reported == nil, "a folder nobody wrote in reported \(reported as Any)")
        }
    }

    @Test("Aujour's own writes are not reported back to it")
    func aujoursOwnWritesAreNotNews() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }
            let store = FileJournalStore(root: root, coordinatedBy: folder)

            // An autosave, from the app's own editor. Coordinated on behalf
            // of the presenter, which is not by itself enough to go unheard:
            // that exclusion is for the presenter of the file being written,
            // and this one presents the folder the file sits in.
            try await store.writeText("Walked to the market, and", at: "2026/03/2026-03-01.md")

            // Told about it, the editor would re-read the file it had just
            // written and the calendar would walk the whole folder — and there
            // is one of these every time the typing pauses.
            //
            // The month folder counts as being told: renaming the Entry into
            // place dates `2026/03` afresh, and the system reports that as
            // readily as it reports the file.
            let reported = await changeReported(by: folder, within: 2)
            #expect(reported == nil, "Aujour's own write came back as \(reported as Any)")
        }
    }

    @Test("the folders Aujour's own write has to make are not reported back either")
    func theFoldersAujoursOwnWriteMakesAreNotNews() async throws {
        try await withTemporaryFolder { root in
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }
            let store = FileJournalStore(root: root, coordinatedBy: folder)

            // The first Entry of a month, into a folder with nothing in it —
            // which is every journal on the day it is opened. The write has to
            // make `2026/` and `2026/03/` on the way, and making the year
            // dates the Journal Root itself, so there are three more things
            // for the same autosave to come back as than the Entry.
            try await store.writeText("Walked to the market.", at: "2026/03/2026-03-01.md")

            let reported = await changeReported(by: folder, within: 2)
            #expect(reported == nil, "Aujour's own write came back as \(reported as Any)")
        }
    }

    @Test("a folder that is no longer the journal stops being listened to")
    func stoppingEndsTheChanges() async throws {
        try await withTemporaryFolder { root in
            let folder = CoordinatedJournalRoot(root: root)

            // What pointing Aujour at a folder in an Obsidian vault does to
            // the folder it was journaling into before. Twice, because it
            // happens both when a journal moves and when the last reference to
            // the folder it left goes away.
            folder.stopWatching()
            folder.stopWatching()
            try root.somebodyElseWrites("Written after the move.\n", at: "2026/03/2026-03-01.md")

            #expect(await changeReported(by: folder, within: 2) == nil)
        }
    }
}

/// The change the folder reports within a deadline, or `nil` for none.
///
/// A deadline, because these are the only tests in the repo whose subject is
/// something the system decides when to do: a presenter is told about another
/// app's write when the system gets round to telling it.
///
/// Generous, because the deadline is only there so that "never" is not
/// "forever" — nothing here is a claim about how *fast* a change is reported,
/// and a loaded CI runner has been seen taking six times as long over
/// everything, including its own sleeps. The app does not lean on the speed
/// either: coming back to the front catches up with the folder whatever the
/// presenter did or did not say while it was away.
///
/// What it reports and not merely that it did, so that a folder heard from
/// when it should have been quiet says which file it was about — which is what
/// told this branch that an autosave comes back as a change to the Entry
/// itself, and not, as it had assumed, to something beside it.
///
/// Once per folder: giving up on the wait cancels the read of `changes`, and a
/// cancelled read of an `AsyncStream` ends the stream for good.
private func changeReported(
    by folder: CoordinatedJournalRoot,
    within seconds: Double = 20
) async -> JournalRootChange? {
    await withTaskGroup(of: JournalRootChange?.self) { group in
        group.addTask {
            for await change in folder.changes { return change }
            // The stream ended without one: the folder stopped being
            // presented, which is an answer too.
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let reported = await group.next() ?? nil
        group.cancelAll()
        return reported
    }
}
