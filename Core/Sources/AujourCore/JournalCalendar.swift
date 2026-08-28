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
/// - **Which day the app is on.** Today, until a day is picked out of the
///   grid — and today again the moment today is picked, which is absence and
///   not a copy of today's date, so that a journal left open past the rollover
///   moves on to the new day.
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

        /// Whether this day belongs to the month on screen, or is one of the
        /// neighbouring months' days the grid is filled out with.
        ///
        /// The grid shows six whole weeks whatever month it is over, so the
        /// first and last rows carry days from either side. They are days like
        /// any other — written on, openable, pickable — and the screen draws
        /// them fainter, which is the whole of what this says.
        public let isInTheMonthOnScreen: Bool

        /// Whether this is the day the app is showing: the one the pill names
        /// and the grid fills in.
        public let isBeingWritten: Bool

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

        /// Six rows of seven, filled out at both ends with the neighbouring
        /// months' days — so a row is a week, a column is a weekday, and the
        /// grid is the same height whatever month it is over.
        ///
        /// Six and not "as many as this month needs", because the rows are
        /// what the pill travels through: a week strip is this grid slid up
        /// until the week being written sits under the weekday names, and a
        /// grid that changed height from month to month would move the strip
        /// with it.
        public let weeks: [[Day]]

        /// The days of the month on screen, in order — without the
        /// neighbouring months' days the grid is filled out with.
        public var days: [Day] {
            cells.filter(\.isInTheMonthOnScreen)
        }

        /// The whole grid in reading order: the weeks laid end to end.
        ///
        /// What a grid actually draws, and what it should draw *from* — a cell
        /// is identified by its place in this one sequence. Drawing weeks of
        /// seven within a grid instead gives seven identities repeated once
        /// per row, and cells that swap what they do when one of them changes.
        public var cells: [Day] {
            weeks.flatMap { $0 }
        }

        /// Which row the day being written falls in — the one the week strip
        /// shows, and so how far the grid is slid up to show it.
        ///
        /// `nil` when that day is not on this grid at all, which is what
        /// stepping to another month does.
        public var weekBeingWritten: Int? {
            weeks.firstIndex { $0.contains(where: \.isBeingWritten) }
        }

        /// Which row the week strip is showing: the week of the day being
        /// written, until a week is stepped to.
        ///
        /// A row of this grid and not a week of its own, because the strip is
        /// this grid slid up — which is why stepping a week off the end of the
        /// grid brings the next month on screen underneath it rather than
        /// leaving the strip somewhere the grid does not reach.
        public let weekOnScreen: Int
    }

    /// The month on screen.
    public private(set) var month: Month

    /// The day picked out of the grid, or `nil` while the app is on today's.
    ///
    /// Absence and not a copy of today's date, because those two are different
    /// things overnight: a phone left open past the rollover with nothing
    /// picked should move on to the new day, and one left open on March 1st
    /// because somebody chose March 1st should not.
    private var picked: JournalDay?

    /// A day in the week the strip is showing, or `nil` while the strip
    /// follows the day being written.
    ///
    /// Absence again rather than a copy, and for the same reason: a strip that
    /// had been *told* it was on this week would stay on it after a day was
    /// picked out of another one.
    private var weekAnchor: JournalDay?

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
            weeks: [],
            weekOnScreen: 0
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

    // MARK: - The day being written

    /// The day the app is showing: the one the pill names, the one the grid
    /// fills in, and the one an Entry is open over.
    ///
    /// Today until somebody picks another, and today again the moment they
    /// pick today — which is what keeps a journal left open overnight on the
    /// day it is now rather than on the day it was.
    public var dayBeingWritten: JournalDay { picked ?? today }

    /// Whether the day being written is today's Entry, which is the one the
    /// app already has an editor over.
    public var isOnToday: Bool { picked == nil }

    /// Picks a day out of the grid.
    ///
    /// Refuses a day that has not arrived, and says so rather than picking it
    /// quietly: a locked cell is not tappable on screen, and this is the same
    /// refusal said where it cannot be tapped around — there is no Entry to
    /// write before the day has come (`v1-decisions.md`).
    ///
    /// A day from a neighbouring month is a day like any other, and picking
    /// one brings its month on screen — which is how a grid of six weeks is
    /// walked through the year without a control for it.
    @discardableResult
    public func pick(_ day: JournalDay) -> Bool {
        guard relation(of: day).allowsWriting else { return false }
        picked = day == today ? nil : day
        // Which is now this day's month, whichever month the grid was over.
        showTheMonthBeingWritten()
        return true
    }

    /// Puts the month of the day being written back on screen — what a pill
    /// closed and opened again shows, whatever month was browsed to in
    /// between.
    public func showTheMonthBeingWritten() {
        let day = dayBeingWritten
        weekAnchor = nil
        visible = (day.year, day.month)
        layOutTheMonth()
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

    // MARK: - Moving through the months and the weeks

    public func showPreviousMonth() {
        show(monthsFromHere: -1)
    }

    public func showNextMonth() {
        show(monthsFromHere: 1)
    }

    private func show(monthsFromHere months: Int) {
        // The strip goes back to following the month, which is its first row —
        // the week the month opens on. A week held over from the month before
        // would be a strip showing days the grid under it no longer has.
        weekAnchor = nil
        visible = theMonth(months, along: visible)
        layOutTheMonth()
    }

    /// The month a given number of months from another one.
    ///
    /// Stepped by the calendar rather than by counting to twelve, so the turn
    /// of the year is its problem and not this one.
    private func theMonth(
        _ steps: Int,
        along from: (year: Int, month: Int)
    ) -> (year: Int, month: Int) {
        let anchor = JournalDay(year: from.year, month: from.month, day: 1).startOfDay(in: timeZone)
        let shifted = gridCalendar.date(byAdding: .month, value: steps, to: anchor)!
        let parts = gridCalendar.dateComponents([.year, .month], from: shifted)
        return (parts.year!, parts.month!)
    }

    public func showPreviousWeek() {
        show(weeksFromHere: -1)
    }

    public func showNextWeek() {
        show(weeksFromHere: 1)
    }

    /// Steps the week strip, and brings the month along when the week it
    /// stepped to has left the grid.
    ///
    /// The strip is a row of the six-week grid, so stepping through the year
    /// by weeks is stepping through rows until there are no more, and then
    /// re-laying the grid over the month the new week lands in. Which is also
    /// why this is here and not in the view: "the week after this one" is a
    /// question about the calendar, and the answer at the end of a month is
    /// the whole of it.
    private func show(weeksFromHere weeks: Int) {
        let anchor = theWeek(weeks)
        weekAnchor = anchor
        visible = theGridHolding(anchor)
        layOutTheMonth()
    }

    /// The day the week strip would be anchored to a given number of weeks
    /// from where it is.
    private func theWeek(_ steps: Int) -> JournalDay {
        (weekAnchor ?? dayBeingWritten).adding(days: 7 * steps)
    }

    /// Which month's grid to lay a week out on: the one already on screen
    /// where it reaches that far, and the week's own month where it does not.
    ///
    /// Staying put where it can is what keeps a walk through the weeks from
    /// re-laying the grid under the strip at every step — six of them fit on
    /// one grid, and only the seventh is a new month.
    private func theGridHolding(_ day: JournalDay) -> (year: Int, month: Int) {
        row(of: day) == nil ? (day.year, day.month) : visible
    }

    /// Which row of the grid as it stands a day falls in, or `nil` when the
    /// grid does not reach it.
    private func row(of day: JournalDay) -> Int? {
        month.weeks.firstIndex { week in week.contains { $0.day == day } }
    }

    // MARK: - The pages either side of the one on screen

    /// The grid a given number of months along from the one on screen, laid
    /// out the same way and marked from the same scan — without moving what is
    /// on screen.
    ///
    /// What a finger pulls into view. A calendar that could only say what is
    /// showing would leave the month being scrolled towards blank until the
    /// scroll had finished, which is a page-turn rather than a scroll.
    public func monthAlong(_ steps: Int) -> Month {
        grid(over: theMonth(steps, along: visible), showingTheWeekOf: weekAnchor ?? dayBeingWritten)
    }

    /// The grid holding the week a given number of weeks along from the one
    /// the strip is showing, with `weekOnScreen` on that week.
    ///
    /// A whole grid for one row of it, because that is what the strip is: the
    /// month grid slid up until the week being read sits under the weekday
    /// names. The page either side is the same grid slid one row further,
    /// until the week runs off the end of it and the next month's grid takes
    /// over.
    public func weekAlong(_ steps: Int) -> Month {
        let anchor = theWeek(steps)
        return grid(over: theGridHolding(anchor), showingTheWeekOf: anchor)
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
        month = grid(over: visible, showingTheWeekOf: weekAnchor ?? dayBeingWritten)
    }

    /// One month laid out, marked from the last scan, slid to a given week.
    ///
    /// Takes what it is over rather than reading it off this object, so that
    /// the pages either side of the one on screen are laid out by the same
    /// arithmetic as the one on screen and not by a second copy of it.
    private func grid(
        over visible: (year: Int, month: Int),
        showingTheWeekOf onScreen: JournalDay
    ) -> Month {
        let calendar = gridCalendar
        let firstOfMonth = JournalDay(year: visible.year, month: visible.month, day: 1)
        let firstInstant = firstOfMonth.startOfDay(in: timeZone)

        // Read from the calendar rather than from a table: the weekday a month
        // opens on is not a constant, and neither is February's length.
        let weekday = calendar.component(.weekday, from: firstInstant)
        let daysBefore = (weekday - calendar.firstWeekday + 7) % 7

        // Six whole weeks of real days, always — the month, and enough of the
        // ones either side of it to fill the grid out. Blanks would leave a
        // grid whose height changed from month to month, and the rows are what
        // the pill travels through.
        let beginning = firstOfMonth.adding(days: -daysBefore)
        let dayBeingWritten = self.dayBeingWritten
        let cells = (0..<(Self.weeksOnTheGrid * 7)).map { offset -> Day in
            let day = beginning.adding(days: offset)
            return Day(
                day: day,
                isJournaled: journaledDays.contains(day),
                relation: relation(of: day),
                isInTheMonthOnScreen: day.year == visible.year && day.month == visible.month,
                isBeingWritten: day == dayBeingWritten
            )
        }

        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
        // And the first row of the grid when the week asked for is not on it,
        // which is the week this month opens on.
        return Month(
            year: visible.year,
            month: visible.month,
            name: firstInstant.formatted(
                Date.FormatStyle(locale: locale, timeZone: timeZone).month(.wide).year()
            ),
            weekdayNames: weekdayNames(in: calendar),
            weeks: weeks,
            weekOnScreen: weeks.firstIndex { week in week.contains { $0.day == onScreen } } ?? 0
        )
    }

    /// How many rows the grid has, whatever month it is over. Six is the most
    /// any month needs — thirty-one days that open on the last day of a week —
    /// so six is what every month gets.
    private static let weeksOnTheGrid = 6

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
