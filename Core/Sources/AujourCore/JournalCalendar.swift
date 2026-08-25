import Foundation
import Observation

/// The Journal seen a month at a time: which days were written on, which day
/// it is, and the way in to any day that can still be written in.
///
/// The three decisions behind the calendar screen are here, so that the
/// screen is left with the grid and the taps:
///
/// - **Which days are journaled.** A day is journaled exactly when its Entry
///   file exists (ADR 0001), and which files are Entries is the current Path
///   Template's answer and nothing else (ADR 0002). So the indicators are a
///   scan of the folder, kept nowhere but here and thrown away with this
///   object — a cache that cannot go stale in any way that outlives a launch,
///   because rebuilding it *is* reading the journal.
/// - **Which day is today.** The current Journal Day, Rollover Hour
///   respected — so at 1 AM with a 4 AM rollover the cell still lit is
///   yesterday's.
/// - **Which days can be opened.** Every day up to today: a past day with no
///   file is spawned from the Content Template dated to *that* day, so a busy
///   Monday can be filled in on Tuesday and never leaves a permanent hole.
///   Future days are shown and locked — there is no Entry to write before the
///   day has arrived (`v1-decisions.md`).
///
/// It reaches the world through a Journal Store and a clock, and nothing
/// else, so all of the above is tested against an in-memory folder on any
/// platform.
@MainActor
@Observable
public final class JournalCalendar {
    /// One cell of the grid: a day, and everything the screen draws it from.
    public struct Day: Hashable, Sendable, Identifiable {
        public let day: JournalDay

        /// Whether this day's Entry file exists — the whole of "this day was
        /// journaled", and so the whole of what an indicator means.
        public let isJournaled: Bool

        /// Where the day sits relative to now.
        public let relation: JournalDay.Relation

        /// Whether tapping this day opens it for writing.
        public var isOpenable: Bool { relation.allowsWriting }

        /// The day this cell is for, which is the Entry's identity too — an
        /// Entry is its date, not its file name.
        public var id: JournalDay { day }
    }

    /// A month laid out for reading: the grid, and the words around it.
    public struct Month: Hashable, Sendable {
        public let year: Int

        /// 1 through 12.
        public let month: Int

        /// The month as a heading — "March 2026", in the reader's language.
        public let name: String

        /// The column headings, from the day the reader's own week starts on:
        /// Sunday first in the US, Monday first in France.
        public let weekdayNames: [String]

        /// Rows of seven, padded with `nil` where the month has not started
        /// or has ended — so a row is a week, and a column is a weekday.
        public let weeks: [[Day?]]

        /// Every day of the month, in order and without the padding.
        public var days: [Day] {
            cells.compactMap { $0 }
        }

        /// The whole grid in reading order: the weeks laid end to end, blanks
        /// and all.
        ///
        /// What a grid actually draws, and what it should draw *from* — a cell
        /// is identified by its place in this one sequence. Drawing weeks of
        /// seven within a grid instead gives seven identities repeated once
        /// per row, and cells that swap what they do when one of them changes.
        public var cells: [Day?] {
            weeks.flatMap { $0 }
        }
    }

    /// The month on screen.
    public private(set) var month: Month

    /// What went wrong with the last scan, if it did.
    ///
    /// Surfaced rather than swallowed: a folder that could not be listed
    /// gives a calendar with no indicators on it, which is exactly what a
    /// journal nobody has written in looks like. Only one of those is true,
    /// and the screen has to be able to say which (ADR 0001).
    public private(set) var problem: (any Error)?

    @ObservationIgnored private let store: any JournalStore
    @ObservationIgnored private let settings: JournalSettings

    /// Where a day spawned from this calendar reads its Content Template.
    private let template: (any ContentTemplateSource)?

    /// Handed on to every editor this calendar opens, so a day filled in from
    /// here reads its own day's calendar rather than nothing at all.
    @ObservationIgnored private let dayData: DayData

    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let now: @MainActor () -> Date

    /// The days with an Entry file, as of the last scan — the disposable
    /// cache the indicators are drawn from (ADR 0001).
    @ObservationIgnored private var journaledDays: Set<JournalDay> = []

    /// Whether the folder has ever answered a scan.
    ///
    /// Kept because a grid with no marks on it means two different things
    /// before and after: nobody has looked, and there is nothing there. Only
    /// the second is something to put in front of the user (ADR 0001).
    private var hasBeenRead = false

