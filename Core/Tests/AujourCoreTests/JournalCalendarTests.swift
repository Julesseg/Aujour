import Foundation
import Testing

@testable import AujourCore

private let english = Locale(identifier: "en_US_POSIX")
private let french = Locale(identifier: "fr_FR")

/// The calendar over a folder of files, with the two seams that would
/// otherwise be the device: the folder itself, and the wall clock the "which
/// day is today" line is drawn at.
@MainActor
private final class CalendarSession {
    let store: FallibleJournalStore

    /// The wall clock the calendar reads. Moved by a test to turn the day.
    var now: Date

    private(set) var calendar: JournalCalendar!

    init(
        files: [String: String] = [:],
        spawningFrom template: String? = nil,
        settings: JournalSettings = .default,
        dayData: DayData = DayData(),
        now: Date = instant(2026, 3, 1, 9, 30, in: paris),
        locale: Locale = english
    ) {
        self.store = FallibleJournalStore(files)
        self.now = now
        self.calendar = JournalCalendar(
            store: store,
            settings: settings,
            spawningFrom: template.map(FixedContentTemplate.init),
            dayData: dayData,
            timeZone: paris,
            locale: locale,
            now: { self.now }
        )
    }

    /// A calendar of its own over the same folder — what the app has after a
    /// relaunch, with nothing kept from the last one.
    func secondCalendar() -> JournalCalendar {
        JournalCalendar(store: store, timeZone: paris, locale: english, now: { self.now })
    }
}

/// A Journal Store that can be made to refuse a listing, as a folder in
/// iCloud that has not come down would.
private final class FallibleJournalStore: JournalStore, @unchecked Sendable {
    private let folder: InMemoryJournalStore

    var refuseListing: (any Error)?

    init(_ files: [String: String] = [:]) {
        folder = InMemoryJournalStore(files)
    }

    func listFiles() async throws -> [String] {
        if let refuseListing { throw refuseListing }
        return await folder.listFiles()
    }

    func fileExists(at relativePath: String) async throws -> Bool {
        try await folder.fileExists(at: relativePath)
    }

    func read(at relativePath: String) async throws -> Data {
        try await folder.read(at: relativePath)
    }

    func write(_ contents: Data, at relativePath: String) async throws {
        try await folder.write(contents, at: relativePath)
    }

    func create(_ contents: Data, at relativePath: String) async throws {
        try await folder.create(contents, at: relativePath)
    }

    func move(from source: String, to destination: String) async throws {
        try await folder.move(from: source, to: destination)
    }
}

extension JournalCalendar.Month {
    /// The cell for a day of this month, by its number — how a test says
    /// "the 14th" without counting rows.
    fileprivate func cell(_ dayOfMonth: Int) -> JournalCalendar.Day? {
        days.first { $0.day.day == dayOfMonth }
    }
}

@Suite("The month the calendar shows")
@MainActor
struct JournalCalendarMonthTests {
    @Test("the calendar opens on the month of the current Journal Day")
    func theCurrentMonthIsShownFirst() {
        let session = CalendarSession()

        #expect(session.calendar.month.year == 2026)
        #expect(session.calendar.month.month == 3)
        #expect(session.calendar.month.name == "March 2026")
        #expect(session.calendar.month.days.count == 31)
    }

    @Test("the month is laid out in whole weeks, starting on the locale's first day")
    func theGridIsLaidOutInWeeks() {
        // April 2026 starts on a Wednesday, so a week beginning on Sunday puts
        // the last three days of March before the 1st.
        let session = CalendarSession(now: instant(2026, 4, 1, 9, 30, in: paris))
        let month = session.calendar.month

        #expect(month.weekdayNames == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        // The grid a screen draws: the same cells, in one sequence, so that
        // each has a place of its own to be identified by.
        #expect(month.cells.count == month.weeks.count * 7)
        #expect(month.weeks.first?[2].day == JournalDay(year: 2026, month: 3, day: 31))
        #expect(month.weeks.first?[3].day == JournalDay(year: 2026, month: 4, day: 1))
        #expect(month.days.count == 30)
        #expect(month.days.first?.day == JournalDay(year: 2026, month: 4, day: 1))
        #expect(month.days.last?.day == JournalDay(year: 2026, month: 4, day: 30))
    }

