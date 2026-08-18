import Foundation

/// A `{{name}}` Aujour fills in from what the device already knows about the
/// Journal Day being written — the day's calendar events, the day's reminders.
///
/// Resolved once, at spawn, into plain markdown: what lands in the Entry is
/// text like any other, so the file is the same file in Obsidian and nothing
/// has to be resolved again to read it (ADR 0001). Which is also why the set
/// is closed — a name Aujour cannot answer is an unknown placeholder, and
/// unknown placeholders render empty.
public enum DataPlaceholder: String, CaseIterable, Hashable, Sendable {
    /// The day's calendar events.
    case events
    /// The day's reminders.
    case reminders
}

/// One thing a Journal Day held: a meeting, a reminder — whatever a
/// ``DayItemSource`` has to say about a day.
///
/// The same shape for both kinds, deliberately. What tells a calendar event
/// from a reminder is which placeholder asked, and that is already settled by
/// the time anything is being written; giving the two different shapes here
/// would only mean two ways of laying out a line of markdown.
public struct DayItem: Hashable, Sendable {
    /// What it is called.
    public var title: String

    /// Where in the day it sits, or `nil` for something the day holds without
    /// an hour — an all-day event, a reminder with a date and no time.
    public var time: Date?

    public init(title: String, time: Date? = nil) {
        self.title = title
        self.time = time
    }
}

/// Where one data placeholder's items come from.
///
/// The seam between the domain and the device: Core decides which stretch of
/// wall-clock time an Entry's day is and what its items read like in markdown,
/// and never learns whether the answers come from EventKit, from a fake, or
/// from nowhere at all.
///
/// Reading cannot fail, and that is the point of the signature. A source the
/// user has not granted access to has no items — which is not an error, it is
/// an answer — and a spawn that could throw would be an Entry that failed to
/// appear because a calendar was unreachable. Everything that goes wrong down
/// there arrives here as an empty day.
public protocol DayItemSource: Sendable {
    /// The items this source has for a stretch of the day.
    ///
    /// Answers, and answers promptly, whatever the state of the permission
    /// behind it: this is called with a day about to go on screen.
    func items(during day: DateInterval) async -> [DayItem]

    /// Asks for whatever this source needs before it can answer anything —
    /// the permission prompt, where there is one.
    ///
    /// Separate from reading, and that separation is the whole of "spawn never
    /// blocks": reading happens with an Entry about to be put in front of the
    /// user, and a spawn waiting on a system alert is a day that does not
    /// appear until somebody answers one. This is called somewhere there is
    /// time to wait — before the day is opened — and never during a spawn.
    ///
    /// Called more than once over a launch, so it has to be cheap the second
    /// time: a permission already decided is decided.
    func prepare() async
}

extension DayItemSource {
    /// Most sources need nothing asked for.
    public func prepare() async {}
}

// MARK: - How the items are laid into the Entry

/// How one data placeholder's items are written into an Entry.
///
/// A Journal Setting, because it shapes what goes into the files: two devices
/// spawning the same template must write the same day the same way (ADR 0003).
public struct DataPlaceholderFormat: Hashable, Sendable {
    /// What every item's line starts with. A markdown list marker by default,
    /// so the placeholder's stretch of the Entry is a list in Aujour and a
    /// list in Obsidian.
    public var linePrefix: String

    /// The format an item's time is written in, before its title — or `nil`
    /// to leave times out, for somebody who wants the day's shape without its
    /// timetable.
    ///
    /// An item that has no time of its own renders without one either way,
    /// and without the space that would have followed it: an all-day event
    /// does not start its line with a gap where a clock would have been.
    public var timeFormat: MomentFormat?

    /// What the placeholder renders as on a day that held nothing.
    ///
    /// Empty by default — a day with no meetings leaves no trace of having
    /// been asked about, which is what keeps `## Today\n{{events}}` from
    /// growing a bullet that says nothing. A user who would rather be told
    /// can say so here.
    public var whenEmpty: String

    public init(
        linePrefix: String = "- ",
        timeFormat: MomentFormat? = MomentFormat("HH:mm"),
        whenEmpty: String = ""
    ) {
        self.linePrefix = linePrefix
        self.timeFormat = timeFormat
        self.whenEmpty = whenEmpty
    }

