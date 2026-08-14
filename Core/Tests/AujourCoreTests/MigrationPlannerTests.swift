import Foundation
import Testing

@testable import AujourCore

// Changing the Path Template changes what an Entry *is* (ADR 0002), so the
// files already in the folder are suddenly in the wrong shape. Aujour offers
// to move them, and this is the arithmetic behind that offer: which file goes
// where, and which days have something already sitting at the path they were
// going to.
//
// Nothing here touches a folder. The plan is a value worked out from a
// listing, which is what lets the whole of it — collisions, paths another
// Entry is vacating, two days that swap — be tested against a handful of
// strings.

private let old = try! PathTemplate("YYYY/MM/YYYY-MM-DD")
private let new = try! PathTemplate("[Journal]/YYYY-MM-DD")

/// The two templates that put the month and the day the other way round —
/// the one everyday change whose moves form a ring.
private let monthFirst = try! PathTemplate("YYYY/[d]MM[-]DD")
private let dayFirst = try! PathTemplate("YYYY/[d]DD[-]MM")

private let firstOfMarch = JournalDay(year: 2026, month: 3, day: 1)
private let secondOfMarch = JournalDay(year: 2026, month: 3, day: 2)

@Suite("Planning a Path Template change")
struct MigrationPlannerTests {
    @Test("every Entry moves to where the new template puts it")
    func entriesMoveToTheirNewPaths() {
        let plan = MigrationPlanner().plan(
            for: ["2026/03/2026-03-01.md", "2026/03/2026-03-02.md"],
            changingFrom: old,
            to: new
        )

        #expect(
            plan.moves == [
                MigrationPlan.Move(
                    day: firstOfMarch,
                    from: "2026/03/2026-03-01.md",
                    to: "Journal/2026-03-01.md",
                    destination: .theDaysNewPath
                ),
                MigrationPlan.Move(
                    day: secondOfMarch,
                    from: "2026/03/2026-03-02.md",
                    to: "Journal/2026-03-02.md",
                    destination: .theDaysNewPath
                ),
            ]
        )
        #expect(plan.collisions.isEmpty)
        #expect(plan.entryCount == 2)
    }

    @Test("a folder with no Entries in it has nothing to move")
    func aFolderWithNoEntriesPlansNothing() {
        // Somebody's vault: notes that are none of Aujour's business, and not
        // one of them at a path the old template renders.
        let plan = MigrationPlanner().plan(
            for: ["Reading/Dune.md", "attachments/2026/03/photo.jpg", "index.md"],
            changingFrom: old,
            to: new
        )

        #expect(plan.isEmpty)
        #expect(plan.entryCount == 0)
    }

    @Test("files that are not Entries are left where they are")
    func onlyEntriesAreMoved() {
        let plan = MigrationPlanner().plan(
            for: [
                "2026/03/2026-03-01.md",
                // A note Obsidian made in the folder the Entries live in.
                "2026/03/Groceries.md",
                // A Parked File from an earlier divergence, which is never an
                // Entry (ADR 0002) and so never migrates.
                "2026/03/2026-03-01_1.md",
                "attachments/2026/03/photo.jpg",
            ],
            changingFrom: old,
            to: new
        )

        #expect(plan.moves.map(\.from) == ["2026/03/2026-03-01.md"])
    }

    @Test("a day the new template leaves where it is stays put")
    func aPathTheChangeDoesNotAlterIsNotAMove() {
        // The month folder spelled out rather than rendered: every path this
        // template names for a March day is the one the old template names
        // too, so March has nothing to move and February has.
        let march = try! PathTemplate("YYYY/[03]/YYYY-MM-DD")

        let plan = MigrationPlanner().plan(
            for: ["2026/03/2026-03-01.md", "2026/02/2026-02-28.md"],
            changingFrom: old,
            to: march
        )

        #expect(plan.moves.map(\.from) == ["2026/02/2026-02-28.md"])
    }

    @Test("changing a template for the same template plans nothing")
    func noChangeIsNoMigration() {
        let plan = MigrationPlanner().plan(
            for: ["2026/03/2026-03-01.md"],
            changingFrom: old,
            to: old
        )

        #expect(plan.isEmpty)
    }
}

