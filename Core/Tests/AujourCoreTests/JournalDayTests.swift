import Foundation
import Testing
@testable import AujourCore

// Instants are written as wall-clock readings in a named zone, because that
// is how the domain talks about them: "1 AM on March 2nd in Paris".
private func instant(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int, _ minute: Int = 0,
    in timeZone: TimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

private let paris = TimeZone(identifier: "Europe/Paris")!
private let utc = TimeZone(secondsFromGMT: 0)!

@Suite("JournalDay resolution")
struct JournalDayResolutionTests {
    @Test("1 AM with a 4 AM rollover still belongs to the previous day")
    func lateNightWritingLandsOnTheDayBeingDescribed() {
        let day = JournalDay.current(
            at: instant(2026, 3, 2, 1, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )

        #expect(day == JournalDay(year: 2026, month: 3, day: 1))
    }

    @Test("the day advances exactly at the Rollover Hour, not a minute before")
    func rolloverHourIsInclusive() {
        let fourAM = JournalDay.current(
            at: instant(2026, 3, 2, 4, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )
        let oneMinuteEarlier = JournalDay.current(
            at: instant(2026, 3, 2, 3, 59, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )

        #expect(fourAM == JournalDay(year: 2026, month: 3, day: 2))
        #expect(oneMinuteEarlier == JournalDay(year: 2026, month: 3, day: 1))
    }

    @Test("the default rollover is midnight, so the Journal Day is the calendar date")
    func midnightDefaultMatchesObsidian() {
        #expect(RolloverHour.midnight.hour == 0)

        let justBeforeMidnight = JournalDay.current(
            at: instant(2026, 3, 1, 23, 59, in: paris),
            in: paris,
            rolloverHour: .midnight
        )
        let midnight = JournalDay.current(
            at: instant(2026, 3, 2, 0, in: paris),
            in: paris,
            rolloverHour: .midnight
        )

        #expect(justBeforeMidnight == JournalDay(year: 2026, month: 3, day: 1))
        #expect(midnight == JournalDay(year: 2026, month: 3, day: 2))
    }

    @Test("rolling back crosses month, year and leap-day boundaries")
    func previousDayCrossesBoundaries() {
        let newYear = JournalDay.current(
            at: instant(2026, 1, 1, 2, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )
        let afterLeapDay = JournalDay.current(
            at: instant(2028, 3, 1, 2, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )

        #expect(newYear == JournalDay(year: 2025, month: 12, day: 31))
        #expect(afterLeapDay == JournalDay(year: 2028, month: 2, day: 29))
    }

    @Test("the same instant belongs to different Journal Days in different zones")
    func resolutionIsRelativeToTheGivenZone() {
        let newYearInParis = instant(2026, 1, 1, 0, 30, in: paris)
        let newYork = TimeZone(identifier: "America/New_York")!

        #expect(
            JournalDay.current(at: newYearInParis, in: paris, rolloverHour: .midnight)
                == JournalDay(year: 2026, month: 1, day: 1)
        )
        #expect(
            JournalDay.current(at: newYearInParis, in: newYork, rolloverHour: .midnight)
                == JournalDay(year: 2025, month: 12, day: 31)
        )
    }

    @Test("an out-of-range Rollover Hour is rejected")
    func rolloverHourIsValidated() {
        #expect(RolloverHour(hour: -1) == nil)
        #expect(RolloverHour(hour: 24) == nil)
        #expect(RolloverHour(hour: 23)?.hour == 23)
    }

    @Test("a Rollover Hour encodes as a bare hour, and a corrupt one is refused")
    func rolloverHourDecodingIsValidated() throws {
        let encoded = try JSONEncoder().encode(RolloverHour(hour: 4)!)

        #expect(String(decoding: encoded, as: UTF8.self) == "4")
        #expect(try JSONDecoder().decode(RolloverHour.self, from: encoded) == RolloverHour(hour: 4))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RolloverHour.self, from: Data("99".utf8))
        }
    }
}

@Suite("JournalDay classification")
struct JournalDayRelationTests {
    private let now = instant(2026, 3, 2, 1, in: paris)
    private let fourAM = RolloverHour(hour: 4)!

    @Test("a Journal Day is past, current or future relative to an instant")
    func classifiesAgainstTheCurrentJournalDay() {
        // 1 AM on March 2nd with a 4 AM rollover: March 1st is still current.
        #expect(
            JournalDay(year: 2026, month: 2, day: 28)
                .relation(to: now, in: paris, rolloverHour: fourAM) == .past
        )
        #expect(
            JournalDay(year: 2026, month: 3, day: 1)
                .relation(to: now, in: paris, rolloverHour: fourAM) == .current
        )
        #expect(
            JournalDay(year: 2026, month: 3, day: 2)
                .relation(to: now, in: paris, rolloverHour: fourAM) == .future
        )
    }

    @Test("the calendar date ahead of the rollover is future, not current")
    func todaysCalendarDateIsFutureBeforeRollover() {
        let today = JournalDay(year: 2026, month: 3, day: 2)

        #expect(today.relation(to: now, in: paris, rolloverHour: fourAM) == .future)
        #expect(today.relation(to: now, in: paris, rolloverHour: .midnight) == .current)
    }
}

