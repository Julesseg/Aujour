import Foundation

/// A Moment-format date pattern — the syntax Obsidian uses for daily-note
/// filenames and for `{{date:FORMAT}}` placeholders.
///
/// A pattern is a mix of *fields* (`YYYY`, `MM`, `dddd`, `HH`, …) and literal
/// text. Anything that is not a field renders verbatim, and text wrapped in
/// `[brackets]` is literal even when it looks like a field — so `[Week] W`
/// reads as prose. It exists for the Content Template's date placeholders,
/// where the whole vocabulary is fair game and nothing has to be read back.
///
/// Path Templates render the same syntax through ``PathFormat`` instead,
/// which supports only the handful of fixed-width numeric fields a path can
/// be matched back to a date from. See that type for why the two are not one.
///
/// Parsing never fails. A pattern that makes no sense simply renders as text,
/// which is what Moment does and what keeps a hand-typed setting from
/// breaking an Entry's content. The fields understood are the cases of
/// ``MomentFormat/Field``; ordinal suffixes (`Do` → `1st`) follow English
/// rules, matching Moment's default locale — which is what Obsidian ships.
public struct MomentFormat: Hashable, Sendable, CustomStringConvertible {
    /// The pattern as the user wrote it.
    public let pattern: String

    private let segments: [Segment]

    /// Parses a pattern. Never fails — see the type's discussion.
    public init(_ pattern: String) {
        self.pattern = pattern
        self.segments = MomentFormat.parse(pattern)
    }

    /// Renders an instant against this pattern.
    ///
    /// The instant is read as wall-clock time in `timeZone`; `locale` picks
    /// month and weekday names and decides where the locale week starts.
    public func render(
        _ date: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        var rendered = ""
        var reading: Reading?
        for segment in segments {
            switch segment {
            case .literal(let text):
                rendered += text
            case .field(let field):
                // Built on first use, so a pattern of pure literal text costs
                // no calendar work at all.
                let resolved = reading ?? Reading(date: date, timeZone: timeZone, locale: locale)
                reading = resolved
                rendered += resolved.value(for: field)
            }
        }
        return rendered
    }

    public var description: String { pattern }
}

// MARK: - The field vocabulary

extension MomentFormat {
    /// Every Moment field this engine understands, spelled as Moment spells it.
    ///
    /// This enum is the single source of the vocabulary: the parser matches
    /// against `allCases`, and `Reading.value(for:)` switches over it
    /// exhaustively, so a field can never be recognised without also being
    /// renderable.
    enum Field: String, CaseIterable, Hashable, Sendable {
        case year4 = "YYYY"
        case year2 = "YY"

        case quarter = "Q"
        case quarterOrdinal = "Qo"

        case monthName = "MMMM"
        case monthAbbreviation = "MMM"
        case monthPadded = "MM"
        case monthOrdinal = "Mo"
        case month = "M"

        case dayOfYearPadded = "DDDD"
        case dayOfYearOrdinal = "DDDo"
        case dayOfYear = "DDD"
        case dayPadded = "DD"
        case dayOrdinal = "Do"
        case day = "D"

        case weekdayName = "dddd"
        case weekdayAbbreviation = "ddd"
        case weekdayMinimal = "dd"
        case weekdayOrdinal = "do"
        case weekday = "d"
        case weekdayInLocaleWeek = "e"
        case weekdayISO = "E"

        case weekPadded = "ww"
        case weekOrdinal = "wo"
        case week = "w"
        case isoWeekPadded = "WW"
        case isoWeekOrdinal = "Wo"
        case isoWeek = "W"

        case weekYear4 = "gggg"
        case weekYear2 = "gg"
        case isoWeekYear4 = "GGGG"
        case isoWeekYear2 = "GG"

        case hourPadded = "HH"
        case hour = "H"
        case hour12Padded = "hh"
        case hour12 = "h"
        case hourFrom1Padded = "kk"
        case hourFrom1 = "k"

        case minutePadded = "mm"
        case minute = "m"
        case secondPadded = "ss"
        case second = "s"
        case millisecond = "SSS"
        case centisecond = "SS"
        case decisecond = "S"

        case meridiemUppercased = "A"
        case meridiemLowercased = "a"

