import Foundation

/// The restricted Moment-format engine both Path Templates are built on.
///
/// Moment's full token vocabulary is far larger than this, but most of it is
/// ambiguous to read back: `MMMM` is a localized month name, `D` an unpadded
/// day whose width depends on the date. Aujour supports exactly the tokens
/// that render to a fixed number of digits — `YYYY`, `MM`, `DD` — plus
/// `[bracketed]` literals. That restriction is what makes matching a path
/// back to a date a plain left-to-right scan with no guessing, which in turn
/// is what lets Entry identity be "the path the template renders" (ADR 0002).
///
/// ``MomentFormat`` renders the same syntax for Content Template
/// placeholders, and the two deliberately stay apart. Being invertible is
/// what shapes this one: it reads tokens as runs of a single letter so a
/// typo is refused by name rather than half-understood, it formats dates
/// arithmetically so the round trip holds either side of the 1582 Gregorian
/// cutover that `Calendar` observes, and it throws where a placeholder would
/// shrug. A placeholder needs none of that and needs `Do` and `MMMM`, which
/// no path may contain.
enum PathFormat {
    /// One piece of a parsed template: text that is copied through verbatim,
    /// or a number taken from the Journal Day.
    enum Element: Hashable, Sendable {
        case literal(String)
        case field(Field)
    }

    /// A supported token. Every field is zero-padded to a constant width, so
    /// a rendered path can be read back without delimiters to guide it.
    enum Field: String, Hashable, Sendable, CaseIterable {
        case year = "YYYY"
        case month = "MM"
        case day = "DD"

        var width: Int {
            switch self {
            case .year: 4
            case .month, .day: 2
            }
        }

        func value(of journalDay: JournalDay) -> Int {
            switch self {
            case .year: journalDay.year
            case .month: journalDay.month
            case .day: journalDay.day
            }
        }
    }

    /// Splits a format string into elements, rejecting anything outside the
    /// supported subset.
    ///
    /// Letters are token material and are read as maximal runs of the same
    /// character, the way Moment tokenizes: `YYYYMM` is two tokens, while
    /// `YYYYY` is one unsupported five-character token rather than a token
    /// plus a stray letter. Everything else — digits, `-`, `_`, `/`, spaces,
    /// accented letters — is literal, so `YYYY-MM-DD` needs no brackets.
    static func parse(_ format: String) throws(PathTemplateError) -> [Element] {
        guard !format.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PathTemplateError.emptyFormat
        }

        var elements: [Element] = []
        var literal = ""
        func flushLiteral() {
            if !literal.isEmpty {
                elements.append(.literal(literal))
                literal = ""
            }
        }

        var remainder = Substring(format)
        while let character = remainder.first {
            if character == "[" {
                remainder = remainder.dropFirst()
                guard let close = remainder.firstIndex(of: "]") else {
                    throw PathTemplateError.unterminatedLiteral
                }
                literal += remainder[..<close]
                remainder = remainder[close...].dropFirst()
            } else if character.isTokenLetter {
                let token = remainder.prefix { $0 == character }
                remainder = remainder.dropFirst(token.count)
                guard let field = Field(rawValue: String(token)) else {
                    throw PathTemplateError.unsupportedToken(String(token))
                }
                flushLiteral()
                elements.append(.field(field))
            } else {
                literal.append(character)
                remainder = remainder.dropFirst()
            }
        }
        flushLiteral()

        return elements
    }

    /// The path a Journal Day renders to — no extension; each Path Template
    /// decides what, if anything, to append.
    static func render(_ elements: [Element], for journalDay: JournalDay) -> String {
        elements.reduce(into: "") { path, element in
            switch element {
            case .literal(let text):
                path += text
            case .field(let field):
                path += String(format: "%0\(field.width)d", field.value(of: journalDay))
            }
        }
    }

    /// A day whose rendering shows the shape of every day's rendering.
    ///
    /// Fields have constant widths and literals never vary, so how many path
    /// components a template produces — and which of them are pure literal —
    /// is the same for every day. One sample answers structural questions
    /// about all of them.
    static let shapeSample = JournalDay(year: 2026, month: 3, day: 1)

    /// The structural rules a path has to obey whatever it addresses: no
    /// empty folder or file names, and no `.` or `..` hops.
    static func validatePathShape(_ elements: [Element]) throws(PathTemplateError) {
        let components = render(elements, for: shapeSample)
            .split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            guard !component.isEmpty else { throw PathTemplateError.emptyPathComponent }
            guard component != "." && component != ".." else {
                throw PathTemplateError.relativePathComponent(String(component))
            }
        }
    }

    /// The Journal Day these elements render to `path` for, or `nil` if no day
    /// does — the exact inverse of `render`.
    ///
    /// Because every field has a fixed width, this is a single left-to-right
    /// scan with nothing to backtrack over. `nil` is the answer for anything
    /// that is not a rendering of the template: leftover characters, a
    /// mismatched literal, repeated tokens that disagree (a March folder
    /// holding an April filename), or a date that never existed.
    static func match(_ path: Substring, against elements: [Element]) -> JournalDay? {
        var values: [Field: Int] = [:]
        var cursor = path.startIndex

        for element in elements {
            switch element {
            case .literal(let text):
                guard path[cursor...].hasPrefix(text) else { return nil }
                cursor = path.index(cursor, offsetBy: text.count)
            case .field(let field):
                guard
                    let fieldEnd = path.index(
                        cursor, offsetBy: field.width, limitedBy: path.endIndex
                    )
                else { return nil }
                let digits = path[cursor..<fieldEnd]
                guard digits.allSatisfy(\.isASCIIDigit), let value = Int(digits) else {
                    return nil
                }
                // A template may name the same field twice — the default one
                // does, as folder and filename. Every occurrence has to agree.
                guard values[field] == nil || values[field] == value else { return nil }
                values[field] = value
                cursor = fieldEnd
            }
        }

        guard cursor == path.endIndex else { return nil }
        guard
            let year = values[.year], let month = values[.month], let day = values[.day],
            isRealDate(year: year, month: month, day: day)
        else { return nil }

        return JournalDay(year: year, month: month, day: day)
    }

    /// Whether a year/month/day triple names a day that exists.
    ///
    /// Done by hand rather than through `Calendar`, which switches to the
    /// Julian calendar before October 1582 and would disagree with what
    /// `render` writes for those years.
    private static func isRealDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...lengths[month - 1]).contains(day)
    }
}

extension Character {
    /// Only ASCII letters form tokens. Moment would treat `é` as a token
    /// character too, but nothing in the supported subset uses one, and a
    /// user with an accented folder name should not have to bracket it.
    fileprivate var isTokenLetter: Bool {
        isASCII && isLetter
    }

    /// `isNumber` is true of Arabic-Indic and other non-ASCII digits, which
    /// `Int(_:)` happily parses. A path spelled with them is not a path this
    /// engine ever rendered, so it is not an Entry.
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
