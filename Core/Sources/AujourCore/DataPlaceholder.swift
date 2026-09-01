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

    /// Whether the day already saw it through — a reminder that was ticked.
    ///
    /// It is the day's finished business that makes this worth carrying: a
    /// Monday written up on Tuesday held everything Monday's list held, and
    /// writing what got done as though it were still to do would be putting
    /// something untrue in somebody's journal. Nothing that cannot be done
    /// ever sets it, and a format whose lines say nothing about doneness
    /// writes those lines the same either way.
    public var isDone: Bool

    public init(title: String, time: Date? = nil, isDone: Bool = false) {
        self.title = title
        self.time = time
        self.isDone = isDone
    }

    /// An item, or nothing at all for one with no name.
    ///
    /// For a source reading somebody's calendar, where a nameless event is a
    /// real thing to find: written out, it would be a bullet with nothing
    /// after it — a line in a journal saying only that a line was written.
    public init?(named title: String?, at time: Date? = nil, isDone: Bool = false) {
        let named = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else { return nil }
        self.init(title: named, time: time, isDone: isDone)
    }
}

extension Array where Element == DayItem {
    /// The day in the order it happened: earliest first, and the items the day
    /// holds without an hour after them.
    ///
    /// For sources whose answers arrive in no order of their own — a
    /// reminders list is a set of things to do and not a timetable. One that
    /// *has* an order has a real one, and ``DataPlaceholderFormat`` writes
    /// items out in the order it is given them.
    public func throughTheDay() -> [DayItem] {
        sorted { mine, theirs in
            switch (mine.time, theirs.time) {
            case (let mine?, let theirs?): mine < theirs
            case (_?, nil): true
            case (nil, _): false
            }
        }
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

// MARK: - Showing what a format would write

extension DataPlaceholder {
    /// Whether a day can already have seen one of these things through —
    /// whether ``DataPlaceholderFormat/donePrefix`` has anything to say about
    /// this placeholder at all.
    ///
    /// A reminder is a thing to do and gets ticked; an event is a thing that
    /// happens, and a day does not finish a meeting. Which is why the marker
    /// is not a question worth asking about every placeholder: a field that
    /// could never change a single line of somebody's Entry is a field about
    /// nothing.
    public var itemsCanBeDone: Bool {
        switch self {
        case .events: false
        case .reminders: true
        }
    }

    /// A day made up, so that a format nobody can evaluate in their head can
    /// be shown as the lines it would write.
    ///
    /// Invented rather than read off the user's own calendar, for two
    /// reasons. A real day may hold nothing — which is exactly the day the
    /// empty text is for, and a poor day to check the other three fields
    /// against — and a preview that changed as the afternoon went on would be
    /// one nobody could compare a typed character against. So it is the same
    /// day every time, holding one of each thing a format has something to
    /// say about: something at an hour, something the day held without one,
    /// and, where the placeholder has a done state, something already seen
    /// through.
    ///
    /// - Parameters:
    ///   - day: the Journal Day to sit the example on — the one the user is
    ///     writing, so that its hours read like the hours of their own today.
    ///   - timeZone: the zone those hours are the hours of.
    public func exampleDay(on day: JournalDay, in timeZone: TimeZone = .current) -> ExampleDay {
        let midnight = day.startOfDay(in: timeZone)
        func atHour(_ hour: Int) -> Date { midnight.addingTimeInterval(TimeInterval(hour) * 3600) }

        switch self {
        case .events:
            return ExampleDay(
                atAnHour: DayItem(title: "Coffee with Ana", time: atHour(9)),
                withoutAnHour: DayItem(title: "Ana's birthday"),
                alreadyDone: nil
            )
        case .reminders:
            return ExampleDay(
                atAnHour: DayItem(title: "Call the dentist", time: atHour(11)),
                withoutAnHour: DayItem(title: "Water the plants"),
                alreadyDone: DayItem(title: "Book the train", time: atHour(8), isDone: true)
            )
        }
    }

    /// The made-up day ``DataPlaceholder/exampleDay(on:in:)`` answers with:
    /// one item for each thing a ``DataPlaceholderFormat`` decides, so that
    /// every field of it can be shown as the line it writes.
    public struct ExampleDay: Hashable, Sendable {
        /// Something the day held at an hour — the line the line prefix and
        /// the time format both show themselves in.
        public let atAnHour: DayItem

        /// Something the day held without one: an all-day event, a reminder
        /// with a date and no time. What the time format leaves alone.
        public let withoutAnHour: DayItem

        /// Something the day already saw through, or `nil` for a placeholder
        /// whose items never get done — where there is no done marker to set,
        /// there is nothing to show one on.
        public let alreadyDone: DayItem?

        /// All of it, in the order the day happened — which is the order the
        /// whole placeholder would be written in.
        public var throughTheDay: [DayItem] {
            ([atAnHour, withoutAnHour] + (alreadyDone.map { [$0] } ?? [])).throughTheDay()
        }
    }
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

    /// What a line starts with when the day already saw that item through.
    ///
    /// The same marker with its box ticked, for the placeholders whose lines
    /// have a box; the same marker unchanged for the ones that do not, which
    /// is what leaves an event — a thing that happens rather than a thing to
    /// do — with nothing to say about it.
    public var donePrefix: String

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

    /// - Parameter donePrefix: the marker for an item already done, or `nil`
    ///   for one that reads the same either way — which is the default, and
    ///   what a placeholder with no boxes in its lines wants.
    public init(
        linePrefix: String = "- ",
        donePrefix: String? = nil,
        timeFormat: MomentFormat? = MomentFormat("HH:mm"),
        whenEmpty: String = ""
    ) {
        self.linePrefix = linePrefix
        // Resolved here rather than kept as an absence, so that two formats
        // are equal exactly when they write a day the same way.
        self.donePrefix = donePrefix ?? linePrefix
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
            (item.isDone ? donePrefix : linePrefix)
                + time(of: item, timeZone: timeZone, locale: locale)
                + oneLine(item.title)
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
    /// What a placeholder's lines look like before anybody has said otherwise.
    ///
    /// The one place the kinds differ by name, so that adding a placeholder is
    /// a case here and nowhere else: an event is a plain list item, and a
    /// reminder is a Task, unticked — a thing to do, and the box is the one
    /// character of markdown that says so, tickable where the user is writing
    /// and the same task in Obsidian.
    public static func `default`(for placeholder: DataPlaceholder) -> DataPlaceholderFormat {
        switch placeholder {
        case .events: DataPlaceholderFormat()
        case .reminders: DataPlaceholderFormat(linePrefix: "- [ ] ", donePrefix: "- [x] ")
        }
    }
}

/// The formatting settings for every data placeholder there is.
///
/// Every placeholder always has a format — one it was given or the default for
/// its kind — so that two of these are equal exactly when they would write a
/// day the same way. Which is what a settings seam needs of them: a write of
/// the value already held must be no news to anybody (ADR 0003).
public struct DataPlaceholderFormatting: Hashable, Sendable {
    private var formats: [DataPlaceholder: DataPlaceholderFormat]

    public init(_ formats: [DataPlaceholder: DataPlaceholderFormat] = [:]) {
        self.formats = Dictionary(
            uniqueKeysWithValues: DataPlaceholder.allCases.map { placeholder in
                (placeholder, formats[placeholder] ?? .default(for: placeholder))
            }
        )
    }

    public subscript(placeholder: DataPlaceholder) -> DataPlaceholderFormat {
        get { formats[placeholder] ?? .default(for: placeholder) }
        set { formats[placeholder] = newValue }
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

    /// What one placeholder renders as for the Entry being spawned.
    ///
    /// A placeholder with no source at all renders empty rather than as an
    /// empty day: nothing was asked and nothing answered, so there is no day
    /// with nothing in it to report — it is a placeholder Aujour cannot
    /// resolve, and those render empty like every other unknown name.
    func text(for placeholder: DataPlaceholder, at spawn: SpawnContext) async -> String {
        guard let source = sources[placeholder] else { return "" }
        let items = await source.items(during: spawn.day.span(in: spawn.timeZone))
        return spawn.dataFormatting[placeholder]
            .render(items, timeZone: spawn.timeZone, locale: spawn.locale)
    }
}
