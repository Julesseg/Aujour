import Foundation
import Testing
import AujourCore

@testable import Aujour

// Two devices were both written in on the same day while one of them was
// offline, and iCloud has come back holding two versions of one Entry. What
// happens next is the promise the whole folder rests on: neither version is
// merged and neither is thrown away (ADR 0001) — the newest is at the day's
// own path, and the other is a file beside it that the user will come across
// in Obsidian or in the Files app.
//
// Which version wins and what the other is called is `ConflictPolicy`'s, and
// tested to death in Core. What is left here is the folder afterwards, which
// is the only place the claim can actually be checked.

/// The day both devices wrote, and where its Entry lives under the default
/// Path Template.
private let march1 = JournalDay(year: 2026, month: 3, day: 1)
private let entry = "2026/03/2026-03-01.md"

private let breakfast = Date(timeIntervalSince1970: 1_772_000_000)
private let lunch = breakfast.addingTimeInterval(3600 * 4)
private let dinner = breakfast.addingTimeInterval(3600 * 10)

@Suite("A day that was written twice")
struct DivergenceParkingTests {
    @Test("the version written last takes the Entry path, and this device's is parked beside it")
    func theNewestVersionTakesTheEntryPath() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: lunch)
            let store = FileJournalStore(root: root)
            let iPad = AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: dinner)

            let parked = try await DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(entry, in: root, are: [iPad])
            ).park(entry, of: march1)

            // Both of them, on disk, where the user can read one against the
            // other — which is the whole of what parking is for.
            #expect(parked.map(\.path) == ["2026/03/2026-03-01_1.md"])
            #expect(try await store.readText(at: entry) == "Written on the iPad.\n")
            #expect(
                try await store.readText(at: "2026/03/2026-03-01_1.md")
                    == "Written on this iPhone.\n"
            )
        }
    }

    @Test("a version that arrived older is the one parked, and the Entry is left alone")
    func anOlderVersionArrivingIsParked() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: dinner)
            let store = FileJournalStore(root: root)
            let iPad = AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: lunch)

            let parked = try await DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(entry, in: root, are: [iPad])
            ).park(entry, of: march1)

            #expect(parked.map(\.path) == ["2026/03/2026-03-01_1.md"])
            #expect(try await store.readText(at: entry) == "Written on this iPhone.\n")
            #expect(
                try await store.readText(at: "2026/03/2026-03-01_1.md")
                    == "Written on the iPad.\n"
            )
        }
    }

    @Test("a Parked File is a file beside the Entry, and not an Entry")
    func aParkedFileIsNotAnEntry() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: lunch)
            let store = FileJournalStore(root: root)

            _ = try await DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(
                    entry,
                    in: root,
                    are: [AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: dinner)]
                )
            ).park(entry, of: march1)

            // Two files, one day. The calendar and the Today view read the
            // folder through the Path Template and nothing else (ADR 0002),
            // so this is what keeps a parked version out of the journal until
            // the user has merged it by hand.
            let files = try await store.listFiles()
            #expect(files == [entry, "2026/03/2026-03-01_1.md"])
            #expect(files.compactMap(PathTemplate.default.match).count == 1)
        }
    }

    @Test("a day nobody else wrote is left exactly as it was")
    func anUndivergedEntryIsUntouched() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: lunch)
            let store = FileJournalStore(root: root)

            let parked = try await DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(entry, in: root, are: [])
            ).park(entry, of: march1)

            #expect(parked.isEmpty)
            #expect(try await store.listFiles() == [entry])
            #expect(try await store.readText(at: entry) == "Written on this iPhone.\n")
        }
    }

    @Test("a parked name the folder already holds is skipped, and its words are untouched")
    func anOccupiedParkedNameIsSkipped() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: lunch)
            // A `_1` from an earlier divergence, or from a migration collision
            // (ADR 0002). Either way it is somebody's words.
            try root.seed("Parked last week.\n", at: "2026/03/2026-03-01_1.md")
            let store = FileJournalStore(root: root)

            let parked = try await DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(
                    entry,
                    in: root,
                    are: [AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: dinner)]
                )
            ).park(entry, of: march1)

            #expect(parked.map(\.path) == ["2026/03/2026-03-01_2.md"])
            #expect(
                try await store.readText(at: "2026/03/2026-03-01_1.md") == "Parked last week.\n"
            )
            #expect(
                try await store.readText(at: "2026/03/2026-03-01_2.md")
                    == "Written on this iPhone.\n"
            )
        }
    }

    @Test("three versions of one day all survive, at three paths")
    func everyVersionSurvives() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: dinner)
            let store = FileJournalStore(root: root)
            let others = [
                AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: lunch),
                AVersionHeldByTheSystem("Written on the other iPhone.\n", writtenAt: breakfast),
            ]

            let parked = try await DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(entry, in: root, are: others)
            ).park(entry, of: march1)

            #expect(parked.map(\.path) == ["2026/03/2026-03-01_1.md", "2026/03/2026-03-01_2.md"])
            #expect(try await store.readText(at: entry) == "Written on this iPhone.\n")
            #expect(
                try await store.readText(at: "2026/03/2026-03-01_1.md") == "Written on the iPad.\n"
            )
            #expect(
                try await store.readText(at: "2026/03/2026-03-01_2.md")
                    == "Written on the other iPhone.\n"
            )
        }
    }

    @Test("a divergence dealt with is not dealt with twice")
    func aSettledDivergenceIsNotParkedAgain() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: lunch)
            let store = FileJournalStore(root: root)
            let iPad = AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: dinner)
            let parking = DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(entry, in: root, are: [iPad])
            )

            #expect(parking.hasDiverged(entry))
            _ = try await parking.park(entry, of: march1)

            // Told the system it has been taken care of, so that the same
            // divergence does not come back as news at every change in the
            // folder and leave a `_2`, a `_3`, and a journal full of copies.
            #expect(iPad.isSettled)
            #expect(!parking.hasDiverged(entry))
            #expect(try await parking.park(entry, of: march1).isEmpty)
            #expect(try await store.listFiles() == [entry, "2026/03/2026-03-01_1.md"])
        }
    }

    /// The one thing Aujour does with a Parked File other than say it is
    /// there: point at it, so the user can be taken to it in the app the
    /// folder belongs to (`CONTEXT.md`, Parked File).
    @Test("a Parked File can be pointed at, where it was left")
    func aParkedFileCanBePointedAtWhereItLies() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Written on this iPhone.\n", at: entry, writtenAt: lunch)
            let store = FileJournalStore(root: root)
            let iPad = AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: dinner)
            let parking = DivergenceParking(
                store: store,
                versions: TheVersionsHeldFor(entry, in: root, are: [iPad])
            )

            let parked = try #require(try await parking.park(entry, of: march1).first)
            let onDisk = try #require(parking.whereItLies(parked))

            #expect(
                onDisk.standardizedFileURL
                    == root.appending(path: parked.path).standardizedFileURL
            )
            #expect(FileManager.default.fileExists(atPath: onDisk.path))
        }
    }
}

