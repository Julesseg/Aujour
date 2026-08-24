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
/// - **Data placeholders** — ``DataPlaceholder``'s names resolve to whatever
///   the day's ``DayData`` made of them, which `render(at:reading:)` reads
///   before rendering. Left to the plain `render(at:)`, they render empty like
///   any other name Aujour cannot answer.
/// - **Interactive placeholders** — the names in
///   ``SpawnContext/interactivePlaceholders`` pass through as the literal text
///   the user wrote, `{{mood}}` and `{{mood:FORMAT}}` alike. The editor owns
///   them from there; until one is answered it is harmless literal text in
///   Obsidian too. An offset is the one shape that does not pass through,
///   because it is not one the editor will ever stand a widget over.
/// - **Anything else** renders empty, per the v1 decision that an unrecognised
///   placeholder leaves no debris in the file.
///
/// Rendering cannot fail. Braces that do not parse as a placeholder — unclosed,
/// empty, or malformed — are ordinary text and are copied through verbatim.
public struct ContentTemplate: Hashable, Sendable {
    /// The template as the user wrote it.
    public let source: String

    private let segments: [Segment]

    /// Parses a template. Never fails — see the type's discussion.
    public init(_ source: String) {
        self.source = source
        self.segments = ContentTemplate.parse(source)
    }

    /// The Entry's starting content, from what the spawn already knows.
    ///
    /// Nothing is read from the device here, so a data placeholder renders
    /// whatever ``SpawnContext/data`` holds for it — which is nothing, unless
    /// `render(at:reading:)` filled it in first.
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

// MARK: - Reading the day's data

extension ContentTemplate {
    /// The Entry's starting content, with the day's data read into it first.
    ///
    /// Only the placeholders this template actually names are read, so a
    /// template that never mentions the calendar costs nothing to spawn — and
    /// the ones it does name are read at the same time as each other, because
    /// waiting for the reminders after the events is waiting twice for an
    /// Entry that has to be on screen.
    ///
    /// Cannot fail and cannot come back empty-handed: a source with nothing to
    /// say — no permission, no items, no source at all — is a placeholder that
    /// renders per its formatting, and the rest of the template is untouched
    /// either way.
    public func render(at spawn: SpawnContext, reading data: DayData) async -> String {
        let placeholders = dataPlaceholders
        guard !placeholders.isEmpty else { return render(at: spawn) }

        var resolved = spawn
        await withTaskGroup(of: (DataPlaceholder, String).self) { group in
            for placeholder in placeholders {
                // The context the reads are *about*, captured before the one
                // they are being written back into starts changing.
                group.addTask { (placeholder, await data.text(for: placeholder, at: spawn)) }
            }
            for await (placeholder, text) in group { resolved.data[placeholder] = text }
        }
        return render(at: resolved)
    }

    /// The data placeholders this template names — which is exactly what a
    /// spawn has to go and read, and nothing more.
    ///
    /// Only the bare ones. `{{events:FORMAT}}` is not a placeholder at all by
    /// the rule ``SpawnContext`` resolves by, so reading a calendar for it
    /// would be reading a calendar for a piece of text.
    public var dataPlaceholders: Set<DataPlaceholder> {
        var named: Set<DataPlaceholder> = []
        for segment in segments {
            guard case .placeholder(let placeholder) = segment, placeholder.isBare,
                let name = DataPlaceholder(rawValue: placeholder.name)
            else { continue }
            named.insert(name)
        }
        return named
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
    /// The zone the Entry's wall-clock day and time are read in.
    public var timeZone: TimeZone
    /// Picks month and weekday names, and where the locale week starts.
    public var locale: Locale
    /// The format bare `{{date}}` renders in. Obsidian uses the daily-note
    /// filename format here, so this tracks the Journal's Path Template.
    public var dateFormat: MomentFormat
    /// Names that pass through as literal text for the editor to own.
    public var interactivePlaceholders: Set<String>
    /// How each data placeholder's items are written into the Entry.
    public var dataFormatting: DataPlaceholderFormatting
    /// What each data placeholder renders as, already read from the day's
    /// data and already formatted.
    ///
    /// Resolved before rendering rather than during it, because reading a
    /// calendar takes waiting and putting a template together does not. A
    /// name missing from here renders empty — which is what a build with no
    /// sources installed, and a spawn that never went looking, both come to.
    public var data: [DataPlaceholder: String]

    /// Defaults describe a spawn on the current device with Obsidian's own
    /// default date format and the interactive placeholders v1 registers.
    public init(
        day: JournalDay,
        instant: Date,
        title: String,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        dateFormat: MomentFormat = MomentFormat("YYYY-MM-DD"),
        interactivePlaceholders: Set<String> = InteractivePlaceholder.registeredNames,
        dataFormatting: DataPlaceholderFormatting = .default,
        data: [DataPlaceholder: String] = [:]
    ) {
        self.day = day
        self.instant = instant
        self.title = title
        self.timeZone = timeZone
        self.locale = locale
        self.dateFormat = dateFormat
        self.interactivePlaceholders = interactivePlaceholders
        self.dataFormatting = dataFormatting
        self.data = data
    }
}

// MARK: - Resolution

extension SpawnContext {
    /// Obsidian's bare `{{time}}` is hard-coded to this format, so ours is too.
    private static let defaultTimeFormat = MomentFormat("HH:mm")