    /// The markdown that stands where the placeholder was.
    ///
    /// The items are laid out in the order the source gave them: which
    /// meeting comes first is a fact about the day, and this is the part that
    /// knows about lines and not about calendars.
    public func render(_ items: [DayItem], timeZone: TimeZone, locale: Locale) -> String {
        guard !items.isEmpty else { return whenEmpty }
        return items.map { item in
            linePrefix + time(of: item, timeZone: timeZone, locale: locale) + oneLine(item.title)
        }
        .joined(separator: "\n")
    }

    private func time(of item: DayItem, timeZone: TimeZone, locale: Locale) -> String {
        guard let timeFormat, let time = item.time else { return "" }
        return timeFormat.render(time, timeZone: timeZone, locale: locale) + " "
    }

    /// A title flattened onto the one line its item is being written as.
    ///
    /// An event called "Standup\nreally" would otherwise make two list items
    /// out of one, the second of them not a list item at all — a line of
    /// somebody's calendar rewriting the Entry's markdown around it.
    private func oneLine(_ title: String) -> String {
        title.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

extension DataPlaceholderFormat {
    /// What a calendar event's line looks like: a plain list item.
    public static let events = DataPlaceholderFormat()

    /// What a reminder's line looks like: a Task, unticked.
    ///
    /// A reminder is a thing to do, and the box is the one character of
    /// markdown that says so — tickable where the user is writing, and the
    /// same task in Obsidian.
    public static let reminders = DataPlaceholderFormat(linePrefix: "- [ ] ")
}

/// The formatting settings for every data placeholder there is.
public struct DataPlaceholderFormatting: Hashable, Sendable {
    public var events: DataPlaceholderFormat
    public var reminders: DataPlaceholderFormat

    public init(
        events: DataPlaceholderFormat = .events,
        reminders: DataPlaceholderFormat = .reminders
    ) {
        self.events = events
        self.reminders = reminders
    }

    public subscript(placeholder: DataPlaceholder) -> DataPlaceholderFormat {
        get {
            switch placeholder {
            case .events: events
            case .reminders: reminders
            }
        }
        set {
            switch placeholder {
            case .events: events = newValue
            case .reminders: reminders = newValue
            }
        }
    }

    public static let `default` = DataPlaceholderFormatting()
}

// MARK: - The day's data

/// What the device can tell Aujour about a Journal Day: one ``DayItemSource``
/// per data placeholder, and nothing else.
///
/// Empty is a whole answer and the one Core ships. A build with no sources
/// installed — every test that is not about this, every platform without a
/// calendar — spawns templates in which `{{events}}` renders empty, exactly
/// as an unknown placeholder does.
public struct DayData: Sendable {
    private let sources: [DataPlaceholder: any DayItemSource]

    public init(_ sources: [DataPlaceholder: any DayItemSource] = [:]) {
        self.sources = sources
    }

    /// Asks each of these placeholders' sources for whatever it needs before
    /// it can answer — the permission prompt, where there is one.
    ///
    /// Called before a day is opened and never during a spawn; see
    /// ``DayItemSource/prepare()``. Only the placeholders passed are asked,
    /// so a Content Template that never mentions the calendar never prompts
    /// for it.
    public func prepare(for placeholders: Set<DataPlaceholder>) async {
        await withTaskGroup(of: Void.self) { group in
            for placeholder in placeholders {
                guard let source = sources[placeholder] else { continue }
                group.addTask { await source.prepare() }
            }
        }
    }

    /// What one placeholder renders as for a Journal Day.
    ///
    /// A placeholder with no source at all renders empty rather than as an
    /// empty day: nothing was asked and nothing answered, so there is no day
    /// with nothing in it to report — it is a placeholder Aujour cannot
    /// resolve, and those render empty like every other unknown name.
    func text(
        for placeholder: DataPlaceholder,
        on day: JournalDay,
        formattedBy formatting: DataPlaceholderFormatting,
        timeZone: TimeZone,
        locale: Locale
    ) async -> String {
        guard let source = sources[placeholder] else { return "" }
        let items = await source.items(during: day.span(in: timeZone))
        return formatting[placeholder].render(items, timeZone: timeZone, locale: locale)
    }
}
