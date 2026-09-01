import AujourCore
import Testing
import UIKit

@testable import Aujour

// The three things a Path Template change says for itself: what it would do
// before it does any of it, how far through it is while it is doing it, and
// what became of every day afterwards.
//
// Words and colours, both without a screen. The words are the whole of the
// decision — a migration is skippable, and what is being skipped has to be
// sayable (ADR 0002) — and the colours are the promise underneath them:
// nothing in this flow is a failure. A day parked beside a file that was
// already there is not a loss, a day the folder would not move is not a loss
// either, and skipping the whole thing is a choice somebody is entitled to
// make.

private let march1 = JournalDay(year: 2026, month: 3, day: 1)
private let march2 = JournalDay(year: 2026, month: 3, day: 2)
private let march3 = JournalDay(year: 2026, month: 3, day: 3)

/// A plan that moves these days, and parks the ones named as colliding.
private func plan(
    moving days: [JournalDay],
    colliding: [JournalDay] = []
) -> MigrationPlan {
    MigrationPlan(
        moves: days.map { day in
            let taken = colliding.contains(day)
            return MigrationPlan.Move(
                day: day,
                from: "\(day.year)/\(day).md",
                to: taken ? "Journal/\(day)_1.md" : "Journal/\(day).md",
                destination: taken
                    ? .besideTheFileAlreadyThere("Journal/\(day).md")
                    : .theDaysNewPath
            )
        }
    )
}

private struct TheFolderWouldNot: Error {}

private func outcome(
    moved: [JournalDay] = [],
    parked: [JournalDay] = [],
    leftBehind: [JournalDay] = []
) -> MigrationOutcome {
    MigrationOutcome(
        moved: moved,
        parked: parked.map { MigrationOutcome.ParkedFile(day: $0, path: "Journal/\($0)_1.md") },
        leftBehind: leftBehind.map {
            MigrationOutcome.LeftBehind(
                day: $0,
                path: "\($0.year)/\($0).md",
                problem: TheFolderWouldNot()
            )
        }
    )
}

@MainActor
@Suite("What a path template change says before, during and after")
struct MigrationScreenTests {

    // MARK: - Before anything moves

    /// The count in prose and not as a bare number, because it is what the
    /// user is agreeing to: a screen that said "3" would be asking them to
    /// work out what of theirs it was about.
    @Test("the offer says how many entries it is about")
    func theOfferCountsTheEntries() {
        #expect(offer(plan(moving: [march1, march2, march3])).question == "Move your 3 entries?")
        #expect(offer(plan(moving: [march1])).question == "Move your 1 entry?")
    }

    /// Every collision named, one by one, and named by the file it *would be
    /// parked under* rather than by the file it is now — that name is what
    /// the user will go looking for in Obsidian or in Files, and the whole of
    /// what being asked first is worth (ADR 0002).
    @Test("the collisions are called out, each by the name it would be parked under")
    func theOfferNamesEveryCollision() {
        let asked = offer(plan(moving: [march1, march2, march3], colliding: [march1, march3]))

        #expect(asked.collisionHeading == "2 days already have a file where they would go")
        #expect(asked.colliding.map(\.name) == ["2026-03-01_1.md", "2026-03-03_1.md"])
    }

    @Test("one collision is said in the singular")
    func oneCollisionIsSaidInTheSingular() {
        let asked = offer(plan(moving: [march1, march2], colliding: [march1]))

        #expect(asked.collisionHeading == "1 day already has a file where it would go")
    }

    /// Nothing to call out is nothing said. A heading over an empty list is a
    /// worry the user has no way to act on.
    @Test("a change that collides with nothing says nothing about collisions")
    func noCollisionsIsNoHeading() {
        #expect(offer(plan(moving: [march1, march2])).collisionHeading == nil)
    }

    /// The one consequence nobody would guess, and the reason ADR 0002 says
    /// the prompt has to carry it: a daily note that changes name is a note
    /// the vault's own links no longer reach.
    @Test("the offer warns that renaming breaks a vault's links")
    func theOfferWarnsAboutLinks() {
        #expect(MigrationOffer.linkWarning.contains("[[links]]"))
    }