        case utcOffsetWithColon = "Z"
        case utcOffset = "ZZ"

        case unixSeconds = "X"
        case unixMilliseconds = "x"

        /// Longest first, which is the whole matching rule: `MMMM` is
        /// preferred over `MMM` over `MM` over `M`.
        static let byDescendingLength: [Field] =
            allCases.sorted { $0.rawValue.count > $1.rawValue.count }
    }
}

// MARK: - Parsing

extension MomentFormat {
    fileprivate enum Segment: Hashable, Sendable {
        case literal(String)
        case field(Field)
    }

    private static func parse(_ pattern: String) -> [Segment] {
        let characters = Array(pattern)
        var segments: [Segment] = []
        var literal = ""
        var index = 0

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            segments.append(.literal(literal))
            literal = ""
        }

        while index < characters.count {
            let character = characters[index]

            // `[literal]` — Moment's escape hatch. An unclosed bracket is just
            // a bracket, so a half-typed pattern still renders.
            if character == "[", let close = characters[(index + 1)...].firstIndex(of: "]") {
                literal += String(characters[(index + 1)..<close])
                index = close + 1
                continue
            }

            if character == "\\", index + 1 < characters.count {
                literal.append(characters[index + 1])
                index += 2
                continue
            }

            if let field = matchField(characters, at: index) {
                flushLiteral()
                segments.append(.field(field))
                index += field.rawValue.count
                continue
            }

            literal.append(character)
            index += 1
        }

        flushLiteral()
        return segments
    }

    private static func matchField(_ characters: [Character], at index: Int) -> Field? {
        for field in Field.byDescendingLength
        where index + field.rawValue.count <= characters.count {
            if characters[index..<(index + field.rawValue.count)].elementsEqual(field.rawValue) {
                return field
            }
        }
        return nil
    }
}

// MARK: - Rendering

/// Every calendar reading a pattern could need, resolved once per render.
private struct Reading {
    private let date: Date
    private let timeZone: TimeZone
    private let locale: Locale
    private let components: DateComponents
    private let isoComponents: DateComponents
    private let dayOfYear: Int
    private let firstWeekday: Int
    private let symbols: DateFormatter

    init(date: Date, timeZone: TimeZone, locale: Locale) {
        self.date = date
        self.timeZone = timeZone
        self.locale = locale

        // Moment's `w`/`gggg` count weeks the locale's way; its `W`/`GGGG` are
        // always ISO. Two calendars, because that is genuinely two questions.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let localeCalendar = locale.calendar
        calendar.firstWeekday = localeCalendar.firstWeekday
        calendar.minimumDaysInFirstWeek = localeCalendar.minimumDaysInFirstWeek
        self.firstWeekday = localeCalendar.firstWeekday

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone

        let wanted: Set<Calendar.Component> = [
            .year, .month, .day, .hour, .minute, .second, .nanosecond,
            .weekday, .weekOfYear, .yearForWeekOfYear,
        ]
        self.components = calendar.dateComponents(wanted, from: date)
        self.isoComponents = iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        // `DateComponents.dayOfYear` needs macOS 15; ordinality is as old as
        // the deployment targets we care about and says the same thing.
        self.dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        self.symbols = formatter
    }

