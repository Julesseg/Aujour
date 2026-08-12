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

    /// The Journal Day `days` days later (or earlier, for a negative count).
    public func adding(days: Int) -> JournalDay {
        let calendar = JournalDay.arithmeticCalendar
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        let noon = calendar.date(from: components)!
        let shifted = calendar.date(byAdding: .day, value: days, to: noon)!
        let result = calendar.dateComponents([.year, .month, .day], from: shifted)
        return JournalDay(year: result.year!, month: result.month!, day: result.day!)
    }

    public static func < (lhs: JournalDay, rhs: JournalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// ISO-8601 calendar date, e.g. `2026-03-01`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Day arithmetic on a bare calendar date has no zone of its own, and UTC
    /// has no DST, so counting days there is plain.
    private static let arithmeticCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