    /// Both ways out are the user's to take, so both are drawn the same. A
    /// skipped migration is a legitimate choice and not a mistake, and a
    /// screen that whispered one of its two answers would be making it for
    /// them.
    @Test("moving and leaving are offered in the same weight")
    func bothWaysOutAreFirstClass() {
        #expect(MigrationOffer.moveAction == "Move Them")
        #expect(MigrationOffer.leaveAction == "Leave Them Where They Are")

        // One treatment draws both, so there is no second style on the screen
        // for either way out to be quietly demoted into.
        let way = MigrationAction(words: MigrationOffer.moveAction, accent: .clay, identifier: "", act: {})
        #expect(way.ink == Accent.clay.inkColor)
        #expect(way.ring == Accent.clay.uiColor)
    }

    // MARK: - While it moves

    /// Determinate, and that is the ticket: a migration touches every file in
    /// somebody's journal, which can run long enough that a spinner is a lie
    /// about whether anything is happening at all.
    @Test("how far through it is, as a fraction of the days it is about")
    func theBarIsDeterminate() {
        let halfway = MigrationUnderway(
            progress: MigrationProgress(settled: 6, total: 12),
            accent: .clay
        )

        #expect(halfway.fraction == 0.5)
        #expect(halfway.tally == "6 of 12 entries")
    }

    @Test("nothing settled yet is a bar at nought, not an absent one")
    func theBarStartsEmptyRatherThanAbsent() {
        let starting = MigrationUnderway(
            progress: MigrationProgress(settled: 0, total: 12),
            accent: .clay
        )

        #expect(starting.fraction == 0)
        #expect(starting.tally == "0 of 12 entries")
    }

    // MARK: - What became of them

    @Test("the report says how much of the journal moved")
    func theReportCountsWhatMoved() {
        #expect(report(outcome(moved: [march1, march2])).headline == "2 entries moved.")
        #expect(report(outcome(moved: [march1])).headline == "1 entry moved.")
    }

    /// Counted over the days that were parked as well, because both of those
    /// moved — a day whose new path was taken is at a name beside it, and the
    /// sentence underneath says which. "0 entries moved" over a folder where a
    /// file did move is the one thing this must not say.
    @Test("a day parked beside a file already there is a day that moved")
    func parkedDaysAreCountedAsMoved() {
        #expect(report(outcome(moved: [march1], parked: [march2])).headline == "2 entries moved.")
    }

    @Test("a migration that moved nothing says so plainly")
    func nothingMovedIsSaidPlainly() {
        #expect(report(outcome(leftBehind: [march1])).headline == "Nothing moved.")
    }

    /// All three, on the one outcome that has all three. A migration comes
    /// back partial more often than it comes back whole, and a report that
    /// mentioned only the good half would leave the user to notice the rest
    /// in their folder.
    @Test("a partial outcome reports what moved, what was parked and what was left behind")
    func aPartialOutcomeReportsAllThree() {
        let said = report(outcome(moved: [march1], parked: [march2], leftBehind: [march3]))

        #expect(said.headline == "2 entries moved.")
        // Named, both of them: a parked file by the name it is under now, a
        // day left behind by the day it is.
        #expect(said.parkedFiles?.contains("2026-03-02_1.md") == true)
        #expect(said.leftBehind?.contains("2026-03-03") == true)
        // And the one thing that is true of every one of them.
        #expect(said.leftBehind?.contains("Nothing was lost") == true)
    }

    @Test("a migration that went through says nothing about parking or leaving behind")
    func awholeOutcomeSaysOnlyWhatMoved() {
        let said = report(outcome(moved: [march1, march2]))

        #expect(said.parkedFiles == nil)
        #expect(said.leftBehind == nil)
    }

    // MARK: - What all three are drawn in

