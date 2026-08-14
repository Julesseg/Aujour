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
        settings: JournalSettings = .default,
        now: Date = instant(2026, 3, 1, 9, 30, in: paris),
        locale: Locale = english
    ) {
        self.store = FallibleJournalStore(files)
        self.now = now
        self.calendar = JournalCalendar(
            store: store,
            settings: settings,
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
    func theGridIsPaddedIntoWeeks() {
        // April 2026 starts on a Wednesday, so a week beginning on Sunday
        // leaves three empty cells before the 1st.
        let session = CalendarSession(now: instant(2026, 4, 1, 9, 30, in: paris))
        let month = session.calendar.month

        #expect(month.weekdayNames == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        // The grid a screen draws: the same cells, in one sequence, so that
        // each has a place of its own to be identified by.
        #expect(month.cells.count == month.weeks.count * 7)
        #expect(month.cells.compactMap { $0 } == month.days)
        #expect(month.weeks.first?.prefix(3).allSatisfy { $0 == nil } == true)
        #expect(month.weeks.first?[3]?.day == JournalDay(year: 2026, month: 4, day: 1))
        // Thirty days after three blanks fill five rows, with the last two
        // cells of the last one left empty.
        #expect(month.weeks.count == 5)
        #expect(month.weeks.last?.suffix(2).allSatisfy { $0 == nil } == true)
        #expect(month.days.last?.day == JournalDay(year: 2026, month: 4, day: 30))
    }

    @Test("a week starts where the reader's own calendar starts it")
    func theFirstWeekdayFollowsTheLocale() {
        // The same April, read in French: the week starts on Monday, so the
        // Wednesday the month opens on has two cells before it.
        let session = CalendarSession(now: instant(2026, 4, 1, 9, 30, in: paris), locale: french)
        let month = session.calendar.month

        #expect(month.name == "avril 2026")
        #expect(month.weekdayNames.first == "L")
        #expect(month.weeks.first?.prefix(2).allSatisfy { $0 == nil } == true)
        #expect(month.weeks.first?[2]?.day == JournalDay(year: 2026, month: 4, day: 1))
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
            settings: JournalSettings(contentTemplate: "# {{title}}\n\n{{date}}, written at {{time}}.\n")
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
