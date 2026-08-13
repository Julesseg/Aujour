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

            #expect(await changeIsReported(by: folder))
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

            #expect(await changeIsReported(by: folder))
        }
    }

    @Test("Aujour's own writes are not reported back to it")
    func aujoursOwnWritesAreNotNews() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let folder = CoordinatedJournalRoot(root: root)
            defer { folder.stopWatching() }
            let store = FileJournalStore(root: root, coordinatedBy: folder)

            // An autosave, from the app's own editor.
            try await store.writeText("Walked to the market, and", at: "2026/03/2026-03-01.md")

            // Told about it, the editor would re-read the file it had just
            // written — and there is one of these every time the typing pauses.
            #expect(await changeIsReported(by: folder, within: 1) == false)
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

            #expect(await changeIsReported(by: folder, within: 1) == false)
        }
    }
}

/// Whether the folder reports a change within a deadline.
///
/// A deadline, because these are the only tests in the repo whose subject is
/// something the system decides when to do: a presenter is told about another
/// app's write when the system gets round to telling it. A change that has not
/// arrived in five seconds is one that is not coming.
///
/// Once per folder: giving up on the wait cancels the read of `changes`, and a
/// cancelled read of an `AsyncStream` ends the stream for good.
private func changeIsReported(
    by folder: CoordinatedJournalRoot,
    within seconds: Double = 5
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in folder.changes { return true }
            // The stream ended without one: the folder stopped being
            // presented, which is an answer too.
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return false
        }
        let reported = await group.next() ?? false
        group.cancelAll()
        return reported
    }
}