@Suite("Planning a change onto paths that are already taken")
struct MigrationCollisionTests {
    @Test("a day whose new path is taken is parked beside it, and the file there stays")
    func aCollidingEntryIsParkedBesideTheFileAlreadyThere() {
        // The vault already keeps daily notes in `Journal/`, which is exactly
        // why somebody points Aujour at that shape — and exactly how two
        // files come to claim one day (ADR 0002).
        let plan = MigrationPlanner().plan(
            for: ["2026/03/2026-03-01.md", "Journal/2026-03-01.md"],
            changingFrom: old,
            to: new
        )

        #expect(
            plan.moves == [
                MigrationPlan.Move(
                    day: firstOfMarch,
                    from: "2026/03/2026-03-01.md",
                    to: "Journal/2026-03-01_1.md",
                    destination: .besideTheFileAlreadyThere("Journal/2026-03-01.md")
                )
            ]
        )
        #expect(plan.collisions == plan.moves)
        // The file that was there is named, because that is what the user is
        // being asked about — and nothing in the plan touches it.
        #expect(!plan.moves.map(\.to).contains("Journal/2026-03-01.md"))
    }

    @Test("a collision takes the first free suffix, in a folder that already holds one")
    func aCollisionTakesTheFirstFreeSuffix() {
        let plan = MigrationPlanner().plan(
            for: [
                "2026/03/2026-03-01.md",
                "Journal/2026-03-01.md",
                "Journal/2026-03-01_1.md",
            ],
            changingFrom: old,
            to: new
        )

        #expect(plan.moves.map(\.to) == ["Journal/2026-03-01_2.md"])
    }

    @Test("two Entries colliding in one folder are parked under names of their own")
    func twoCollisionsDoNotTakeTheSameName() {
        // Both days land in `Journal/`, both find something there, and the
        // suffixes are chosen against each other as well as against the
        // folder — two versions of two days never share a path.
        let plan = MigrationPlanner().plan(
            for: [
                "2026/03/2026-03-01.md",
                "2026/03/2026-03-02.md",
                "Journal/2026-03-01.md",
                "Journal/2026-03-02.md",
            ],
            changingFrom: old,
            to: new
        )

        #expect(plan.collisions.count == 2)
        #expect(Set(plan.moves.map(\.to)).count == 2)
    }

    @Test("an Entry on its way out is not something to collide with")
    func aPathAnotherEntryIsLeavingIsNotACollision() {
        // Each of these two days is moving onto the path the other is
        // leaving, so nothing is in anybody's way and nothing is parked. What
        // it takes is an order — which is the next test.
        let plan = MigrationPlanner().plan(
            for: ["2026/d03-04.md", "2026/d04-03.md"],
            changingFrom: monthFirst,
            to: dayFirst
        )

        #expect(plan.collisions.isEmpty)
        #expect(plan.entryCount == 2)
    }

    @Test("two days that swap paths both arrive, by way of a name of their own")
    func aSwapIsBrokenByMovingOneEntryAside() {
        // The month and the day the other way round: the 4th of March is
        // going to where the 3rd of April is, and the 3rd of April to where
        // the 4th of March is. No order of two moves does that, so one file
        // waits at a name of its own on the way.
        let files = ["2026/d03-04.md", "2026/d04-03.md"]

        let plan = MigrationPlanner().plan(for: files, changingFrom: monthFirst, to: dayFirst)

        // Three moves for two Entries: one of them goes aside and then on.
        #expect(plan.moves.count == 3)
        #expect(plan.moves.first?.destination == .asideWhileThePathClears)
        // Both days end up at the path the new template names for them.
        #expect(
            Set(plan.moves.filter { $0.destination == .theDaysNewPath }.map(\.to))
                == ["2026/d04-03.md", "2026/d03-04.md"]
        )
        expectNothingIsOverwritten(by: plan, in: files)
    }

    @Test("a folder full of swapped days is planned without one file landing on another")
    func aFolderOfSwapsIsStillSafeToCarryOut() {
        // The first twelve days of the first twelve months: every day has a
        // partner it swaps with, except the twelve that swap with themselves.
        let days = (1...12).flatMap { month in
            (1...12).map { JournalDay(year: 2026, month: month, day: $0) }
        }
        let files = days.map(monthFirst.render)

        let plan = MigrationPlanner().plan(for: files, changingFrom: monthFirst, to: dayFirst)

        #expect(plan.entryCount == days.count - 12)
        #expect(plan.collisions.isEmpty)
        expectNothingIsOverwritten(by: plan, in: files)
    }
}

/// Walks a plan over the folder it was made for, one move at a time, and
/// fails if any of them would land on a file that is there.
///
/// This is the promise the whole migration rests on — nothing is ever
/// overwritten (ADR 0002) — said as arithmetic, so that it can be asserted
/// about a plan for a hundred and forty-four days as easily as about one for
/// two.
private func expectNothingIsOverwritten(by plan: MigrationPlan, in files: [String]) {
    var folder = Set(files)
    for move in plan.moves {
        #expect(folder.contains(move.from), "'\(move.from)' is not in the folder to be moved")
        #expect(!folder.contains(move.to), "moving '\(move.from)' would overwrite '\(move.to)'")
        folder.remove(move.from)
        folder.insert(move.to)
    }
}