    /// Six rows whatever the month, because the rows are what the pill travels
    /// through: the week strip is this grid slid up by whole rows, and a grid
    /// that changed height from month to month would take the strip with it.
    @Test("the grid is six whole weeks whatever month it is over")
    func theGridIsAlwaysSixWeeks() {
        for (year, month) in [(2026, 2), (2026, 4), (2026, 8), (2027, 1)] {
            let session = CalendarSession(now: instant(year, month, 1, 9, 30, in: paris))
            let grid = session.calendar.month

            #expect(grid.weeks.count == 6, "\(grid.name) was laid out in \(grid.weeks.count) rows")
            #expect(grid.cells.count == 42)
            // Forty-two days running, with nothing skipped between them.
            for (earlier, later) in zip(grid.cells, grid.cells.dropFirst()) {
                #expect(earlier.day.adding(days: 1) == later.day)
            }
        }
    }

    @Test("the days either side of the month are on the grid, and known to be")
    func theNeighbouringMonthsFillTheGridOut() {
        let session = CalendarSession(now: instant(2026, 4, 1, 9, 30, in: paris))
        let month = session.calendar.month

        #expect(month.cells.first?.day == JournalDay(year: 2026, month: 3, day: 29))
        #expect(month.cells.first?.isInTheMonthOnScreen == false)
        #expect(month.cells.last?.isInTheMonthOnScreen == false)
        #expect(month.cell(1)?.isInTheMonthOnScreen == true)
        // Days like any other: the ones that have been can still be written.
        #expect(month.cells.first?.isOpenable == true)
    }

    @Test("a week starts where the reader's own calendar starts it")
    func theFirstWeekdayFollowsTheLocale() {
        // The same April, read in French: the week starts on Monday, so the
        // Wednesday the month opens on has two cells before it.
        let session = CalendarSession(now: instant(2026, 4, 1, 9, 30, in: paris), locale: french)
        let month = session.calendar.month

        #expect(month.name == "avril 2026")
        #expect(month.weekdayNames.first == "L")
        #expect(month.weeks.first?[0].day == JournalDay(year: 2026, month: 3, day: 30))
        #expect(month.weeks.first?[2].day == JournalDay(year: 2026, month: 4, day: 1))
    }

    @Test("stepping through the months crosses the turn of the year")
    func monthsStepBackwardsAndForwards() {
        let session = CalendarSession(now: instant(2026, 1, 15, 9, 30, in: paris))

        session.calendar.showPreviousMonth()
        #expect(session.calendar.month.year == 2025)
        #expect(session.calendar.month.month == 12)
        #expect(session.calendar.month.days.count == 31)

        session.calendar.showNextMonth()
        session.calendar.showNextMonth()
        #expect(session.calendar.month.year == 2026)
        #expect(session.calendar.month.month == 2)
        // A month whose length is not a constant, read from the calendar
        // rather than from a table.
        #expect(session.calendar.month.days.count == 28)
    }

    @Test("today's cell is the current Journal Day, not the calendar date")
    func oneAMBeforeTheRolloverIsStillYesterdaysCell() {
        // 1 AM on March 2nd with the day turning at 4 AM: March 1st is still
        // the day being written, and March 2nd has not arrived.
        let session = CalendarSession(
            settings: JournalSettings(rolloverHour: RolloverHour(hour: 4)!),
            now: instant(2026, 3, 2, 1, 0, in: paris)
        )
        let month = session.calendar.month

        #expect(month.cell(1)?.relation == .current)
        #expect(month.cell(2)?.relation == .future)
    }

    @Test("future days are shown, and are not open to write in")
    func futureDaysAreVisibleButLocked() {
        let session = CalendarSession()
        let month = session.calendar.month

        #expect(month.cell(2)?.relation == .future)
        #expect(month.cell(2)?.isOpenable == false)
        #expect(month.cell(1)?.isOpenable == true)
        #expect(month.cell(31) != nil)

        // A day in the month gone by is as open as today is.
        session.calendar.showPreviousMonth()
        #expect(session.calendar.month.cell(28)?.isOpenable == true)
    }
}

@Suite("Which days the calendar marks as journaled")
@MainActor
struct JournalCalendarIndicatorTests {
    /// A folder holding two Entries and a spread of files that are not
    /// Entries: a Parked File, an ordinary note, an attachment, an Entry-like
    /// name at the wrong depth, and an Entry from another month.
    private static let folder = [
        "2026/03/2026-03-01.md": "Walked to the market.\n",
        "2026/03/2026-03-14.md": "Rain all day.\n",
        "2026/03/2026-03-14_1.md": "A parked divergence.\n",
        "2026/03/notes.md": "Not an Entry.\n",
        "attachments/2026/03/photo.jpg": "",
        "2026/2026-03-20.md": "The right name in the wrong folder.\n",
        "2027/01/2027-01-05.md": "Next year.\n",
    ]

