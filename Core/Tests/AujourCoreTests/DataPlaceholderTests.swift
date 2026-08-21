import Foundation
import Testing

@testable import AujourCore

private let english = Locale(identifier: "en_US_POSIX")

/// A day of items, answered from memory — the fake every test here reads
/// through, standing where EventKit stands in the app.
///
/// It records the stretch it was asked about, because "the right day" is most
/// of what a data placeholder has to get right, and a backfill is where it is
/// easiest to get wrong.
private final class ADayOfItems: DayItemSource, @unchecked Sendable {
    private let answer: @Sendable (DateInterval) -> [DayItem]
    private let lock = NSLock()
    private var askedAbout: DateInterval?
    private var timesPrepared = 0

    init(_ items: [DayItem]) {
        self.answer = { _ in items }
    }

    init(answering answer: @escaping @Sendable (DateInterval) -> [DayItem]) {
        self.answer = answer
    }

    func items(during day: DateInterval) async -> [DayItem] {
        lock.withLock { askedAbout = day }
        return answer(day)
    }

    func prepare() async {
        lock.withLock { timesPrepared += 1 }
    }

    var span: DateInterval? { lock.withLock { askedAbout } }
    var preparations: Int { lock.withLock { timesPrepared } }
}

/// A source that never answers until it is let go — for the claim that a
/// spawn reads the placeholders it names *at the same time* rather than one
/// after the other.
private final class ASourceThatWaits: DayItemSource, @unchecked Sendable {
    private let item: DayItem
    private let arrived: @Sendable () -> Void
    private let letGo: @Sendable () async -> Void

    init(
        _ item: DayItem,
        arrived: @escaping @Sendable () -> Void,
        letGo: @escaping @Sendable () async -> Void
    ) {
        self.item = item
        self.arrived = arrived
        self.letGo = letGo
    }

    func items(during day: DateInterval) async -> [DayItem] {
        arrived()
        await letGo()
        return [item]
    }
}

// A backfill throughout, like `ContentTemplateTests`: the Entry is Sunday
// 1 March, written on Wednesday 4 March — so "which day were the events read
// for?" is always an answerable question.
private let march1 = JournalDay(year: 2026, month: 3, day: 1)

private func spawn(
    _ formatting: DataPlaceholderFormatting = .default
) -> SpawnContext {
    SpawnContext(
        day: march1,
        instant: instant(2026, 3, 4, 14, 5, in: paris),
        title: "2026-03-01",
        timeZone: paris,
        locale: english,
        dataFormatting: formatting
    )
}

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    instant(2026, 3, 1, hour, minute, in: paris)
}

@Suite("Data placeholders at spawn")
struct DataPlaceholderSpawnTests {
    @Test("{{events}} renders the day's items as the format says")
    func eventsRenderAsAList() async {
        let calendar = ADayOfItems([
            DayItem(title: "Standup", time: at(9, 30)),
            DayItem(title: "Dentist", time: at(14)),
        ])

        let rendered = await ContentTemplate("## Today\n{{events}}\n").render(
            at: spawn(),
            reading: DayData([.events: calendar])
        )

        #expect(rendered == "## Today\n- 09:30 Standup\n- 14:00 Dentist\n")
    }

    @Test("{{reminders}} arrives as tasks the user can tick")
    func remindersRenderAsTasks() async {
        let reminders = ADayOfItems([
            DayItem(title: "Call the plumber", time: at(11)),
            DayItem(title: "Renew the passport"),
        ])

        let rendered = await ContentTemplate("{{reminders}}").render(
            at: spawn(),
            reading: DayData([.reminders: reminders])
        )

        // The one with no time of its own loses the space a clock would have
        // left behind it.
        #expect(rendered == "- [ ] 11:00 Call the plumber\n- [ ] Renew the passport")
    }

    @Test("both placeholders resolve in one spawn, each from its own source")
    func bothPlaceholdersResolveTogether() async {
        let rendered = await ContentTemplate("# Events\n{{events}}\n\n# To do\n{{reminders}}")
            .render(
                at: spawn(),
                reading: DayData([
                    .events: ADayOfItems([DayItem(title: "Standup", time: at(9))]),
                    .reminders: ADayOfItems([DayItem(title: "Bread", time: at(18))]),
                ])
            )

        #expect(rendered == "# Events\n- 09:00 Standup\n\n# To do\n- [ ] 18:00 Bread")
    }

    // The whole point of the seam being asked about a *day*: a Monday filled
    // in on Wednesday gets Monday's meetings, not Wednesday's.
    @Test("the day read is the Entry's Journal Day, not the day of the spawn")
    func backfillReadsTheEntrysOwnDay() async {
        let calendar = ADayOfItems([])

        _ = await ContentTemplate("{{events}}").render(
            at: spawn(),
            reading: DayData([.events: calendar])
        )

        #expect(calendar.span?.start == instant(2026, 3, 1, 0, 0, in: paris))
        #expect(calendar.span?.end == instant(2026, 3, 2, 0, 0, in: paris))
    }

