import Foundation
import Testing

@testable import AujourCore

// The other half of a Path Template change: the plan, made over the folder it
// was planned for. Every claim here is about what the folder holds afterwards
// — because that is all a migration is, and because ADR 0002's promise is
// about files (nothing overwritten, every version still readable, everything
// Aujour did not put there left alone).

private let old = try! PathTemplate("YYYY/MM/YYYY-MM-DD")
private let new = try! PathTemplate("[Journal]/YYYY-MM-DD")

/// The two templates that put the month and the day the other way round in a
/// file name — the everyday change whose moves form a ring.
private let monthFirst = try! PathTemplate("YYYY/[d]MM[-]DD")
private let dayFirst = try! PathTemplate("YYYY/[d]DD[-]MM")

@Suite("Carrying a Path Template change out over the folder")
struct JournalMigrationTests {
    @Test("every Entry ends up where the new template puts it, saying what it said")
    func entriesArriveAtTheirNewPathsIntact() async throws {
        let store = InMemoryJournalStore([
            "2026/03/2026-03-01.md": "Walked to the market.\n",
            "2026/02/2026-02-28.md": "February's last day.\n",
        ])
        let migration = JournalMigration(over: store)

        let plan = try await migration.plan(changingFrom: old, to: new)
        let outcome = await migration.carryOut(plan)

        let files = await store.listFiles()
        #expect(files == ["Journal/2026-02-28.md", "Journal/2026-03-01.md"])
        let march = try await store.readText(at: "Journal/2026-03-01.md")
        let february = try await store.readText(at: "Journal/2026-02-28.md")
        #expect(march == "Walked to the market.\n")
        #expect(february == "February's last day.\n")
        #expect(outcome.moved.count == 2)
        #expect(outcome.parked.isEmpty)
        #expect(outcome.leftBehind.isEmpty)
    }

    @Test("nothing the migration was not about is touched")
    func onlyEntriesAreEverMoved() async throws {
        let store = InMemoryJournalStore([
            "2026/03/2026-03-01.md": "Walked to the market.\n",
            "Reading/Dune.md": "Somebody else's note.\n",
            "2026/03/2026-03-01_1.md": "A parked divergence.\n",
        ])
        let migration = JournalMigration(over: store)

        let plan = try await migration.plan(changingFrom: old, to: new)
        _ = await migration.carryOut(plan)

        let note = try await store.readText(at: "Reading/Dune.md")
        let parked = try await store.readText(at: "2026/03/2026-03-01_1.md")
        #expect(note == "Somebody else's note.\n")
        #expect(parked == "A parked divergence.\n")
    }