    @Test("indicators mark exactly the days whose Entry file exists")
    func onlyEntriesAreMarked() async {
        let session = CalendarSession(files: Self.folder)

        await session.calendar.scan()

        let month = session.calendar.month
        #expect(month.days.filter(\.isJournaled).map(\.day.day) == [1, 14])
        #expect(session.calendar.problem == nil)
    }

    @Test("the indicators are a scan of the folder, kept nowhere else")
    func theCacheIsRebuiltByScanning() async {
        let session = CalendarSession(files: Self.folder)
        await session.calendar.scan()

        // A relaunch: a calendar that has never seen the first one's answers
        // arrives at the same ones by reading the folder.
        let second = session.secondCalendar()
        #expect(second.month.days.contains { $0.isJournaled } == false)
        await second.scan()
        #expect(second.month.days.filter(\.isJournaled).map(\.day.day) == [1, 14])
    }

    @Test("a day written behind the calendar's back is marked at the next scan")
    func anEntryWrittenElsewhereShowsUp() async throws {
        let session = CalendarSession(files: Self.folder)
        await session.calendar.scan()
        #expect(session.calendar.month.cell(2)?.isJournaled == false)

        // Obsidian, or another device's sync, writing into the folder.
        try await session.store.writeText("Written in the vault.\n", at: "2026/03/2026-03-02.md")
        await session.calendar.scan()

        #expect(session.calendar.month.cell(2)?.isJournaled == true)
    }

    @Test("a folder that cannot be read is reported, not shown as an empty journal")
    func anUnreadableFolderIsReported() async {
        let session = CalendarSession(files: Self.folder)
        session.store.refuseListing = JournalStoreError.fileNotFound("2026")

        await session.calendar.scan()

        #expect(session.calendar.problem != nil)
        #expect(session.calendar.month.days.contains { $0.isJournaled } == false)

        // And it is over once the folder answers again.
        session.store.refuseListing = nil
        await session.calendar.scan()
        #expect(session.calendar.problem == nil)
        #expect(session.calendar.month.cell(14)?.isJournaled == true)
    }

    @Test("a scan that failed leaves the last reading of the folder standing")
    func aFailedScanKeepsWhatWasLastRead() async {
        let session = CalendarSession(files: Self.folder)
        await session.calendar.scan()

        session.store.refuseListing = JournalStoreError.fileNotFound("2026")
        await session.calendar.scan()

        // The days that were there are still there — the folder did not
        // answer, and unmarking them would say the opposite of what is known.
        // What has changed is that the calendar can no longer promise the
        // reading is current, and says so.
        #expect(session.calendar.month.days.filter(\.isJournaled).map(\.day.day) == [1, 14])
        #expect(session.calendar.problem != nil)
    }

    @Test("a journal with days in it is not at its beginning")
    func aJournalWithAPastIsNotABeginning() async {
        let session = CalendarSession(files: Self.folder)

        await session.calendar.scan()

        #expect(!session.calendar.theJournalIsAtItsBeginning)
    }

    /// The distinction the sentence turns on: one day anywhere in the folder
    /// and this is a journal with a past, whatever the month on screen holds.
    /// A month it does not reach into is an ordinary gap, and the grid states
    /// that by having no marks on it — saying so in words as well would be the
    /// app narrating what the reader is looking at.
    @Test("one day anywhere ends the beginning, even in another month")
    func oneDayAnywhereEndsTheBeginning() async {
        let session = CalendarSession()

        await session.calendar.scan()
        #expect(session.calendar.theJournalIsAtItsBeginning)

        // A day in February, with March on screen. Saying "nobody has written
        // in this journal" over a March that follows a February full of days
        // would be the app forgetting them.
        try? await session.store.writeText("Snow, and soup.\n", at: "2026/02/2026-02-14.md")
        await session.calendar.scan()

        #expect(!session.calendar.theJournalIsAtItsBeginning)
        #expect(session.calendar.month.days.filter(\.isJournaled).isEmpty)
    }