    @Test("a template that names no data placeholder reads nothing at all")
    func unnamedPlaceholdersAreNeverRead() async {
        let calendar = ADayOfItems([DayItem(title: "Standup", time: at(9))])

        let rendered = await ContentTemplate("# {{title}}\n{{reminders}}").render(
            at: spawn(),
            reading: DayData([.events: calendar, .reminders: ADayOfItems([])])
        )

        #expect(calendar.span == nil)
        #expect(rendered == "# 2026-03-01\n")
    }

    // Two calendars read one after the other is an Entry that waits twice for
    // a screen it is meant to appear on.
    @Test("the placeholders a template names are read at the same time")
    func placeholdersAreReadConcurrently() async {
        let bothArrived = Arrivals(expecting: 2)
        let template = ContentTemplate("{{events}}\n{{reminders}}")

        let rendered = await template.render(
            at: spawn(),
            reading: DayData([
                .events: ASourceThatWaits(
                    DayItem(title: "Standup"),
                    arrived: { bothArrived.arrive() },
                    letGo: { await bothArrived.everybody() }
                ),
                .reminders: ASourceThatWaits(
                    DayItem(title: "Bread"),
                    arrived: { bothArrived.arrive() },
                    letGo: { await bothArrived.everybody() }
                ),
            ])
        )

        // Reached at all only because neither source could finish until the
        // other had started: read one after the other, this deadlocks.
        #expect(rendered == "- Standup\n- [ ] Bread")
    }
}

@Suite("Data placeholders with nothing to say")
struct DataPlaceholderEmptyTests {
    @Test("a day with no items renders what the formatting settings say")
    func anEmptyDayRendersItsEmptyText() async {
        var formatting = DataPlaceholderFormatting.default
        formatting[.events].whenEmpty = "_nothing in the calendar_"

        let rendered = await ContentTemplate("## Today\n{{events}}\n").render(
            at: spawn(formatting),
            reading: DayData([.events: ADayOfItems([])])
        )

        #expect(rendered == "## Today\n_nothing in the calendar_\n")
    }

    @Test("an empty day leaves no debris by default, and the template stands")
    func anEmptyDayLeavesTheTemplateIntact() async {
        let rendered = await ContentTemplate("# {{title}}\n\n## Today\n{{events}}\n\n## Notes\n")
            .render(at: spawn(), reading: DayData([.events: ADayOfItems([])]))

        #expect(rendered == "# 2026-03-01\n\n## Today\n\n\n## Notes\n")
    }

    // The permission-denied case: the app's source answers with no items and
    // no error, so this is exactly the test above — which is the point. A
    // spawn cannot tell a calendar it may not read from a calendar with
    // nothing in it, and neither reaches the user as a failure.
    @Test("a source that cannot read anything renders empty and never fails")
    func aSourceWithNoAccessRendersEmpty() async {
        let denied = ADayOfItems([])

        let rendered = await ContentTemplate("{{events}}{{reminders}}").render(
            at: spawn(),
            reading: DayData([.events: denied, .reminders: denied])
        )

        #expect(rendered == "")
    }

    @Test("a placeholder with no source at all renders empty, like any unknown name")
    func aPlaceholderWithNoSourceRendersEmpty() async {
        var formatting = DataPlaceholderFormatting.default
        formatting[.reminders].whenEmpty = "_nothing to do_"

        let rendered = await ContentTemplate("a{{reminders}}b").render(
            at: spawn(formatting),
            reading: DayData([.events: ADayOfItems([])])
        )

        // Not "_nothing to do_": nothing was asked, so there is no day with
        // nothing in it to report.
        #expect(rendered == "ab")
    }

    @Test("with no sources installed at all, data placeholders render empty")
    func noSourcesAtAllRendersEmpty() async {
        let rendered = await ContentTemplate("{{events}}|{{reminders}}").render(
            at: spawn(),
            reading: DayData()
        )

        #expect(rendered == "|")
    }
}

@Suite("Data placeholders alongside the rest of the template")
struct DataPlaceholderCoexistenceTests {
    @Test("core and interactive placeholders are unaffected")
    func theOtherKindsAreUntouched() async {
        let rendered = await ContentTemplate("# {{title}} {{date}}\n{{events}}\n{{mood}}").render(
            at: spawn(),
            reading: DayData([.events: ADayOfItems([DayItem(title: "Standup", time: at(9))])])
        )

        #expect(rendered == "# 2026-03-01 2026-03-01\n- 09:00 Standup\n{{mood}}")
    }

