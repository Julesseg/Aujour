import Foundation

/// A Moment-format date pattern — the syntax Obsidian uses for daily-note
/// filenames and for `{{date:FORMAT}}` placeholders.
///
/// A pattern is a mix of *tokens* (`YYYY`, `MM`, `dddd`, `HH`, …) and literal
/// text. Anything that is not a token renders verbatim, and text wrapped in
/// `[brackets]` is literal even when it looks like a token — so
/// `[Week] W` reads as prose. This is the shared engine behind both the
/// Content Template's date placeholders and the Path Template.
///
/// Parsing never fails. A pattern that makes no sense simply renders as text,
/// which is what Moment does and what keeps a hand-typed setting from
/// breaking an Entry's content.
///
/// ## Supported tokens
///
/// | Kind | Tokens |
/// | --- | --- |
/// | Year | `YYYY` `YY` |
/// | Quarter | `Q` `Qo` |
/// | Month | `MMMM` `MMM` `MM` `Mo` `M` |
/// | Day of month | `DD` `Do` `D` |
/// | Day of year | `DDDD` `DDDo` `DDD` |
/// | Day of week | `dddd` `ddd` `dd` `do` `d` `e` `E` |
/// | Week of year | `ww` `wo` `w` (locale) `WW` `Wo` `W` (ISO) |
/// | Week year | `gggg` `gg` (locale) `GGGG` `GG` (ISO) |
/// | Hour | `HH` `H` `hh` `h` `kk` `k` |
/// | Minute / second | `mm` `m` `ss` `s` `SSS` `SS` `S` |
/// | Meridiem | `A` `a` |
/// | UTC offset | `Z` `ZZ` |
/// | Unix time | `X` `x` |
///
/// Ordinal suffixes (`Do` → `1st`) follow English rules, matching Moment's
/// default locale — which is what Obsidian ships with.
public struct MomentFormat: Hashable, Sendable, CustomStringConvertible {
    /// The pattern as the user wrote it.
    public let pattern: String

    private let tokens: [Token]

    public init(_ pattern: String) {
        self.pattern = pattern
        self.tokens = MomentFormat.parse(pattern)
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
        var fields: Fields?
        for token in tokens {
            switch token {
            case .literal(let text):
                rendered += text
            case .field(let field):
                // Built on first use, so a pattern of pure literal text costs
                // no calendar work at all.
                let resolved = fields ?? Fields(date: date, timeZone: timeZone, locale: locale)
                fields = resolved
                rendered += resolved.value(for: field)
            }
        }
        return rendered
    }

    public var description: String { pattern }
}

// MARK: - Parsing

extension MomentFormat {
    fileprivate enum Token: Hashable, Sendable {
        case literal(String)
        case field(String)
    }

    /// Every token this engine knows, longest first — the order is the
    /// matching rule, so `MMMM` is preferred over `MMM` over `MM` over `M`.
    private static let knownTokens: [String] = [
        "DDDD", "DDDo", "YYYY", "MMMM", "dddd", "gggg", "GGGG",
        "MMM", "DDD", "ddd", "SSS",
        "YY", "Qo", "MM", "Mo", "DD", "Do", "dd", "do",
        "wo", "ww", "Wo", "WW", "gg", "GG",
        "HH", "hh", "kk", "mm", "ss", "SS", "ZZ",
        "Q", "M", "D", "d", "e", "E", "w", "W",
        "H", "h", "k", "m", "s", "S", "A", "a", "Z", "X", "x",
    ]

    private static func parse(_ pattern: String) -> [Token] {
        let characters = Array(pattern)
        var tokens: [Token] = []
        var literal = ""
        var index = 0

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            tokens.append(.literal(literal))
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

            if let field = matchToken(characters, at: index) {
                flushLiteral()
                tokens.append(.field(field))
                index += field.count
                continue
            }

            literal.append(character)
            index += 1
        }