    @Test("a folder nobody has read yet is not a journal nobody has written in")
    func nothingIsSaidBeforeTheFolderAnswers() async {
        let session = CalendarSession()

        // The grid is on screen from the first frame, before any scan. An
        // empty-state notice drawn then would be a claim about a folder
        // nothing has looked in (ADR 0001).
        #expect(!session.calendar.theJournalIsAtItsBeginning)

        await session.calendar.scan()
        #expect(session.calendar.theJournalIsAtItsBeginning)
    }

    @Test("a folder that would not answer is a problem, never an empty journal")
    func anUnreadableFolderIsNeverCalledEmpty() async {
        let session = CalendarSession()
        session.store.refuseListing = JournalStoreError.fileNotFound("2026")

        await session.calendar.scan()

        // The one confusion this screen exists not to cause: a journal of ten
        // years whose folder has not come down from iCloud must never be shown
        // as a journal with nothing in it. The problem notice is what says
        // what happened.
        #expect(session.calendar.problem != nil)
        #expect(!session.calendar.theJournalIsAtItsBeginning)
    }

    @Test("a Path Template that cannot name a day is reported, not guessed at")
    func anUnusablePathTemplateIsReported() async {
        let session = CalendarSession(
            files: Self.folder,
            settings: JournalSettings(pathTemplate: "YYYY/MM")
        )

        await session.calendar.scan()

        #expect(session.calendar.problem is PathTemplateError)
    }
}

@Suite("Opening a day from the calendar")
@MainActor
struct JournalCalendarBackfillTests {
    @Test("a past day that was written opens on what its file says")
    func aWrittenPastDayOpensOnItsFile() async throws {
        let session = CalendarSession(files: ["2026/02/2026-02-14.md": "Snow, and soup.\n"])

        let editor = try #require(
            session.calendar.editor(for: JournalDay(year: 2026, month: 2, day: 14))
        )
        await editor.open()

        #expect(editor.day == JournalDay(year: 2026, month: 2, day: 14))
        #expect(editor.content == "Snow, and soup.\n")
    }

    @Test("an unwritten past day is spawned with that day's own date")
    func anUnwrittenPastDayIsSpawnedForThatDay() async throws {
        let session = CalendarSession(
            spawningFrom: "# {{title}}\n\n{{date}}, written at {{time}}.\n"
        )

        let editor = try #require(
            session.calendar.editor(for: JournalDay(year: 2026, month: 2, day: 14))
        )
        await editor.open()

        // The day being written *about* is February 14th; the clock time is
        // the one it is being written *at*.
        #expect(editor.content == "# 2026-02-14\n\n2026-02-14, written at 09:30.\n")
        // And still nothing on disk: a day opened and not written on leaves
        // no husk behind.
        #expect(try await session.store.listFiles().isEmpty)
    }

    @Test("a backfilled day's data placeholders are read for that day")
    func aBackfilledDayReadsItsOwnData() async throws {
        let session = CalendarSession(
            spawningFrom: "## Today\n{{events}}\n",
            dayData: DayData([.events: TheDayThatWasRead()])
        )

        let editor = try #require(
            session.calendar.editor(for: JournalDay(year: 2026, month: 2, day: 14))
        )
        await editor.open()

        // February 14th's meetings and not March 1st's — a day filled in on
        // another day is the whole reason the seam is asked about a day.
        #expect(editor.content == "## Today\n- 2026-02-14\n")
    }

    @Test("the backfilled file is created by the typing, at that day's path")
    func typingIntoABackfilledDayCreatesItsFile() async throws {
        let session = CalendarSession()
        let editor = try #require(
            session.calendar.editor(for: JournalDay(year: 2026, month: 2, day: 14))
        )
        await editor.open()

        editor.content = "Snow, and soup.\n"
        await editor.save()

        #expect(try await session.store.listFiles() == ["2026/02/2026-02-14.md"])
        // Which is what the calendar marks it by, at the next scan.
        session.calendar.showPreviousMonth()
        await session.calendar.scan()
        #expect(session.calendar.month.cell(14)?.isJournaled == true)
    }

    @Test("a future day cannot be opened to write in")
    func aFutureDayHasNoEditor() {
        let session = CalendarSession()

        #expect(session.calendar.editor(for: JournalDay(year: 2026, month: 3, day: 2)) == nil)
        #expect(session.calendar.editor(for: JournalDay(year: 2027, month: 1, day: 1)) == nil)
        #expect(session.calendar.editor(for: JournalDay(year: 2026, month: 3, day: 1)) != nil)
    }

    @Test("the day the calendar opened does not move when the clock does")
    func abackfilledDayDoesNotFollowTheClock() async throws {
        let session = CalendarSession()
        let editor = try #require(
            session.calendar.editor(for: JournalDay(year: 2026, month: 2, day: 14))
        )
        await editor.open()

        // Today's Entry follows the Journal Day turning; a day opened from
        // the calendar is the day it was opened on, and stays it.
        session.now = instant(2026, 3, 3, 9, 30, in: paris)
        await editor.reopenIfTheDayTurned()

        #expect(editor.day == JournalDay(year: 2026, month: 2, day: 14))
    }
}