    @Test("unknown placeholders still render empty")
    func unknownPlaceholdersStillRenderEmpty() async {
        let rendered = await ContentTemplate("a{{nonsense}}b").render(
            at: spawn(),
            reading: DayData([.events: ADayOfItems([DayItem(title: "Standup")])])
        )

        #expect(rendered == "ab")
    }

    // A data name is a bare name, like every name but `date` and `time`: an
    // offset or a `:FORMAT` on one is not a placeholder at all.
    @Test("a data placeholder carrying a format is not a placeholder")
    func aFormatOnADataNameRendersEmpty() async {
        let calendar = ADayOfItems([DayItem(title: "Standup")])
        let template = ContentTemplate("{{events:HH:mm}}{{events+1d}}")

        #expect(template.dataPlaceholders.isEmpty)
        #expect(await template.render(at: spawn(), reading: DayData([.events: calendar])) == "")
    }

    @Test("a template names the data placeholders it uses, bare ones only")
    func aTemplateNamesItsDataPlaceholders() {
        #expect(ContentTemplate("{{events}} {{events}}").dataPlaceholders == [.events])
        #expect(
            ContentTemplate("{{EVENTS}}\n{{ reminders }}").dataPlaceholders == [
                .events, .reminders,
            ]
        )
        #expect(ContentTemplate("# {{title}}\n{{mood}}").dataPlaceholders.isEmpty)
    }

    @Test("rendering without a day's data leaves data placeholders empty")
    func theSynchronousRenderResolvesNoData() {
        #expect(ContentTemplate("a{{events}}b").render(at: spawn()) == "ab")
    }
}

@Suite("Asking for what a data placeholder needs")
struct DataPlaceholderPreparationTests {
    @Test("only the placeholders a template names are asked for")
    func onlyTheNamedPlaceholdersArePrepared() async {
        let calendar = ADayOfItems([])
        let reminders = ADayOfItems([])
        let data = DayData([.events: calendar, .reminders: reminders])

        await data.prepare(for: ContentTemplate("{{events}}").dataPlaceholders)

        #expect(calendar.preparations == 1)
        #expect(reminders.preparations == 0)
    }

    @Test("asking twice is harmless, and asking for what is not there is too")
    func preparingIsRepeatableAndTotal() async {
        let calendar = ADayOfItems([])
        let data = DayData([.events: calendar])

        await data.prepare(for: [.events, .reminders])
        await data.prepare(for: [.events, .reminders])

        #expect(calendar.preparations == 2)
    }

    @Test("reading never asks — a spawn is never behind a permission prompt")
    func readingDoesNotPrepare() async {
        let calendar = ADayOfItems([DayItem(title: "Standup")])

        _ = await ContentTemplate("{{events}}").render(
            at: spawn(),
            reading: DayData([.events: calendar])
        )

        #expect(calendar.preparations == 0)
    }
}

@Suite("How a data placeholder's items are written")
struct DataPlaceholderFormatTests {
    private let items = [
        DayItem(title: "Standup", time: at(9, 30)),
        DayItem(title: "Bank holiday"),
    ]

    private func render(_ format: DataPlaceholderFormat) -> String {
        format.render(items, timeZone: paris, locale: english)
    }

    @Test("the line prefix is whatever the setting says")
    func theLinePrefixIsASetting() {
        #expect(render(DataPlaceholderFormat(linePrefix: "* ")).hasPrefix("* 09:30 Standup"))
        #expect(render(DataPlaceholderFormat(linePrefix: "")).hasPrefix("09:30 Standup"))
    }