    /// Which month `month` is showing, kept as numbers so that stepping
    /// through the year is arithmetic rather than a re-reading of the grid.
    @ObservationIgnored private var visible: (year: Int, month: Int)

    /// - Parameters:
    ///   - store: the folder this Journal lives in.
    ///   - settings: the Path Template that says which files are Entries, the
    ///     Content Template a backfilled day is spawned from, and the
    ///     Rollover Hour that decides which day is today.
    ///   - dayData: where a backfilled day's data placeholders read that day
    ///     from — the same seam today's Entry spawns through.
    ///   - timeZone: the zone the Journal Day is read in.
    ///   - locale: picks the month and weekday names, and the day the week
    ///     starts on.
    ///   - now: the wall clock. Read on every question rather than once, so a
    ///     calendar left on screen overnight moves "today" when it is asked
    ///     again.
    /// - Parameter template: where a backfilled day's markdown is spawned
    ///   from — handed on to every editor this calendar makes, so a day filled
    ///   in from here starts from the same template today does.
    public init(
        store: any JournalStore,
        settings: JournalSettings = .default,
        spawningFrom template: (any ContentTemplateSource)? = nil,
        dayData: DayData = DayData(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.settings = settings
        self.template = template
        self.dayData = dayData
        self.timeZone = timeZone
        self.locale = locale
        self.now = now

        let today = JournalDay.current(at: now(), in: timeZone, rolloverHour: settings.rolloverHour)
        self.visible = (today.year, today.month)
        // Empty for the one line it takes to lay the month out properly:
        // `month` is a stored property, so it has to hold something before
        // any method of this object can fill it in. Nothing ever reads this.
        self.month = Month(
            year: today.year,
            month: today.month,
            name: "",
            weekdayNames: [],
            weeks: []
        )
        // The grid is on screen from the first frame, with no indicators on
        // it yet: those arrive when the folder answers a `scan()`.
        layOutTheMonth()
    }

    /// The Journal Day it is now: the cell the grid lights up, and the day
    /// the app's Today screen is over.
    ///
    /// Asked of the clock every time rather than fixed at launch, and by way
    /// of the Rollover Hour — at 1 AM with a 4 AM rollover this is still
    /// yesterday, which is the day the user is writing.
    public var today: JournalDay {
        JournalDay.current(at: now(), in: timeZone, rolloverHour: settings.rolloverHour)
    }

    /// Why the month on screen has no marks on it — or `nil` when it has some,
    /// and when there is nothing honest to say about it having none.
    ///
    /// A grid with no dots is four different things, and three of them must
    /// never be dressed up as the fourth (ADR 0001): a folder nothing has
    /// looked in yet, a folder that would not answer, a month a journal simply
    /// does not reach into, and a journal nobody has written in. Only the last
    /// two are the user's to be told about, and only the last is a beginning
    /// rather than an absence — so the calendar says which, and the screen
    /// draws it.
    ///
    /// Silent before the first scan and silent while there is a `problem`,
    /// because both are the app saying it does not know: a journal of ten years
    /// whose folder has not come down from iCloud looks exactly like a journal
    /// of none, and calling it empty is the one thing this screen must not do.
    public var nothingToShow: NothingToShow? {
        guard hasBeenRead, problem == nil else { return nil }
        guard !month.days.contains(where: \.isJournaled) else { return nil }
        return journaledDays.isEmpty ? .aJournalNobodyHasWrittenIn : .aMonthNobodyWroteIn
    }

    /// The two empty months worth saying something about.
    public enum NothingToShow: Hashable, Sendable {
        /// Nothing anywhere in the folder: a journal at its beginning, which
        /// is a thing to invite somebody into rather than a gap to explain.
        case aJournalNobodyHasWrittenIn

        /// Days elsewhere in the journal, none of them in this month.
        case aMonthNobodyWroteIn
    }

    // MARK: - Reading the folder

    /// Rebuilds the indicators by reading the Journal Root.
    ///
    /// This is the only way they are ever built. There is no index to keep in
    /// step with the folder, and so no way for the two to disagree: a day
    /// written in Obsidian, or arriving from another device, is marked at the
    /// next scan, and a folder emptied out unmarks itself.
    public func scan() async {
        do {
            // A Path Template that cannot name a day cannot say which files
            // are Entries either, so no day can be claimed as journaled —
            // that is a sentence for the user rather than an empty calendar
            // (ADR 0002).
            let template = try PathTemplate(settings.pathTemplate)
            let files = try await store.listFiles()
            journaledDays = Set(files.compactMap(template.match))
            hasBeenRead = true
            problem = nil
        } catch {
            // What was scanned last time is kept: it is the last true reading
            // of the folder, and dropping it would turn a folder that failed
            // to answer into a journal with nothing in it. `problem` is what
            // says the reading may be behind.
            problem = error
        }
        layOutTheMonth()
    }

    // MARK: - Moving through the months

    public func showPreviousMonth() {
        show(monthsFromHere: -1)
    }

    public func showNextMonth() {
        show(monthsFromHere: 1)
    }

    private func show(monthsFromHere months: Int) {
        let anchor = JournalDay(year: visible.year, month: visible.month, day: 1)
            .startOfDay(in: timeZone)
        // Stepped by the calendar rather than by counting to twelve, so the
        // turn of the year is its problem and not this one.
        let shifted = gridCalendar.date(byAdding: .month, value: months, to: anchor)!
        let parts = gridCalendar.dateComponents([.year, .month], from: shifted)
        visible = (parts.year!, parts.month!)
        layOutTheMonth()
    }

    // MARK: - Opening a day

    /// The way in to a day's Entry: its file if it has one, the Content
    /// Template spawned for that day if it does not — which is backfill.
    ///
    /// `nil` for a day that has not arrived. Future days are on the calendar
    /// to be seen and not to be written in, and this is where that is
    /// decided: an editor is the only thing that can write an Entry, so a day
    /// with no editor is a day with no file, however hard the screen is
    /// tapped.
    ///
    /// A fresh editor each time, pinned to the day asked for. It is the
    /// caller's to open and to keep for as long as that day is on screen —
    /// and to ask for only once per day at a time: two editors over one Entry
    /// would autosave that day's file over each other. Today's Entry is
    /// usually already open elsewhere in an app, which is why this answers
    /// for it too rather than deciding whose editor that is.
    public func editor(for day: JournalDay) -> EntryEditor? {
        guard relation(of: day).allowsWriting else { return nil }
        return EntryEditor(
            store: store,
            settings: settings,
            spawningFrom: template,
            dayData: dayData,
            timeZone: timeZone,
            locale: locale,
            day: day,
            now: now
        )
    }

    // MARK: - Laying out the grid

    private func layOutTheMonth() {
        let calendar = gridCalendar
        let firstOfMonth = JournalDay(year: visible.year, month: visible.month, day: 1)
        let firstInstant = firstOfMonth.startOfDay(in: timeZone)

        // Both read from the calendar rather than from a table: February's
        // length is not a constant, and neither is the weekday a month opens
        // on.
        let length = calendar.range(of: .day, in: .month, for: firstInstant)!.count
        let weekday = calendar.component(.weekday, from: firstInstant)
        let blanksBefore = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Day?] = Array(repeating: nil, count: blanksBefore)
        for dayOfMonth in 1...length {
            let day = JournalDay(year: visible.year, month: visible.month, day: dayOfMonth)
            cells.append(
                Day(
                    day: day,
                    isJournaled: journaledDays.contains(day),
                    relation: relation(of: day)
                )
            )
        }
        // Filled out to whole weeks, so that every row is seven wide and a
        // column stays one weekday all the way down.
        while !cells.count.isMultiple(of: 7) {
            cells.append(nil)
        }

        month = Month(
            year: visible.year,
            month: visible.month,
            name: firstInstant.formatted(
                Date.FormatStyle(locale: locale, timeZone: timeZone).month(.wide).year()
            ),
            weekdayNames: weekdayNames(in: calendar),
            weeks: stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
        )
    }

    /// The column headings, rotated to start where this locale's week does.
    /// Foundation lists them from Sunday whatever the locale; `firstWeekday`
    /// is what says where the reader's own week begins.
    private func weekdayNames(in calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func relation(of day: JournalDay) -> JournalDay.Relation {
        day.relation(to: now(), in: timeZone, rolloverHour: settings.rolloverHour)
    }

    /// The calendar the grid is measured with: this Journal's zone, and the
    /// reader's locale, which is what decides the first day of the week and
    /// the names of the days.
    private var gridCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }
}
