import Foundation

/// The markdown skeleton a new Entry starts from.
///
/// A Content Template is plain markdown sprinkled with Obsidian-syntax
/// `{{name}}` / `{{name:FORMAT}}` placeholders. `render(at:)` turns it into an
/// Entry's starting content at spawn:
///
/// - **Core placeholders** — `{{date}}`, `{{time}}`, `{{title}}` (plus
///   Obsidian's `{{yesterday}}` and `{{tomorrow}}`) resolve to text, exactly
///   as Obsidian's daily-notes templates do, so an existing template pastes
///   over unchanged.
/// - **Interactive placeholders** — the names in
///   ``SpawnContext/interactivePlaceholders`` pass through as the literal text
///   the user wrote. The editor owns them from there; until one is answered it
///   is harmless literal text in Obsidian too.
/// - **Anything else** renders empty, per the v1 decision that an unrecognised
///   placeholder leaves no debris in the file.
///
/// Rendering cannot fail. Braces that do not parse as a placeholder — unclosed,
/// empty, or malformed — are ordinary text and are copied through verbatim.
public struct ContentTemplate: Hashable, Sendable {
    /// The template as the user wrote it.
    public let source: String

    private let segments: [Segment]

    public init(_ source: String) {
        self.source = source
        self.segments = ContentTemplate.parse(source)
    }

    /// The Entry's starting content.
    public func render(at spawn: SpawnContext) -> String {
        var rendered = ""
        for segment in segments {
            switch segment {
            case .literal(let text):
                rendered += text
            case .placeholder(let placeholder):
                rendered += spawn.resolve(placeholder)
            }
        }
        return rendered
    }
}

// MARK: - The spawn context

/// Everything resolving a Content Template needs to know about the Entry being
/// spawned and the moment it is being spawned at.
///
/// The two are deliberately separate: `day` is the Entry's Journal Day, which
/// on a backfill is not today, while `instant` is the wall clock right now.
public struct SpawnContext: Sendable {
    /// The Journal Day the new Entry belongs to.
    public var day: JournalDay
    /// The wall-clock moment of the spawn.
    public var instant: Date
    /// The Entry's title — its filename without the `.md` extension.
    public var title: String
    public var timeZone: TimeZone
    public var locale: Locale
    /// The format bare `{{date}}` renders in. Obsidian uses the daily-note
    /// filename format here, so this tracks the Journal's Path Template.
    public var dateFormat: MomentFormat
    /// Names that pass through as literal text for the editor to own.
    public var interactivePlaceholders: Set<String>

    public init(
        day: JournalDay,
        instant: Date,
        title: String,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        dateFormat: MomentFormat = MomentFormat("YYYY-MM-DD"),
        interactivePlaceholders: Set<String> = InteractivePlaceholder.registeredNames
    ) {
        self.day = day
        self.instant = instant
        self.title = title
        self.timeZone = timeZone
        self.locale = locale
        self.dateFormat = dateFormat
        self.interactivePlaceholders = interactivePlaceholders
    }
}

/// The placeholders Aujour renders as inline widgets in the editor, and which
/// therefore survive a spawn as literal `{{name}}` text.
public enum InteractivePlaceholder: String, CaseIterable, Sendable {
    case mood
    case location

    public static let registeredNames: Set<String> = Set(allCases.map(\.rawValue))
}

// MARK: - Resolution

extension SpawnContext {
    /// Obsidian's bare `{{time}}` is hard-coded to this format, so ours is too.
    private static let defaultTimeFormat = MomentFormat("HH:mm")

    fileprivate func resolve(_ placeholder: ContentTemplate.Placeholder) -> String {
        switch placeholder.name {
        case "date":
            return format(placeholder, default: dateFormat, extraDays: 0)
        case "time":
            return format(placeholder, default: SpawnContext.defaultTimeFormat, extraDays: 0)
        case "yesterday":
            return format(placeholder, default: dateFormat, extraDays: -1)
        case "tomorrow":
            return format(placeholder, default: dateFormat, extraDays: 1)
        case "title":
            return title
        case let name where interactivePlaceholders.contains(name):
            return placeholder.raw
        default:
            return ""
        }
    }

    private func format(
        _ placeholder: ContentTemplate.Placeholder,
        default fallback: MomentFormat,
        extraDays: Int
    ) -> String {
        var moment = anchor
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if extraDays != 0 {
            moment = calendar.date(byAdding: .day, value: extraDays, to: moment) ?? moment
        }
        if let offset = placeholder.offset {
            moment = calendar.date(byAdding: offset.component, value: offset.amount, to: moment)
                ?? moment
        }

        let format = placeholder.format.map(MomentFormat.init) ?? fallback
        return format.render(moment, timeZone: timeZone, locale: locale)
    }