// Paris springs forward on 2026-03-29 (02:00 → 03:00, so 2 AM never happens)
// and falls back on 2026-10-25 (03:00 → 02:00, so 2:30 AM happens twice).
@Suite("JournalDay across DST transitions")
struct JournalDayDaylightSavingTests {
    @Test("the hour skipped by spring-forward does not skip a Journal Day")
    func springForwardKeepsBothSidesOnTheRightDay() {
        let rollover = RolloverHour(hour: 2)!

        let beforeTheGap = JournalDay.current(
            at: instant(2026, 3, 29, 1, 30, in: paris),
            in: paris,
            rolloverHour: rollover
        )
        let afterTheGap = JournalDay.current(
            at: instant(2026, 3, 29, 3, 30, in: paris),
            in: paris,
            rolloverHour: rollover
        )

        #expect(beforeTheGap == JournalDay(year: 2026, month: 3, day: 28))
        #expect(afterTheGap == JournalDay(year: 2026, month: 3, day: 29))
    }

    @Test("a 23-hour day still rolls over onto the correct previous day")
    func springForwardNightRollsBackOneDay() {
        let day = JournalDay.current(
            at: instant(2026, 3, 29, 3, 30, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )

        #expect(day == JournalDay(year: 2026, month: 3, day: 28))
    }

    @Test("the hour repeated by fall-back never moves the Journal Day backwards")
    func fallBackIsMonotonic() {
        let rollover = RolloverHour(hour: 2)!
        // 02:30 CEST (UTC+2) and, an hour later, 02:30 CET (UTC+1).
        let firstPass = instant(2026, 10, 25, 0, 30, in: utc)
        let secondPass = instant(2026, 10, 25, 1, 30, in: utc)

        let beforeRollover = JournalDay.current(
            at: instant(2026, 10, 25, 1, 30, in: paris),
            in: paris,
            rolloverHour: rollover
        )
        let first = JournalDay.current(at: firstPass, in: paris, rolloverHour: rollover)
        let second = JournalDay.current(at: secondPass, in: paris, rolloverHour: rollover)

        #expect(beforeRollover == JournalDay(year: 2026, month: 10, day: 24))
        #expect(first == JournalDay(year: 2026, month: 10, day: 25))
        #expect(second == JournalDay(year: 2026, month: 10, day: 25))
    }

    @Test("a 25-hour day still rolls over onto the correct previous day")
    func fallBackNightRollsBackOneDay() {
        let day = JournalDay.current(
            at: instant(2026, 10, 25, 1, 30, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )

        #expect(day == JournalDay(year: 2026, month: 10, day: 24))
    }

    @Test("resolution never skips or repeats a Journal Day across a DST week")
    func resolutionIsMonotonicAcrossTransitions() {
        for rolloverHour in [0, 2, 3, 4, 23] {
            let rollover = RolloverHour(hour: rolloverHour)!
            for transition in [instant(2026, 3, 29, 0, in: utc), instant(2026, 10, 25, 0, in: utc)] {
                var seen: [JournalDay] = []
                // Half-hour steps for three days either side of the transition.
                for step in stride(from: -144.0, through: 144.0, by: 1.0) {
                    let day = JournalDay.current(
                        at: transition.addingTimeInterval(step * 1800),
                        in: paris,
                        rolloverHour: rollover
                    )
                    if seen.last != day { seen.append(day) }
                }

                #expect(seen == seen.sorted(), "days went backwards with rollover \(rolloverHour)")
                #expect(Set(seen).count == seen.count, "a day recurred with rollover \(rolloverHour)")
                for (earlier, later) in zip(seen, seen.dropFirst()) {
                    #expect(
                        earlier.adding(days: 1) == later,
                        "rollover \(rolloverHour) skipped a day between \(earlier) and \(later)"
                    )
                }
            }
        }
    }
}