    /// **No error colour anywhere in the flow**, which is what this holds:
    /// every colour any of the three states draws with is one of the
    /// identity's own — the reader's accent and the inks — and the identity
    /// has no error colour in it to reach for.
    ///
    /// Asked of all nine accents, because each screen is tinted by whichever
    /// one the reader chose and a fixed colour would pass on one of them.
    @Test("nothing in the flow is drawn in a warning", arguments: Accent.allCases)
    func theWholeFlowIsTheAccents(accent: Accent) {
        let asked = offer(plan(moving: [march1], colliding: [march1]), in: accent)
        #expect(asked.mark == accent.uiColor)
        #expect(asked.questionInk == Palette.ink)
        #expect(asked.detailInk == Palette.inkMuted)

        let way = MigrationAction(words: MigrationOffer.moveAction, accent: accent, identifier: "", act: {})
        #expect(way.ink == accent.inkColor)
        #expect(way.ring == accent.uiColor)

        let moving = MigrationUnderway(
            progress: MigrationProgress(settled: 1, total: 2),
            accent: accent
        )
        #expect(moving.barInk == accent.uiColor)
        #expect(moving.headlineInk == Palette.ink)
        #expect(moving.tallyInk == Palette.inkMuted)

        // The partial outcome, which is the one an app would have been
        // tempted to colour like a failure.
        let said = report(outcome(moved: [march1], parked: [march2], leftBehind: [march3]), in: accent)
        #expect(said.mark == accent.uiColor)
        #expect(said.headlineInk == Palette.ink)
        #expect(said.detailInk == Palette.inkMuted)

        // And the claim underneath all of those, made once over the whole
        // flow: every colour any of the three states reaches for is one the
        // identity holds. A screen that had picked up `.systemRed`, or any
        // other colour from outside the palette, fails here — which the
        // assertions above, each naming the token they expect, cannot catch
        // on their own.
        let theIdentitys: Set<UIColor> = Set(Palette.everyToken.map(\.colour))
            .union([accent.uiColor, accent.inkColor, accent.softColor, accent.softerColor])
        let drawnWith = [
            asked.mark, asked.questionInk, asked.detailInk,
            way.ink, way.ring, way.wash,
            moving.barInk, moving.headlineInk, moving.tallyInk,
            said.mark, said.headlineInk, said.detailInk,
            EntryPathSection.rejectionInk,
        ]
        for colour in drawnWith {
            #expect(theIdentitys.contains(colour), "\(colour) is not one of the identity's")
        }
    }

    /// The flow starts at the field, where a template halfway to being typed
    /// is refused a dozen times on the way to one that is not. An app that
    /// coloured that like a fault would be telling somebody off for typing.
    @Test("a template that cannot be read is refused without a warning colour")
    func arefusedTemplateIsNotDrawnAsAFailure() {
        #expect(EntryPathSection.rejectionInk == Palette.ink)
    }

    // MARK: - How many of them get named

    /// A vault that already keeps its daily notes where the new entry path
    /// puts them collides on every single day. Every one of those is named in
    /// the *preview*, which is a list somebody scrolls; the report is a
    /// paragraph, and four hundred names run together in one is a paragraph
    /// nobody reads.
    @Test("a report about more days than fit says how many it did not name")
    func alongReportNamesAFewAndCountsTheRest() {
        let manyDays = (1...9).map { JournalDay(year: 2026, month: 3, day: $0) }
        let said = report(outcome(parked: manyDays))

        #expect(said.parkedFiles?.contains("2026-03-01_1.md") == true)
        #expect(said.parkedFiles?.contains("and 4 more") == true)
        // Nothing hidden: the count at the front is still all nine.
        #expect(said.headline == "9 entries moved.")
    }
}

@MainActor
private func offer(_ plan: MigrationPlan, in accent: Accent = .clay) -> MigrationOffer {
    MigrationOffer(plan: plan, accent: accent, move: {}, leaveThem: {})
}

@MainActor
private func report(_ outcome: MigrationOutcome, in accent: Accent = .clay) -> MigrationReport {
    MigrationReport(outcome: outcome, accent: accent)
}