/// A source that answers with the date it was asked about, so that a spawned
/// Entry says which day the calendar was read for.
private struct TheDayThatWasRead: DayItemSource {
    func items(during day: DateInterval) async -> [DayItem] {
        [DayItem(title: MomentFormat("YYYY-MM-DD").render(day.start, timeZone: paris))]
    }
}

@Suite("The day the calendar is on")
@MainActor
struct JournalCalendarPickingTests {
    @Test("the app is on today until somebody picks another day")
    func todayIsWhereItStarts() {
        let session = CalendarSession()

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.calendar.isOnToday)
        #expect(session.calendar.month.cell(1)?.isBeingWritten == true)
    }

    @Test("picking a day makes it the day being written, and marks its cell")
    func pickingADayMovesTheGridOntoIt() {
        let session = CalendarSession(now: instant(2026, 3, 20, 9, 30, in: paris))

        #expect(session.calendar.pick(JournalDay(year: 2026, month: 3, day: 14)))

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 14))
        #expect(!session.calendar.isOnToday)
        #expect(session.calendar.month.cell(14)?.isBeingWritten == true)
        #expect(session.calendar.month.cell(20)?.isBeingWritten == false)
    }

    /// The one the whole grid exists to refuse: a day that has not arrived has
    /// no Entry to write, so it cannot be picked from the screen *or* from
    /// here (`v1-decisions.md`).
    @Test("a day that has not arrived cannot be picked")
    func aFutureDayIsRefused() {
        let session = CalendarSession()

        #expect(session.calendar.pick(JournalDay(year: 2026, month: 3, day: 2)) == false)

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.calendar.isOnToday)
    }

    /// Picking today is going back to following the clock, not pinning
    /// today's date — which is what a phone left open past the rollover shows
    /// the difference between.
    @Test("picking today puts the app back on whatever day it is")
    func pickingTodayFollowsTheClockAgain() {
        let session = CalendarSession(
            settings: JournalSettings(rolloverHour: RolloverHour(hour: 4)!),
            now: instant(2026, 3, 1, 22, 0, in: paris)
        )
        session.calendar.pick(JournalDay(year: 2026, month: 2, day: 20))
        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 1))

        // Past midnight and past the rollover: it is March 2nd now.
        session.now = instant(2026, 3, 2, 9, 0, in: paris)

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 2))
        #expect(session.calendar.isOnToday)
    }

    @Test("a day picked from the month before brings its month on screen")
    func pickingFromTheEdgeOfTheGridStepsTheMonth() {
        let session = CalendarSession(now: instant(2026, 4, 15, 9, 30, in: paris))

        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 30))

        #expect(session.calendar.month.month == 3)
        #expect(session.calendar.month.name == "March 2026")
        #expect(session.calendar.month.cell(30)?.isBeingWritten == true)
    }

    @Test("the month browsed to is put back when the pill opens again")
    func theMonthBeingWrittenComesBack() {
        let session = CalendarSession()
        session.calendar.showPreviousMonth()
        session.calendar.showPreviousMonth()
        #expect(session.calendar.month.month == 1)

        session.calendar.showTheMonthBeingWritten()

        #expect(session.calendar.month.month == 3)
    }

    /// What the week strip is: this grid slid up by whole rows until the week
    /// being written sits under the weekday names.
    @Test("the row the day being written falls in is the week the strip shows")
    func theStripKnowsWhichRowToShow() {
        // 1 March 2026 is a Sunday, so it opens the grid's first row and the
        // rows below it are the 8th, the 15th and the 22nd.
        let session = CalendarSession(now: instant(2026, 3, 25, 9, 30, in: paris))

        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.calendar.month.weekBeingWritten == 0)

        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 14))
        #expect(session.calendar.month.weekBeingWritten == 1)

        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 15))
        #expect(session.calendar.month.weekBeingWritten == 2)
    }

    @Test("a month stepped away from has no week to show")
    func amonthWithoutTheDayBeingWrittenSaysSo() {
        let session = CalendarSession()

        session.calendar.showPreviousMonth()
        session.calendar.showPreviousMonth()

        #expect(session.calendar.month.weekBeingWritten == nil)
        // The strip falls back to the row the month opens on rather than to
        // nowhere: every grid has a first week, and it is the one this month
        // begins in.
        #expect(session.calendar.month.weekOnScreen == 0)
    }

    /// Walking the calendar sideways, which on a strip is the only way through
    /// it: there is no room on one row for a pair of chevrons.
    @Test("the strip steps a week at a time, forwards and back")
    func theStripStepsByWeeks() {
        // 1 March 2026 is a Sunday and the day being written, so it opens the
        // grid and the rows under it are the 8th, the 15th and the 22nd.
        let session = CalendarSession()
        #expect(session.calendar.month.weekOnScreen == 0)

        session.calendar.showNextWeek()
        #expect(session.calendar.month.weekOnScreen == 1)

        session.calendar.showNextWeek()
        #expect(session.calendar.month.weekOnScreen == 2)

        session.calendar.showPreviousWeek()
        #expect(session.calendar.month.weekOnScreen == 1)

        // And the day being written has not moved: walking the calendar is
        // looking, and picking a day is choosing.
        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.calendar.isOnToday)
    }

    /// The strip is a row of the six-week grid, so a week off either end of it
    /// is a month to re-lay the grid over.
    @Test("a week stepped off the end of the grid brings the next month under it")
    func steppingAWeekOffTheGridStepsTheMonth() {
        let session = CalendarSession()

        // Backwards first: March 2026 opens on a Sunday, so its grid starts on
        // the 1st and the week before is February's business.
        session.calendar.showPreviousWeek()

        #expect(session.calendar.month.month == 2)
        // February 2026 also opens on a Sunday, so the 22nd is its fourth row.
        #expect(session.calendar.month.weekOnScreen == 3)
        #expect(session.calendar.month.weeks[3].first?.day == JournalDay(year: 2026, month: 2, day: 22))

        // And forwards, off the far end: the March grid runs to 11 April, so
        // the week of the 12th is April's.
        session.calendar.showTheMonthBeingWritten()
        for _ in 0..<6 { session.calendar.showNextWeek() }

        #expect(session.calendar.month.month == 4)
        #expect(session.calendar.month.weeks[session.calendar.month.weekOnScreen].first?.day
            == JournalDay(year: 2026, month: 4, day: 12))
    }

    /// What a scroll needs that a page-turn does not: the month or the week
    /// either side of this one, laid out and ready to be carried into view,
    /// without the calendar having moved onto it.
    @Test("the pages either side are laid out without moving what is on screen")
    func thePagesEitherSideAreLaidOutWithoutMovingWhatIsOnScreen() {
        let session = CalendarSession()

        let before = session.calendar.monthAlong(-1)
        let after = session.calendar.monthAlong(1)

        #expect(before.month == 2)
        #expect(before.name == "February 2026")
        #expect(after.month == 4)
        #expect(session.calendar.month.month == 3)
        #expect(session.calendar.monthAlong(0) == session.calendar.month)
    }

    /// The strip is a row of the grid, so the week either side is usually the
    /// same grid one row along — and a new grid only where the rows run out.
    @Test("the week either side of the strip is a row of the same grid, until it is not")
    func theWeekPagesAreRowsOfTheSameGrid() {
        // 1 March 2026 is a Sunday and the day being written, so the strip is
        // on the grid's first row and the row under it is the 8th.
        let session = CalendarSession()

        let after = session.calendar.weekAlong(1)
        #expect(after.month == 3)
        #expect(after.weekOnScreen == 1)

        // And backwards there is no row above it, so February's grid takes
        // over — where the week of 22 February is the fourth row.
        let before = session.calendar.weekAlong(-1)
        #expect(before.month == 2)
        #expect(before.weekOnScreen == 3)
        #expect(before.weeks[3].first?.day == JournalDay(year: 2026, month: 2, day: 22))

        // None of which moved the strip.
        #expect(session.calendar.month.month == 3)
        #expect(session.calendar.month.weekOnScreen == 0)
    }

    @Test("a page is marked from the same scan the page on screen is")
    func thePagesCarryTheMarksTheFolderHolds() async {
        let session = CalendarSession(files: ["2026/02/2026-02-14.md": "Words.\n"])

        await session.calendar.scan()

        let before = session.calendar.monthAlong(-1)
        #expect(before.days.contains { $0.day.day == 14 && $0.isJournaled })
        #expect(before.days.allSatisfy { $0.day.day == 14 || !$0.isJournaled })
    }

    @Test("the week walked to is given up when the pill goes back to the day being written")
    func theStripGoesBackToTheDayBeingWritten() {
        let session = CalendarSession()
        session.calendar.showNextWeek()
        session.calendar.showNextWeek()
        #expect(session.calendar.month.weekOnScreen == 2)

        session.calendar.showTheMonthBeingWritten()

        #expect(session.calendar.month.weekOnScreen == 0)
    }

    @Test("picking a day puts the strip on that day's week")
    func pickingADayMovesTheStrip() {
        let session = CalendarSession(now: instant(2026, 3, 25, 9, 30, in: paris))
        session.calendar.showNextWeek()

        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 10))

        #expect(session.calendar.month.weekOnScreen == 1)
        #expect(session.calendar.month.weekOnScreen == session.calendar.month.weekBeingWritten)
    }

    /// The neighbouring months' days are on the grid now, and a mark on one of
    /// them is not a mark on this month.
    @Test("a mark on the month before is not one of this month's days")
    func aNeighbouringMonthsMarkIsNotThisMonths() async {
        // April 2026 opens on a Wednesday, so the last three days of March are
        // on its grid — and one of them was written in.
        let session = CalendarSession(
            files: ["2026/03/2026-03-30.md": "Words.\n"],
            now: instant(2026, 4, 15, 9, 30, in: paris)
        )

        await session.calendar.scan()

        #expect(session.calendar.month.cells.contains { $0.day.month == 3 && $0.isJournaled })
        #expect(session.calendar.month.days.filter(\.isJournaled).isEmpty)
    }
}

