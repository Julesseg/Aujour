import Foundation

/// One key and its value inside a Frontmatter: `mood: 7`, `tags: [walk]`,
/// `done: false` (`CONTEXT.md`, *Property*).
///
/// Its kind is what the value looks like and nothing else decides it — save
/// that `tags`, `aliases` and `cssclasses` are lists by name, because Obsidian
/// says so. There is no changing a Property's kind except by writing a value
/// of another shape, which is why a text field that is handed `7` writes
/// `"7"`: quoted, so that it reads back as the text it was typed into.
///
/// It knows which lines of the block it stands on, because a control's write
/// rewrites those lines and no others (ADR 0007).
public struct Property: Hashable, Sendable {
    public let key: String
    public let value: Value

    /// The lines of the block this Property is written on, counted from the
    /// opening fence at line 0: one line for a scalar, and one plus an item
    /// per line for a list written under its key.
    public let lines: Range<Int>

    /// How a list was written, kept so that rewriting it keeps the style it
    /// had. `nil` for anything that was not written as a list, which a new
    /// list under that key is written in block style.
    let listStyle: ListStyle?

    /// The value a Property holds, in the shape it was written in.
    public enum Value: Hashable, Sendable {
        case text(String)
        case number(Double)
        case checkbox(Bool)
        case date(year: Int, month: Int, day: Int)
        case dateTime(year: Int, month: Int, day: Int, hour: Int, minute: Int)
        case list([String])

        public var kind: Kind {
            switch self {
            case .text: .text
            case .number: .number
            case .checkbox: .checkbox
            case .date: .date
            case .dateTime: .dateTime
            case .list: .list
            }
        }

        /// The value as it is written in the block, bare: `7.5`, `true`,
        /// `2026-03-14` — what a field shows before anybody types into it.
        public var spelledOut: String { YAMLScalar.plain(self) }
    }

    /// The kinds a Property can be — what the row for one asks for when it is
    /// added, because the kind is what seeds the value's shape.
    public enum Kind: Hashable, CaseIterable, Sendable {
        case text
        case number
        case checkbox
        case date
        case dateTime
        case list

        /// A value of this kind's shape with nothing said yet: empty text,
        /// nought, unticked, the day itself, that day at this hour, an empty
        /// list.
        ///
        /// - Parameters:
        ///   - day: the Journal Day the Entry is for, which is the date a
        ///     date Property starts as — a Monday filled in on Friday is
        ///     about Monday.
        ///   - clock: the hour and minute a date-and-time Property starts at,
        ///     which is now on the device's own clock.
        public func seed(on day: JournalDay, at clock: (hour: Int, minute: Int)) -> Value {
            switch self {
            case .text: .text("")
            case .number: .number(0)
            case .checkbox: .checkbox(false)
            case .date: .date(year: day.year, month: day.month, day: day.day)
            case .dateTime:
                .dateTime(
                    year: day.year, month: day.month, day: day.day,
                    hour: clock.hour, minute: clock.minute
                )
            case .list: .list([])
            }
        }
    }

    /// How a list was written in the block.
    enum ListStyle: Hashable, Sendable {
        /// `tags: [walk, market]`, on the key's own line.
        case flow
        /// `tags:` and then `- walk` on the lines under it, each item
        /// indented by this much.
        case block(indent: String)
    }

    /// The keys Obsidian reads as lists whatever they hold.
    public static let listsByName: Set<String> = ["tags", "aliases", "cssclasses"]

    /// Whether this is one line's worth of name: something in it, no colon,
    /// no line break, no leading or trailing space, and nothing at its start
    /// that YAML would read as something other than a key — a `#` that
    /// makes the line a comment, a `- ` that makes it an item, a quote, a
    /// bracket, an anchor. The same rule the reader applies, so that a key
    /// this accepts is a key the block is still understood with.
    public static func isAKey(_ key: String) -> Bool {
        guard let first = key.first, let last = key.last else { return false }
        guard !first.isWhitespace, !last.isWhitespace else { return false }
        guard !YAMLScalar.startsWithAnIndicator(key), first != "#", key != "-",
            !key.hasPrefix("- ")
        else { return false }
        return !key.contains(where: { $0 == ":" || $0.isNewline })
    }

    /// The hour and minute a moment falls at on a clock in this zone — what
    /// a date-and-time Property starts as.
    public static func clock(at instant: Date, in timeZone: TimeZone) -> (hour: Int, minute: Int) {
        let parts = calendar(in: timeZone).dateComponents([.hour, .minute], from: instant)
        return (parts.hour ?? 0, parts.minute ?? 0)
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// A number as somebody typed it into a field, with whichever decimal
    /// separator their keyboard offered — a French decimal pad types `7,5`,
    /// and the block is written with a `.` whatever the locale.
    ///
    /// `nil` for anything that is not a plain decimal number: a field being
    /// cleared, a sign on its own, a dot with nothing after it.
    public static func number(typed text: String) -> Double? {
        let plain = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        // Digits, and at most one dot with digits on both sides of it: the
        // shape a decimal pad types, and nothing a field half-typed is.
        var rest = Substring(plain)
        if rest.first == "-" { rest = rest.dropFirst() }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) })
        else { return nil }
        return Double(plain)
    }
}

extension Property.Value {
    /// A date or a date-and-time Property as a moment on this zone's clock —
    /// what a picker is handed — and `nil` for any other kind, or for a date
    /// no calendar has (the 31st of a month with 30 days).
    ///
    /// The zone is the device's, because the block says none: a date and
    /// time is written device-local (`CONTEXT.md`, *Property*).
    public func moment(in timeZone: TimeZone) -> Date? {
        let parts: DateComponents
        switch self {
        case .date(let year, let month, let day):
            parts = DateComponents(year: year, month: month, day: day, hour: 0, minute: 0)
        case .dateTime(let year, let month, let day, let hour, let minute):
            parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        default:
            return nil
        }
        // A calendar rolls a day that is not there over into the next month
        // rather than refusing it, and the 30th of February is not a moment
        // this Property names.
        let calendar = Property.calendar(in: timeZone)
        guard let moment = calendar.date(from: parts),
            calendar.dateComponents([.year, .month, .day], from: moment)
                == DateComponents(year: parts.year, month: parts.month, day: parts.day)
        else { return nil }
        return moment
    }

    /// The date a moment falls on in this zone, as a date Property.
    public static func date(of moment: Date, in timeZone: TimeZone) -> Property.Value {
        let parts = Property.calendar(in: timeZone).dateComponents([.year, .month, .day], from: moment)
        return .date(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// A moment in this zone, to the minute, as a date-and-time Property.
    public static func dateTime(of moment: Date, in timeZone: TimeZone) -> Property.Value {
        let parts = Property.calendar(in: timeZone).dateComponents(
            [.year, .month, .day, .hour, .minute], from: moment
        )
        return .dateTime(
            year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1,
            hour: parts.hour ?? 0, minute: parts.minute ?? 0
        )
    }
}