    @Test("a file already claiming a day stays put, and the Entry arrives beside it")
    func aCollisionKeepsBothVersions() async throws {
        let store = InMemoryJournalStore([
            "2026/03/2026-03-01.md": "What Aujour has for the 1st.\n",
            "Journal/2026-03-01.md": "What the vault already had.\n",
        ])
        let migration = JournalMigration(over: store)

        let plan = try await migration.plan(changingFrom: old, to: new)
        let outcome = await migration.carryOut(plan)

        // Neither version is gone, and the one that was already at the day's
        // new path is the one still at it (ADR 0002).
        let wasThere = try await store.readText(at: "Journal/2026-03-01.md")
        let arrived = try await store.readText(at: "Journal/2026-03-01_1.md")
        #expect(wasThere == "What the vault already had.\n")
        #expect(arrived == "What Aujour has for the 1st.\n")
        #expect(outcome.moved.isEmpty)
        #expect(
            outcome.parked == [
                MigrationOutcome.ParkedEntry(
                    day: JournalDay(year: 2026, month: 3, day: 1),
                    path: "Journal/2026-03-01_1.md"
                )
            ]
        )
        // Named the way the user will meet it in Obsidian or in Files.
        #expect(outcome.parked.first?.name == "2026-03-01_1.md")
    }

    @Test("two days that swap paths both keep their words")
    func aSwapLosesNeitherDay() async throws {
        let store = InMemoryJournalStore([
            "2026/d03-04.md": "The fourth of March.\n",
            "2026/d04-03.md": "The third of April.\n",
        ])
        let migration = JournalMigration(over: store)

        let plan = try await migration.plan(changingFrom: monthFirst, to: dayFirst)
        let outcome = await migration.carryOut(plan)

        // Each day is where the new template names it, and neither is a
        // Parked File: the ring was opened by a file waiting at a name of its
        // own, which is not somewhere anything is left.
        let files = await store.listFiles()
        #expect(files == ["2026/d03-04.md", "2026/d04-03.md"])
        let fourthOfMarch = try await store.readText(at: "2026/d04-03.md")
        let thirdOfApril = try await store.readText(at: "2026/d03-04.md")
        #expect(fourthOfMarch == "The fourth of March.\n")
        #expect(thirdOfApril == "The third of April.\n")
        #expect(outcome.moved.count == 2)
        #expect(outcome.parked.isEmpty)
        #expect(outcome.leftBehind.isEmpty)
    }

    @Test("a move the folder refuses leaves that day where it was, and the rest still move")
    func oneUnmovableEntryDoesNotStopTheOthers() async throws {
        let store = ObstructiveJournalStore([
            "2026/03/2026-03-01.md": "The day iCloud has not brought down.\n",
            "2026/03/2026-03-02.md": "The day beside it.\n",
        ])
        store.refuseMovingFrom = "2026/03/2026-03-01.md"
        let migration = JournalMigration(over: store)

        let plan = try await migration.plan(changingFrom: old, to: new)
        let outcome = await migration.carryOut(plan)

        // Nothing is lost — the file is exactly where it was, still saying
        // what it said — and the user is told which day it was.
        let stayed = try await store.readText(at: "2026/03/2026-03-01.md")
        let moved = try await store.readText(at: "Journal/2026-03-02.md")
        #expect(stayed == "The day iCloud has not brought down.\n")
        #expect(moved == "The day beside it.\n")
        #expect(outcome.moved == [JournalDay(year: 2026, month: 3, day: 2)])
        #expect(outcome.leftBehind.map(\.day) == [JournalDay(year: 2026, month: 3, day: 1)])
        #expect(outcome.leftBehind.map(\.path) == ["2026/03/2026-03-01.md"])
    }

    @Test("a day that could not step aside is not chased any further")
    func aRefusedStagingMoveEndsThatDaysMigration() async throws {
        let store = ObstructiveJournalStore([
            "2026/d03-04.md": "The fourth of March.\n",
            "2026/d04-03.md": "The third of April.\n",
        ])
        let migration = JournalMigration(over: store)
        let plan = try await migration.plan(changingFrom: monthFirst, to: dayFirst)
        // The move that opens the ring, refused — so the day behind it has
        // nowhere to go either.
        store.refuseMovingFrom = plan.moves[0].from

        let outcome = await migration.carryOut(plan)

        // Both files are exactly where they started, and each day that could
        // not move is reported once rather than at every step it missed.
        let files = try await store.listFiles()
        #expect(files == ["2026/d03-04.md", "2026/d04-03.md"])
        #expect(outcome.leftBehind.count == 2)
        #expect(Set(outcome.leftBehind.map(\.day)).count == 2)
        #expect(outcome.moved.isEmpty)
    }

    @Test("a folder with nothing to migrate is left alone and says so")
    func anEmptyPlanChangesNothing() async throws {
        let store = InMemoryJournalStore(["Reading/Dune.md": "Somebody else's note.\n"])
        let migration = JournalMigration(over: store)

        let plan = try await migration.plan(changingFrom: old, to: new)
        let outcome = await migration.carryOut(plan)

        #expect(plan.isEmpty)
        let files = await store.listFiles()
        #expect(files == ["Reading/Dune.md"])
        #expect(outcome.moved.isEmpty)
        #expect(outcome.parked.isEmpty)
        #expect(outcome.leftBehind.isEmpty)
        #expect(outcome.wentThrough)
    }
}

/// A Journal Store that refuses to move one particular file, as a folder does
/// for a file iCloud has not brought down yet.
///
/// Unchecked because what it refuses is set by the test before the code under
/// test runs, and only read while it does.
private final class ObstructiveJournalStore: JournalStore, @unchecked Sendable {
    private let folder: InMemoryJournalStore

    var refuseMovingFrom: String?

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
        try await folder.write(contents, at: relativePath)
    }

    func create(_ contents: Data, at relativePath: String) async throws {
        try await folder.create(contents, at: relativePath)
    }

    func move(from source: String, to destination: String) async throws {
        if source == refuseMovingFrom { throw JournalStoreError.fileNotFound(source) }
        try await folder.move(from: source, to: destination)
    }
}