/// The third way through the journal, after the month and the week: one day at
/// a time, which is what a finger drawn across the day's own writing does.
///
/// Not the grid's way, and the difference is the whole of this suite. The grid
/// locks a day that has not arrived because a locked cell is one that cannot
/// be written in; a swipe is looking rather than choosing, so it reaches
/// tomorrow and finds a day that says it has not begun.
@Suite("Moving a day at a time")
@MainActor
struct JournalCalendarDayWalkingTests {
    @Test("the day after and the day before are one step either side")
    func steppingADayMovesTheDayBeingWritten() {
        let session = CalendarSession(now: instant(2026, 3, 14, 9, 30, in: paris))

        session.calendar.showPreviousDay()

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 13))
        #expect(!session.calendar.isOnToday)
        #expect(session.calendar.month.cell(13)?.isBeingWritten == true)

        session.calendar.showNextDay()

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 14))
        #expect(session.calendar.isOnToday)
    }

    /// Absence and not a copy of today's date, exactly as picking today is:
    /// stepping back to today puts the app on whatever day it is, so a journal
    /// left open past the rollover moves on to the new one.
    @Test("stepping back onto today follows the clock again")
    func steppingOntoTodayFollowsTheClockAgain() {
        let session = CalendarSession(
            settings: JournalSettings(rolloverHour: RolloverHour(hour: 4)!),
            now: instant(2026, 3, 1, 22, 0, in: paris)
        )
        session.calendar.showPreviousDay()
        session.calendar.showNextDay()
        #expect(session.calendar.isOnToday)

        // Past midnight and past the rollover: it is March 2nd now.
        session.now = instant(2026, 3, 2, 9, 0, in: paris)

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 2))
    }

    /// The one the grid refuses and this does not. A day that has not arrived
    /// is on the calendar to be seen, and a swipe is a way of seeing it — what
    /// it has is no Entry, which is `writingOpensAt` saying so and
    /// `editor(for:)` saying it again.
    @Test("a swipe reaches a day that has not arrived, and finds it locked")
    func aDayThatHasNotArrivedIsReachedAndLocked() {
        let session = CalendarSession(now: instant(2026, 3, 14, 9, 30, in: paris))
        #expect(session.calendar.writingOpensAt == nil)

        session.calendar.showNextDay()

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 15))
        #expect(session.calendar.writingOpensAt == RolloverHour.midnight)
        #expect(session.calendar.editor(for: session.calendar.dayBeingWritten) == nil)
    }

    /// The hour named is the one this journal turns its day at, not midnight
    /// by default: the locked page says when writing opens, and that is a
    /// setting.
    @Test("the locked day names this journal's own rollover hour")
    func theLockedDayNamesTheRolloverHour() {
        let session = CalendarSession(
            settings: JournalSettings(rolloverHour: RolloverHour(hour: 4)!),
            now: instant(2026, 3, 14, 9, 30, in: paris)
        )

        session.calendar.showNextDay()

        #expect(session.calendar.writingOpensAt == RolloverHour(hour: 4)!)
    }

    /// Which is what the way back is for: the Today chip is on the pill the
    /// whole time a locked day is on screen, because the app is not on today.
    @Test("a day that has not arrived is walked back out of the way it was walked into")
    func aLockedDayIsWalkedBackOutOf() {
        let session = CalendarSession(now: instant(2026, 3, 14, 9, 30, in: paris))
        session.calendar.showNextDay()
        session.calendar.showNextDay()
        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 16))
        #expect(!session.calendar.isOnToday)

        session.calendar.showPreviousDay()
        session.calendar.showPreviousDay()

        #expect(session.calendar.isOnToday)
        #expect(session.calendar.writingOpensAt == nil)
    }

    /// The pill is over whichever day the app is on, so stepping off the end
    /// of a month brings the next one under it — the same thing picking a day
    /// out of a neighbouring month does.
    @Test("stepping off the end of a month brings the next month on screen")
    func steppingPastTheEndOfAMonthMovesTheGrid() {
        let session = CalendarSession(now: instant(2026, 3, 31, 9, 30, in: paris))

        session.calendar.showNextDay()

        #expect(session.calendar.month.month == 4)
        #expect(session.calendar.month.name == "April 2026")
        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 4, day: 1))
    }

    @Test("and off the start of one brings the month before")
    func steppingBackPastTheStartOfAMonthMovesTheGrid() {
        let session = CalendarSession(now: instant(2026, 3, 1, 9, 30, in: paris))

        session.calendar.showPreviousDay()

        #expect(session.calendar.month.month == 2)
        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 2, day: 28))
    }

    /// The one a swipe forwards makes reachable and nothing else could: a day
    /// picked while it was still to come, left on screen, and overtaken by the
    /// clock.
    ///
    /// It is now both the day being written and today, and the app is still
    /// pinned to it rather than following the clock — so the way back to today
    /// is still offered, and it has to still work. Picking today is a decision
    /// even when today is already the day on screen.
    @Test("a day swiped to before it arrived can be handed back to the clock once it has")
    func aPickedDayOvertakenByTheClockGoesBackToTheClock() {
        let session = CalendarSession(now: instant(2026, 3, 14, 9, 30, in: paris))
        session.calendar.showNextDay()
        #expect(session.calendar.writingOpensAt != nil)

        // Overnight: the day that had not arrived is today.
        session.now = instant(2026, 3, 15, 9, 30, in: paris)
        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 15))
        #expect(session.calendar.writingOpensAt == nil)
        #expect(!session.calendar.isOnToday)

        #expect(session.calendar.pick(session.calendar.today))

        #expect(session.calendar.isOnToday)
    }

    /// And the ordinary case that must stay a no-op: tapping the day already
    /// being written rebuilds nothing, because rebuilding is what the app does
    /// with a `true` from here — a second editor over one Entry is a day's
    /// words autosaving over themselves.
    @Test("picking the day already being written changes nothing")
    func pickingTheDayAlreadyOnScreenIsANoOp() {
        let session = CalendarSession(now: instant(2026, 3, 14, 9, 30, in: paris))
        session.calendar.pick(JournalDay(year: 2026, month: 3, day: 10))

        #expect(session.calendar.pick(JournalDay(year: 2026, month: 3, day: 10)) == false)

        #expect(session.calendar.dayBeingWritten == JournalDay(year: 2026, month: 3, day: 10))
    }

    /// A past day with no Entry is what a swipe backwards mostly lands on, and
    /// it is not locked: it is spawned for that day, which is Backfill
    /// (`CONTEXT.md`).
    @Test("a past day with no entry has an editor waiting on it")
    func aPastDayIsBackfilledRatherThanLocked() {
        let session = CalendarSession(now: instant(2026, 3, 14, 9, 30, in: paris))

        session.calendar.showPreviousDay()

        #expect(session.calendar.writingOpensAt == nil)
        #expect(session.calendar.editor(for: session.calendar.dayBeingWritten) != nil)
    }
}