    @Test("the time format is a Moment format, and no format leaves times out")
    func theTimeFormatIsASetting() {
        #expect(
            render(DataPlaceholderFormat(timeFormat: MomentFormat("h:mm a")))
                == "- 9:30 am Standup\n- Bank holiday"
        )
        #expect(
            render(DataPlaceholderFormat(timeFormat: nil))
                == "- Standup\n- Bank holiday"
        )
    }

    // An event whose title runs over a line would otherwise make two list
    // items out of one, the second of them not a list item at all.
    @Test("a title with a newline in it stays on its own line")
    func titlesAreFlattenedOntoOneLine() {
        let format = DataPlaceholderFormat(timeFormat: nil)
        let rendered = format.render(
            [DayItem(title: "Standup\n- and retro")],
            timeZone: paris,
            locale: english
        )

        #expect(rendered == "- Standup - and retro")
    }

    @Test("the items keep the order the source gave them")
    func orderIsTheSources() {
        let format = DataPlaceholderFormat(timeFormat: nil)
        let rendered = format.render(
            [DayItem(title: "Second", time: at(18)), DayItem(title: "First", time: at(9))],
            timeZone: paris,
            locale: english
        )

        #expect(rendered == "- Second\n- First")
    }

    @Test("times are read in the Entry's zone")
    func timesAreReadInTheEntrysZone() {
        let nine = DayItem(title: "Standup", time: at(9))
        let format = DataPlaceholderFormat()

        #expect(format.render([nine], timeZone: paris, locale: english) == "- 09:00 Standup")
        #expect(format.render([nine], timeZone: utc, locale: english) == "- 08:00 Standup")
    }

    @Test("the defaults are a list for events and a task list for reminders")
    func theDefaultsSayWhatEachKindIs() {
        for placeholder in DataPlaceholder.allCases {
            #expect(DataPlaceholderFormatting.default[placeholder] == .default(for: placeholder))
        }
        #expect(DataPlaceholderFormat.default(for: .events).linePrefix == "- ")
        #expect(DataPlaceholderFormat.default(for: .reminders).linePrefix == "- [ ] ")
    }

    @Test("a format written for one placeholder leaves the others at their defaults")
    func settingOnePlaceholderLeavesTheRest() {
        var formatting = DataPlaceholderFormatting.default
        formatting[.events].linePrefix = "* "

        #expect(formatting[.events].linePrefix == "* ")
        #expect(formatting[.reminders] == .default(for: .reminders))
        // And a format handed in is the same value as one set afterwards: two
        // of these are equal exactly when they would write a day alike.
        #expect(formatting == DataPlaceholderFormatting([.events: formatting[.events]]))
    }

    @Test("a done item takes the done marker, and events have nothing to say about it")
    func doneItemsTakeTheirOwnMarker() {
        let done = [DayItem(title: "Buy bread", isDone: true), DayItem(title: "Call back")]

        #expect(
            DataPlaceholderFormat.default(for: .reminders)
                .render(done, timeZone: paris, locale: english)
                == "- [x] Buy bread\n- [ ] Call back"
        )
        // An event is a thing that happened rather than a thing to do, so its
        // lines read the same either way.
        #expect(
            DataPlaceholderFormat.default(for: .events)
                .render(done, timeZone: paris, locale: english)
                == "- Buy bread\n- Call back"
        )
    }

    @Test("the day's items can be put in the order the day happened in")
    func itemsSortThroughTheDay() {
        let unordered = [
            DayItem(title: "All day"),
            DayItem(title: "Evening", time: at(18)),
            DayItem(title: "Morning", time: at(9)),
        ]

        #expect(unordered.throughTheDay().map(\.title) == ["Morning", "Evening", "All day"])
    }

    @Test("a nameless item is no item at all")
    func namelessItemsAreNotItems() {
        #expect(DayItem(named: nil) == nil)
        #expect(DayItem(named: "   \n ") == nil)
        // And a name with room around it is written without it.
        #expect(DayItem(named: "  Standup  ")?.title == "Standup")
    }
}

@Suite("The stretch of a day a data placeholder reads")
struct JournalDaySpanTests {
    @Test("a day runs from its own midnight to the next")
    func aDayIsMidnightToMidnight() {
        let span = march1.span(in: paris)

        #expect(span.start == instant(2026, 3, 1, 0, 0, in: paris))
        #expect(span.end == instant(2026, 3, 2, 0, 0, in: paris))
    }

    // Spring forward: 29 March 2026 is 23 hours long in Paris. Counting a day
    // as 86,400 seconds would run the span an hour into the 30th.
    @Test("a day that loses an hour to DST still ends at the next midnight")
    func aDstDayEndsWhereTheNextDayStarts() {
        let shortDay = JournalDay(year: 2026, month: 3, day: 29).span(in: paris)

        #expect(shortDay.end == instant(2026, 3, 30, 0, 0, in: paris))
        #expect(shortDay.duration == 23 * 3600)
    }

    // The Rollover Hour decides which day is being *written*, never what a day
    // *contains*: at 1 AM under a 4 AM rollover the Entry is the 1st's, and so
    // are the meetings in it.
    @Test("the span is the calendar date's, whatever the Rollover Hour is")
    func theSpanIgnoresTheRolloverHour() {
        let oneInTheMorning = instant(2026, 3, 2, 1, 0, in: paris)
        let day = JournalDay.current(at: oneInTheMorning, in: paris, rolloverHour: .init(hour: 4)!)

        #expect(day == march1)
        #expect(day.span(in: paris).start == instant(2026, 3, 1, 0, 0, in: paris))
    }
}

/// A meeting point: everybody waits until everybody has arrived.
private final class Arrivals: @unchecked Sendable {
    private let expected: Int
    private let lock = NSLock()
    private var arrived = 0

    init(expecting expected: Int) {
        self.expected = expected
    }

    func arrive() {
        lock.withLock { arrived += 1 }
    }

    /// Spins rather than signalling, because what is being proved is that two
    /// tasks are running at once — and a wait that could be satisfied by one
    /// of them proves nothing.
    func everybody() async {
        while lock.withLock({ arrived }) < expected {
            await Task.yield()
        }
    }
}