// MARK: - The day's own screen

@MainActor
@Suite("A day written twice, said where that day is being written")
struct DivergenceToldToTheUserTests {
    /// The two halves of what the screen is owed: the day that was written
    /// twice has something to say, and every other day has nothing. A notice
    /// about March 1st over the Entry for the 14th would be about a file that
    /// is nowhere near it.
    @Test("only the day that was written twice has anything to say about it")
    func aParkedFileBelongsToItsOwnDayAndNoOther() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
            let entryPath = PathTemplate.default.render(today)
            try iCloud.seed("Written on this iPhone.\n", at: entryPath, writtenAt: lunch)
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked,
                versions: TheVersionsHeldFor(
                    entryPath,
                    in: iCloud,
                    are: [AVersionHeldByTheSystem("Written on the iPad.\n", writtenAt: dinner)]
                )
            )

            await journal.open()

            let parked = try #require(journal.parkedFiles(from: today).first)
            #expect(parked.name == "\(today.description)_1.md")
            #expect(journal.parkedFiles(from: today.adding(days: -1)).isEmpty)

            // Both versions are still there, one at the day's own path and one
            // beside it — the promise the whole folder rests on (ADR 0001).
            let onDisk = try #require(journal.whereItLies(parked))
            #expect(try String(contentsOf: onDisk, encoding: .utf8) == "Written on this iPhone.\n")
            #expect(
                try String(contentsOf: iCloud.appending(path: entryPath), encoding: .utf8)
                    == "Written on the iPad.\n"
            )
        }
    }

    @Test("a day nobody else wrote says nothing at all")
    func aDayWithNoOtherVersionSaysNothing() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
            try iCloud.seed("Walked to the market.\n", at: PathTemplate.default.render(today))
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )

            await journal.open()

            #expect(journal.parkedFiles(from: today).isEmpty)
        }
    }
}

// MARK: - The versions iCloud would have been holding

/// A version of a file the system is holding on to, as a test can make one —
/// which is the only way there is. A real one takes two devices, a sync, and
/// a moment of bad luck.
///
/// A class, and unchecked, because settling it is a fact the test reads back
/// afterwards; nothing here runs while the parking does.
private final class AVersionHeldByTheSystem: EntryVersion, @unchecked Sendable {
    let writtenAt: Date?
    private let text: String
    private(set) var isSettled = false

    init(_ text: String, writtenAt: Date?) {
        self.text = text
        self.writtenAt = writtenAt
    }

    func contents() throws -> Data {
        Data(text.utf8)
    }

    func settle() {
        isSettled = true
    }
}

/// The versions held for one file and no other — iCloud, as far as parking can
/// tell.
private struct TheVersionsHeldFor: EntryVersions {
    private let file: URL
    private let versions: [AVersionHeldByTheSystem]

    init(_ relativePath: String, in root: URL, are versions: [AVersionHeldByTheSystem]) {
        file = root.appending(path: relativePath).standardizedFileURL
        self.versions = versions
    }

    func unresolved(at url: URL) -> [any EntryVersion] {
        guard url.standardizedFileURL == file else { return [] }
        return versions.filter { !$0.isSettled }
    }
}