    func value(for field: MomentFormat.Field) -> String {
        switch field {
        case .year4: return pad(year, 4)
        case .year2: return pad(abs(year) % 100, 2)

        case .quarter: return String(quarter)
        case .quarterOrdinal: return ordinal(quarter)

        case .monthName: return symbols.monthSymbols[month - 1]
        case .monthAbbreviation: return symbols.shortMonthSymbols[month - 1]
        case .monthPadded: return pad(month, 2)
        case .monthOrdinal: return ordinal(month)
        case .month: return String(month)

        case .dayOfYearPadded: return pad(dayOfYear, 3)
        case .dayOfYearOrdinal: return ordinal(dayOfYear)
        case .dayOfYear: return String(dayOfYear)
        case .dayPadded: return pad(day, 2)
        case .dayOrdinal: return ordinal(day)
        case .day: return String(day)

        case .weekdayName: return symbols.weekdaySymbols[weekdayIndex]
        case .weekdayAbbreviation: return symbols.shortWeekdaySymbols[weekdayIndex]
        // Moment's two-letter weekday has no Foundation equivalent; the short
        // name's first two characters is the same answer in every locale we
        // ship ("Sun" → "Su", "dim." → "di").
        case .weekdayMinimal: return String(symbols.shortWeekdaySymbols[weekdayIndex].prefix(2))
        case .weekdayOrdinal: return ordinal(weekdayIndex)
        case .weekday: return String(weekdayIndex)
        case .weekdayInLocaleWeek: return String((weekdayIndex - (firstWeekday - 1) + 7) % 7)
        case .weekdayISO: return String(((weekdayIndex + 6) % 7) + 1)

        case .weekPadded: return pad(weekOfYear, 2)
        case .weekOrdinal: return ordinal(weekOfYear)
        case .week: return String(weekOfYear)
        case .isoWeekPadded: return pad(isoWeekOfYear, 2)
        case .isoWeekOrdinal: return ordinal(isoWeekOfYear)
        case .isoWeek: return String(isoWeekOfYear)

        case .weekYear4: return pad(weekYear, 4)
        case .weekYear2: return pad(abs(weekYear) % 100, 2)
        case .isoWeekYear4: return pad(isoWeekYear, 4)
        case .isoWeekYear2: return pad(abs(isoWeekYear) % 100, 2)

        case .hourPadded: return pad(hour, 2)
        case .hour: return String(hour)
        case .hour12Padded: return pad(hour12, 2)
        case .hour12: return String(hour12)
        case .hourFrom1Padded: return pad(hourFrom1, 2)
        case .hourFrom1: return String(hourFrom1)

        case .minutePadded: return pad(minute, 2)
        case .minute: return String(minute)
        case .secondPadded: return pad(second, 2)
        case .second: return String(second)
        case .millisecond: return pad(millisecond, 3)
        case .centisecond: return pad(millisecond / 10, 2)
        case .decisecond: return String(millisecond / 100)

        case .meridiemUppercased: return meridiem.uppercased(with: locale)
        case .meridiemLowercased: return meridiem.lowercased(with: locale)

        case .utcOffsetWithColon: return utcOffset(separator: ":")
        case .utcOffset: return utcOffset(separator: "")

        case .unixSeconds: return String(Int(date.timeIntervalSince1970.rounded(.down)))
        case .unixMilliseconds: return String(Int((date.timeIntervalSince1970 * 1000).rounded(.down)))
        }
    }

    private var year: Int { components.year ?? 0 }
    private var month: Int { components.month ?? 1 }
    private var day: Int { components.day ?? 1 }
    private var quarter: Int { (month - 1) / 3 + 1 }
    /// Moment numbers weekdays from 0 = Sunday; Foundation numbers from 1.
    private var weekdayIndex: Int { (components.weekday ?? 1) - 1 }
    private var weekOfYear: Int { components.weekOfYear ?? 1 }
    private var weekYear: Int { components.yearForWeekOfYear ?? year }
    private var isoWeekOfYear: Int { isoComponents.weekOfYear ?? 1 }
    private var isoWeekYear: Int { isoComponents.yearForWeekOfYear ?? year }
    private var hour: Int { components.hour ?? 0 }
    private var minute: Int { components.minute ?? 0 }
    private var second: Int { components.second ?? 0 }
    private var millisecond: Int { (components.nanosecond ?? 0) / 1_000_000 }
    private var hour12: Int { hour % 12 == 0 ? 12 : hour % 12 }
    /// Moment's `k` is the 1-24 clock: midnight is hour 24 of the day before.
    private var hourFrom1: Int { hour == 0 ? 24 : hour }
    private var meridiem: String { hour < 12 ? symbols.amSymbol : symbols.pmSymbol }

    private func utcOffset(separator: String) -> String {
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(sign)\(pad(minutes / 60, 2))\(separator)\(pad(minutes % 60, 2))"
    }

    private func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let padding = String(repeating: "0", count: max(0, width - digits.count))
        return (value < 0 ? "-" : "") + padding + digits
    }

    /// English ordinal suffixes, matching Moment's default locale.
    private func ordinal(_ value: Int) -> String {
        let suffix: String
        switch (value % 100, value % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(value)\(suffix)"
    }
}