        flushLiteral()
        return tokens
    }

    private static func matchToken(_ characters: [Character], at index: Int) -> String? {
        for token in knownTokens where index + token.count <= characters.count {
            if characters[index..<(index + token.count)].elementsEqual(token) {
                return token
            }
        }
        return nil
    }
}

// MARK: - Rendering

/// Every calendar reading a pattern could need, resolved once per render.
private struct Fields {
    private let date: Date
    private let timeZone: TimeZone
    private let locale: Locale
    private let components: DateComponents
    private let isoComponents: DateComponents
    private let dayOfYear: Int
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

    func value(for token: String) -> String {
        switch token {
        case "YYYY": return pad(year, 4)
        case "YY": return pad(abs(year) % 100, 2)

        case "Q": return String(quarter)
        case "Qo": return ordinal(quarter)

        case "MMMM": return symbols.monthSymbols[month - 1]
        case "MMM": return symbols.shortMonthSymbols[month - 1]
        case "MM": return pad(month, 2)
        case "Mo": return ordinal(month)
        case "M": return String(month)

        case "DDDD": return pad(dayOfYear, 3)
        case "DDDo": return ordinal(dayOfYear)
        case "DDD": return String(dayOfYear)
        case "DD": return pad(day, 2)
        case "Do": return ordinal(day)
        case "D": return String(day)

        case "dddd": return symbols.weekdaySymbols[weekdayIndex]
        case "ddd": return symbols.shortWeekdaySymbols[weekdayIndex]
        // Moment's two-letter weekday has no Foundation equivalent; the short
        // name's first two characters is the same answer in every locale we
        // ship ("Sun" → "Su", "dim." → "di").
        case "dd": return String(symbols.shortWeekdaySymbols[weekdayIndex].prefix(2))
        case "do": return ordinal(weekdayIndex)
        case "d": return String(weekdayIndex)
        case "e": return String((weekdayIndex - (firstWeekday - 1) + 7) % 7)
        case "E": return String(((weekdayIndex + 6) % 7) + 1)

        case "ww": return pad(weekOfYear, 2)
        case "wo": return ordinal(weekOfYear)
        case "w": return String(weekOfYear)
        case "WW": return pad(isoWeekOfYear, 2)
        case "Wo": return ordinal(isoWeekOfYear)
        case "W": return String(isoWeekOfYear)

        case "gggg": return pad(weekYear, 4)
        case "gg": return pad(abs(weekYear) % 100, 2)
        case "GGGG": return pad(isoWeekYear, 4)
        case "GG": return pad(abs(isoWeekYear) % 100, 2)

        case "HH": return pad(hour, 2)
        case "H": return String(hour)
        case "hh": return pad(hour12, 2)
        case "h": return String(hour12)
        case "kk": return pad(hour24From1, 2)
        case "k": return String(hour24From1)

        case "mm": return pad(minute, 2)
        case "m": return String(minute)
        case "ss": return pad(second, 2)
        case "s": return String(second)
        case "SSS": return pad(millisecond, 3)
        case "SS": return pad(millisecond / 10, 2)
        case "S": return String(millisecond / 100)

        case "A": return meridiem.uppercased(with: locale)
        case "a": return meridiem.lowercased(with: locale)

        case "Z": return utcOffset(separator: ":")
        case "ZZ": return utcOffset(separator: "")

        case "X": return String(Int(date.timeIntervalSince1970.rounded(.down)))
        case "x": return String(Int((date.timeIntervalSince1970 * 1000).rounded(.down)))

        default: return token
        }
    }

    private var year: Int { components.year ?? 0 }
    private var month: Int { components.month ?? 1 }
    private var day: Int { components.day ?? 1 }
    private var quarter: Int { (month - 1) / 3 + 1 }
    /// Moment numbers weekdays from 0 = Sunday; Foundation numbers from 1.
    private var weekdayIndex: Int { (components.weekday ?? 1) - 1 }
    private var firstWeekday: Int { locale.calendar.firstWeekday }
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
    private var hour24From1: Int { hour == 0 ? 24 : hour }
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