    /// Resolves one placeholder, mirroring the order Obsidian substitutes in.
    ///
    /// Obsidian replaces the bare `{{date}}`, `{{time}}`, `{{title}}`,
    /// `{{yesterday}}` and `{{tomorrow}}` outright, and only then runs a
    /// pattern that accepts an offset or a `:FORMAT` — and that pattern
    /// recognises `date` and `time` alone. So a format or offset on any other
    /// name is not a placeholder at all, and falls through to the
    /// unknown-renders-empty rule.
    fileprivate func resolve(_ placeholder: ContentTemplate.Placeholder) -> String {
        switch placeholder.name {
        case "date" where placeholder.isBare:
            return render(dateFormat, at: day.startOfDay(in: timeZone))
        case "time" where placeholder.isBare:
            return render(SpawnContext.defaultTimeFormat, at: instant)
        case "yesterday" where placeholder.isBare:
            return render(dateFormat, at: day.adding(days: -1).startOfDay(in: timeZone))
        case "tomorrow" where placeholder.isBare:
            return render(dateFormat, at: day.adding(days: 1).startOfDay(in: timeZone))
        case "title" where placeholder.isBare:
            return title
        case "date", "time":
            return renderShifted(placeholder)
        // A name the user answers passes through as the literal text they
        // wrote, format and all — but only in the shapes the editor will find
        // again, which is what keeps a token that survives the spawn from being
        // one no widget ever stands over. An offset is not one of them.
        case let name
        where interactivePlaceholders.contains(name) && placeholder.offset == nil:
            return placeholder.raw
        default:
            // A data placeholder renders what the day's data made of it, and
            // every other name renders empty — including a data name carrying
            // an offset or a `:FORMAT`, which by the rule above is not a
            // placeholder at all.
            guard placeholder.isBare, let name = DataPlaceholder(rawValue: placeholder.name)
            else { return "" }
            return data[name] ?? ""
        }
    }

    /// `{{date±Nunit}}` / `{{date:FORMAT}}` and their `time` twins.
    private func renderShifted(_ placeholder: ContentTemplate.Placeholder) -> String {
        // Obsidian measures these from the Entry's day carrying the current
        // time of day, which is why `{{date:HH:mm}}` reads as a live clock
        // rather than midnight. For today's Entry it collapses to plain "now".
        var moment = day.date(atClockTimeOf: instant, in: timeZone)

        if let offset = placeholder.offset {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            moment = calendar.date(byAdding: offset.component, value: offset.amount, to: moment)
                ?? moment
        }

        // A deliberate divergence: Obsidian falls back to the *date* format
        // here even for `{{time}}`, so `{{time+1h}}` renders a date there. A
        // time placeholder resolving to a date is an upstream bug, and no
        // template is written to depend on it — each placeholder keeps its own
        // default instead.
        return render(placeholder.format ?? defaultFormat(for: placeholder.name), at: moment)
    }

    private func render(_ format: MomentFormat, at moment: Date) -> String {
        format.render(moment, timeZone: timeZone, locale: locale)
    }

    /// What a placeholder renders in when it carries no `:FORMAT` of its own.
    private func defaultFormat(for name: String) -> MomentFormat {
        name == "time" ? SpawnContext.defaultTimeFormat : dateFormat
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
        /// The pattern after `:`, parsed once here rather than per render.
        let format: MomentFormat?
        /// The token exactly as written, for interactive pass-through.
        let raw: String

        /// A placeholder carrying neither an offset nor a format — the only
        /// shape Obsidian accepts for names other than `date` and `time`.
        var isBare: Bool { offset == nil && format == nil }
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
            while index < characters.count, PlaceholderSyntax.isSpace(characters[index]) {
                index += 1
            }
        }

        skipSpaces()

        let nameStart = index
        while index < characters.count, PlaceholderSyntax.isNameCharacter(characters[index]) {
            index += 1
        }
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

        var format: MomentFormat?
        if index < characters.count, characters[index] == ":" {
            index += 1
            guard let close = closingBraces(characters, from: index) else { return nil }
            let pattern = String(characters[index..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            format = MomentFormat(pattern)
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

    /// Shared with the editor's own scan, so a token the spawn passes through
    /// is one the editor closes in the same place — which is what keeps a
    /// format holding braces of its own (`{value}`) readable by both.
    private static func closingBraces(_ characters: [Character], from index: Int) -> Int? {
        PlaceholderSyntax.closingBraces(in: characters[index...], open: "{", close: "}")
    }
}
