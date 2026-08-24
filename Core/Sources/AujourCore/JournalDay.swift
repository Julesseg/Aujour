import Foundation

/// The date an Entry belongs to.
///
/// A Journal Day is a plain calendar date — it carries no time zone and no
/// time of day. Which Journal Day a wall-clock instant belongs to is a
/// separate question, answered by `current(at:in:rolloverHour:)`.
public struct JournalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The Journal Day an instant belongs to: the local calendar date, except
    /// before the Rollover Hour, when the previous day is still current.
    public static func current(
        at instant: Date,
        in timeZone: TimeZone,
        rolloverHour: RolloverHour
    ) -> JournalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Compared as wall-clock components rather than by subtracting hours
        // from the instant, so DST transitions shift when the day rolls over
        // rather than which day an instant lands on.
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: instant)
        let localDay = JournalDay(
            year: components.year!,
            month: components.month!,
            day: components.day!
        )
        return rolloverHour.hasPassed(byLocalHour: components.hour!)
            ? localDay
            : localDay.adding(days: -1)
    }

    /// Where a Journal Day sits relative to a wall-clock instant. Future days
    /// are the ones the app locks; the current one is "today's Entry".
    public enum Relation: Hashable, Sendable {
        case past
        case current
        case future

        /// Whether a day this far along can be written in — every day up to
        /// today. A past day with no Entry is backfilled from the calendar,
        /// and a future one is visible there but locked: there is no Entry to
        /// write before the day has arrived (`v1-decisions.md`).
        public var allowsWriting: Bool { self != .future }
    }

    /// Classifies this Journal Day against the one current at `instant`.
    public func relation(
        to instant: Date,
        in timeZone: TimeZone,
        rolloverHour: RolloverHour
    ) -> Relation {
        let today = JournalDay.current(at: instant, in: timeZone, rolloverHour: rolloverHour)
        if self < today { return .past }
        if self > today { return .future }
        return .current
    }

    /// The first instant of this Journal Day in `timeZone`.
    public func startOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Noon always exists, even in the zones where DST skips midnight
        // itself; stepping back from it is how Foundation finds the real
        // first instant of the day.
        return calendar.startOfDay(for: noon(in: calendar))
    }

    /// The stretch of wall-clock time this Journal Day covers in `timeZone` —
    /// its own midnight to the next.
    ///
    /// The calendar date's stretch and not the Rollover Hour's, deliberately.
    /// The Rollover Hour decides which day somebody is *writing*; the day they
    /// are writing *about* is a calendar date, and it is the one their
    /// calendar app draws. At 1 AM under a 4 AM rollover the Entry is
    /// yesterday's, and so are the meetings in it — which is right, and would
    /// not be if this ran 4 AM to 4 AM and pulled tomorrow morning's alarm
    /// into the day being written.
    public func span(in timeZone: TimeZone) -> DateInterval {
        DateInterval(
            start: startOfDay(in: timeZone),
            end: adding(days: 1).startOfDay(in: timeZone)
        )
    }

    /// This Journal Day at the same wall-clock time as `other`.
    ///
    /// Spawning a template needs exactly this pairing: a backfilled Entry's
    /// date placeholders describe the day being written *about*, carrying the
    /// clock time it is being written *at*.
    public func date(atClockTimeOf other: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let clock = calendar.dateComponents([.hour, .minute, .second], from: other)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = clock.second
        // Nil only when that wall-clock time does not exist here — the hour a
        // spring-forward skips. The day is the part that has to stay right, so
        // give up the time of day rather than the date.
        return calendar.date(from: components) ?? startOfDay(in: timeZone)
    }

    /// The Journal Day `days` days later (or earlier, for a negative count).
    public func adding(days: Int) -> JournalDay {
        let calendar = JournalDay.arithmeticCalendar
        let shifted = calendar.date(byAdding: .day, value: days, to: noon(in: calendar))!
        let result = calendar.dateComponents([.year, .month, .day], from: shifted)
        return JournalDay(year: result.year!, month: result.month!, day: result.day!)
    }

    /// Midday on this Journal Day — the hour furthest from any DST seam, which
    /// makes it the safe footing for date arithmetic.
    private func noon(in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    public static func < (lhs: JournalDay, rhs: JournalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// ISO-8601 calendar date, e.g. `2026-03-01`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The day an ISO-8601 calendar date names — `description`'s inverse, for
    /// reading a Journal Day back out of somewhere one was written down.
    ///
    /// Strict about the spelling, and only that spelling: zero-padded, three
    /// ASCII-digit parts, naming a day that exists. What this reads is what
    /// Aujour itself wrote, so anything looser would be leniency towards
    /// nobody, and a date it guessed at would be a day's words filed under a
    /// day there is no such thing as.
    public init?(_ isoDate: String) {
        let parts = isoDate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            JournalDay.isReal(year: year, month: month, day: day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Whether a year/month/day triple names a day that exists.
    ///
    /// Here rather than beside either of the two things that read a day back
    /// out of writing — a path matched against a Path Template, and the
    /// ISO-8601 spelling above — because it is one question about a Journal
    /// Day, and two answers to it would be two ideas of which days there are.
    ///
    /// Done by hand rather than through `Calendar`, which switches to the
    /// Julian calendar before October 1582 and would disagree with what a Path
    /// Template renders for those years.
    static func isReal(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...lengths[month - 1]).contains(day)
    }

    /// The day as someone would say it out loud — "Sunday, March 1" — for a
    /// screen showing one day at a time.
    ///
    /// No year in it by default: the days a journal is opened on are today's
    /// and the ones either side of it, and the year is in the Entry's own file
    /// name for anyone who wants it. A day reached from the calendar asks for
    /// one, because that day can be years back and every February has a 14th.
    ///
    /// Localized, because this is the one place a Journal Day is read rather
    /// than matched — the paths it renders to are `description`'s business and
    /// stay ISO-8601 wherever the user is.
    public func spelledOut(
        withYear: Bool = false,
        in timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone)
            .weekday(.wide)
            .day()
            .month(.wide)
        if withYear { style = style.year() }
        return startOfDay(in: timeZone).formatted(style)
    }

    /// Day arithmetic on a bare calendar date has no zone of its own, and UTC
    /// has no DST, so counting days there is plain.
    private static let arithmeticCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