    /// The moment every date placeholder is measured from: the Entry's Journal
    /// Day carrying the current time of day. That combination is Obsidian's —
    /// it is why `{{date:HH:mm}}` reads as a live clock rather than midnight —
    /// and it collapses to plain "now" for today's Entry, the common case.
    private var anchor: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let clock = calendar.dateComponents([.hour, .minute, .second], from: instant)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = clock.second
        // Nil only if the wall-clock time does not exist on that date — a
        // spring-forward gap. Falling back to the spawn instant keeps a
        // template rendering rather than trapping.
        return calendar.date(from: components) ?? instant
    }
}

// MARK: - Parsing

extension ContentTemplate {
    fileprivate enum Segment: Hashable, Sendable {
        case literal(String)
        case placeholder(Placeholder)
    }

    /// A parsed `{{name±Nunit:FORMAT}}` token.
    fileprivate struct Placeholder: Hashable, Sendable {
        /// Lower-cased, because Obsidian matches placeholder names that way.
        let name: String
        let offset: Offset?
        /// The text after `:`, trimmed — `nil` when the placeholder had none.
        let format: String?
        /// The token exactly as written, for interactive pass-through.
        let raw: String
    }

    fileprivate struct Offset: Hashable, Sendable {
        let amount: Int
        let component: Calendar.Component

        /// Obsidian accepts a single-letter Moment unit. Case matters here and
        /// nowhere else in the syntax: `M` is months, `m` is minutes.
        init?(amount: Int, unit: Character) {
            // Quarters count as three months: Foundation's `.quarter` is not
            // reliably additive, and three months is what Moment means anyway.
            var scale = 1
            switch unit {
            case "y", "Y": component = .year
            case "Q", "q": component = .month; scale = 3
            case "M": component = .month
            case "w", "W": component = .weekOfYear
            case "d", "D": component = .day
            case "h", "H": component = .hour
            case "m": component = .minute
            case "s", "S": component = .second
            default: return nil
            }
            self.amount = amount * scale
        }
    }

    private static func parse(_ source: String) -> [Segment] {
        let characters = Array(source)
        var segments: [Segment] = []
        var literal = ""
        var index = 0

        while index < characters.count {
            guard characters[index] == "{",
                  index + 1 < characters.count, characters[index + 1] == "{",
                  let match = parsePlaceholder(characters, from: index)
            else {
                literal.append(characters[index])
                index += 1
                continue
            }

            if !literal.isEmpty {
                segments.append(.literal(literal))
                literal = ""
            }
            segments.append(.placeholder(match.placeholder))
            index = match.end
        }

        if !literal.isEmpty {
            segments.append(.literal(literal))
        }
        return segments
    }

    /// Parses one placeholder starting at the `{{` at `start`.
    ///
    /// Returns `nil` for anything that is not a well-formed placeholder, and
    /// the caller then treats the `{` as ordinary text and retries one
    /// character later — so `{{{date}}` still finds the placeholder inside,
    /// which is what Obsidian's scanning regex does.
    private static func parsePlaceholder(
        _ characters: [Character],
        from start: Int
    ) -> (placeholder: Placeholder, end: Int)? {
        var index = start + 2

        func skipSpaces() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }

        skipSpaces()

        let nameStart = index
        while index < characters.count, isNameCharacter(characters[index]) { index += 1 }
        guard index > nameStart else { return nil }
        let name = String(characters[nameStart..<index]).lowercased()

        skipSpaces()

        var offset: Offset?
        if index < characters.count, characters[index] == "+" || characters[index] == "-" {
            let negative = characters[index] == "-"
            index += 1
            let digitsStart = index
            while index < characters.count, characters[index].isNumber { index += 1 }
            guard index > digitsStart,
                  let magnitude = Int(String(characters[digitsStart..<index])),
                  index < characters.count,
                  let parsed = Offset(amount: negative ? -magnitude : magnitude, unit: characters[index])
            else { return nil }
            offset = parsed
            index += 1
            skipSpaces()
        }

        var format: String?
        if index < characters.count, characters[index] == ":" {
            index += 1
            guard let close = closingBraces(characters, from: index) else { return nil }
            format = String(characters[index..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            index = close
        }

        guard index + 1 < characters.count,
              characters[index] == "}", characters[index + 1] == "}"
        else { return nil }

        let end = index + 2
        return (
            Placeholder(
                name: name,
                offset: offset,
                format: format,
                raw: String(characters[start..<end])
            ),
            end
        )
    }

    /// A hyphen is deliberately not a name character: it is how an offset
    /// starts, and `{{date-1d}}` has to read as "date, minus one day".
    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func closingBraces(_ characters: [Character], from index: Int) -> Int? {
        var cursor = index
        while cursor + 1 < characters.count {
            if characters[cursor] == "}", characters[cursor + 1] == "}" { return cursor }
            cursor += 1
        }
        return nil
    }
}
