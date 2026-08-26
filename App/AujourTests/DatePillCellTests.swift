import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

// The one thing the date pill's grid has to be, held to headlessly: its six
// states are six *different* states. A calendar whose "written on" and "empty"
// cells came out the same colour would be a month with no journal in it, which
// is the one thing this app must never look like when there is one (ADR 0001).
//
// The look is a value, so this needs no screenshot — and it is asked of every
// accent in both appearances, because a set of nine colours is nine chances for
// two states to collapse into one.

private let appearances: [(name: String, style: UIUserInterfaceStyle)] = [
    ("light", .light), ("dark", .dark),
]

/// The August of a journal with one day written in it, seen on the 15th, with
/// the 12th picked out of the grid — which puts all six states on one screen.
///
/// Built from a real ``JournalCalendar`` over a real folder rather than from
/// hand-made cells: what is being measured is what the app draws, and a `Day`
/// assembled here would be a second idea of which days are which.
@MainActor
private struct AMonthWithEverySortOfDay {
    let month: JournalCalendar.Month

    init() async {
        var noon = DateComponents()
        noon.year = 2026
        noon.month = 8
        noon.day = 15
        noon.hour = 12
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = utc.date(from: noon)!

        let calendar = JournalCalendar(
            store: InMemoryJournalStore(["2026/08/2026-08-10.md": "Words.\n"]),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { now }
        )
        // The marks are a scan of the folder and nothing else (ADR 0001), so
        // without this the day with a file would look like a day without one.
        await calendar.scan()
        calendar.pick(JournalDay(year: 2026, month: 8, day: 12))
        month = calendar.month
    }

    /// A day of the month either side, by its whole date.
    func day(_ day: JournalDay) -> JournalCalendar.Day {
        month.cells.first { $0.day == day }!
    }

    /// A day of the August on screen, by its number.
    func august(_ dayOfMonth: Int) -> JournalCalendar.Day {
        day(JournalDay(year: 2026, month: 8, day: dayOfMonth))
    }

    /// The six states, named — so that a failure says which two of them
    /// collapsed into each other.
    var everyState: [(name: String, day: JournalCalendar.Day)] {
        [
            ("has entry", august(10)),
            ("empty", august(11)),
            ("today", august(15)),
            ("being written", august(12)),
            ("locked", august(20)),
            ("other month", day(JournalDay(year: 2026, month: 7, day: 31))),
        ]
    }
}

@MainActor
@Suite("Every state a day in the grid can be in")
struct DayCellLookTests {
    /// Asked first, because every measurement below is only worth having if
    /// the six cells really are in the six states they are named for.
    @Test("the six states are the six the grid has to tell apart")
    func theSixStatesAreThere() async {
        let august = await AMonthWithEverySortOfDay()

        #expect(august.august(10).isJournaled && !august.august(10).isBeingWritten)
        #expect(!august.august(11).isJournaled && august.august(11).relation == .past)
        #expect(august.august(15).relation == .current && !august.august(15).isBeingWritten)
        #expect(august.august(12).isBeingWritten)
        #expect(!august.august(20).isOpenable)
        #expect(august.day(JournalDay(year: 2026, month: 7, day: 31)).isInTheMonthOnScreen == false)
    }

    /// The whole of "every cell state is distinguishable". Six looks, and no
    /// two of them the same — on any accent, in either appearance.
    @Test("no two states are drawn the same way", arguments: Accent.allCases)
    func theSixStatesStaySix(accent: Accent) async {
        let august = await AMonthWithEverySortOfDay()

        for appearance in appearances {
            let drawn = august.everyState.map {
                (name: $0.name, look: DayCellLook($0.day, accent: accent).asDrawn(in: appearance.style))
            }
            for (one, other) in everyPair(of: drawn) {
                #expect(
                    one.look != other.look,
                    """
                    \(one.name) and \(other.name) are drawn identically on \(accent.name) \
                    in \(appearance.name): \(one.look)
                    """
                )
            }
        }
    }

    /// The number on the day being written is the paper, on a solid accent —
    /// the one pairing in the grid that is not ink on a ground, and so the one
    /// the palette's own floor does not already answer for (ADR 0006).
    @Test("the day being written is legible on its own fill", arguments: Accent.allCases)
    func theFilledDayIsLegible(accent: Accent) async {
        let look = await DayCellLook(AMonthWithEverySortOfDay().august(12), accent: accent)

        for appearance in appearances {
            let numeral = Landed(look.numeral, in: appearance.style, over: look.fill)
            let fill = Landed(look.fill, in: appearance.style)
            #expect(
                numeral.contrast(against: fill) >= 4.5,
                """
                the day being written on \(accent.name) in \(appearance.name) is \
                \(numeral.contrast(against: fill)), under 4.5:1
                """
            )
        }
    }

    /// Today's number sits on a wash of the accent rather than on the page, so
    /// it is the accent's *ink* shade that has to carry it.
    @Test("today is legible on its own tint", arguments: Accent.allCases)
    func todayIsLegible(accent: Accent) async {
        let look = await DayCellLook(AMonthWithEverySortOfDay().august(15), accent: accent)

        for appearance in appearances {
            for ground in [Palette.background, Palette.glassSolid] {
                let wash = Landed(look.fill, in: appearance.style, over: ground)
                let numeral = Landed(look.numeral, in: appearance.style, over: look.fill)
                #expect(
                    numeral.contrast(against: wash) >= 4.5,
                    """
                    today on \(accent.name) in \(appearance.name) is \
                    \(numeral.contrast(against: wash)), under 4.5:1
                    """
                )
            }
        }
    }

    @Test("only a day with a file is marked, and never the one already filled")
    func onlyWrittenDaysAreMarked() async {
        let august = await AMonthWithEverySortOfDay()

        #expect(DayCellLook(august.august(10), accent: .driftwood).dot != nil)
        #expect(DayCellLook(august.august(11), accent: .driftwood).dot == nil)
        // The 12th is the day being written: its fill says more than a dot
        // could, and a dot on top of it would be a mark nobody could see.
        #expect(DayCellLook(august.august(12), accent: .driftwood).dot == nil)
    }

    @Test("only the months either side of the one on screen are turned down")
    func onlyTheNeighbouringMonthsAreDimmed() async {
        let august = await AMonthWithEverySortOfDay()

        #expect(DayCellLook(august.august(11), accent: .driftwood).dimmed == false)
        #expect(DayCellLook(august.august(20), accent: .driftwood).dimmed == false)
        let july = august.day(JournalDay(year: 2026, month: 7, day: 31))
        #expect(DayCellLook(july, accent: .driftwood).dimmed)
    }
}

extension DayCellLook {
    /// Everything about this look as it actually comes out on a screen, in one
    /// string — so that "these two states are drawn the same" is one
    /// comparison and not four.
    fileprivate func asDrawn(in style: UIUserInterfaceStyle) -> String {
        [
            fill.resolved(in: style),
            numeral.resolved(in: style),
            dot?.resolved(in: style) ?? "no dot",
            dimmed ? "dimmed" : "full",
        ].joined(separator: " · ")
    }
}

/// Every unordered pair, so that "no two of these" is said once rather than
/// with two nested loops and an index comparison in every test that needs it.
private func everyPair<Element>(of items: [Element]) -> [(Element, Element)] {
    items.indices.flatMap { one in
        items[(one + 1)...].map { (items[one], $0) }
    }
}
