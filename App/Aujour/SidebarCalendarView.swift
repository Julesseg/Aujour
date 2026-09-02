import AujourCore
import SwiftUI

/// The month, down the side of a window wide enough to hold it and a page of
/// words at once (``JournalLayout``).
///
/// The date pill with the gesture taken out, and nothing else: the same pane
/// of glass, the same day named across the top, the same month grid under it,
/// at the same width the pill opens to. On a narrow window that pane is
/// somewhere a finger has to pull the month out of and put it back, because
/// the room it needs is the room the day's words are using; here there is room
/// for both at once, so it is simply out — no progress, no chevron, nothing to
/// open and nothing to shut.
///
/// Which is why it is not a second design. A reader who turns their iPad on
/// its side should recognise what arrives rather than learn it: what changed
/// is that the calendar stopped being somewhere to go and started being
/// somewhere to look, and every other thing about it is the same thing.
///
/// It holds no more rules than the pill does. Which days are marked, which is
/// today, which can be picked at all and which day the app is on are
/// ``JournalCalendar``'s.
struct SidebarCalendarView: View {
    let calendar: JournalCalendar

    /// The colour this device chose, handed down for the same reason the pill
    /// is handed it: a cell needs the accent, its wash and the shade a word
    /// takes on that wash, which are three colours and one decision (ADR 0006).
    let accent: Accent

    /// What picking a day does. The sidebar does not open Entries — it says
    /// which day was chosen, and the page beside it is the one that is over a
    /// day.
    let pick: (JournalDay) -> Void

    /// What has to be written down before the folder is read.
    ///
    /// The marks are a scan of the folder and nothing else (ADR 0001), so a
    /// day being written this second is a day with no file yet. The pill
    /// settles the page under it at the moment it is opened; this is never
    /// opened, so it settles the page beside it on the way in.
    let settleTheDayOnScreen: () async -> Void

    /// How tall a row is, and so how wide a column is.
    ///
    /// The pill's own number, because this is the pill: a day is the same size
    /// to aim a finger at whichever calendar it is on.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

    /// How tall the row of weekday initials is, and how tall the month's own
    /// row is — the pill's numbers again, for the same reason.
    @ScaledMetric(relativeTo: .caption2) private var weekdayHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var monthRowHeight: CGFloat = 34

    /// How wide the pane is: seven columns as wide as a row is tall, plus the
    /// inset the grid sits in.
    ///
    /// The width the pill opens to, arrived at the same way and for the same
    /// reason — past a square column every extra point goes into the gaps
    /// between the days and none of it into the days, and a month with a
    /// hand's width between its Tuesdays reads as seven numbers rather than as
    /// a week.
    private var paneWidth: CGFloat { rowHeight * 7 + Spacing.close * 2 }

    /// The corner the glass has, which is a pill's: a capsule 44 points tall
    /// is a 22-point corner, and the identity keeps it as the pane grows
    /// rather than squaring off into a card (`Metrics`).
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: rowHeight / 2, style: .continuous)
    }

    var body: some View {
        // Scrolls only where it has to, which at the reader's own text size is
        // never: a header, a month's name, six weeks of a bounded row and
        // sometimes a sentence, which fits on any window wide enough to have a
        // sidebar at all. What it is here for is the far end of Dynamic Type —
        // a calendar with its last week off the bottom of the screen is a
        // calendar somebody cannot reach December in.
        ScrollView {
            pane
                .padding(.horizontal, Spacing.apart)
                .padding(.top, Spacing.close)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: paneWidth + Spacing.apart * 2)
        // The month being written, whenever the journal moves to another one:
        // a day picked out of the grid, an app left open across the rollover.
        // The pill does this when it is opened, which is a moment this
        // calendar does not have.
        .onChange(of: calendar.dayBeingWritten, initial: true) { _, _ in
            calendar.showTheMonthBeingWritten()
        }
        // And reads the folder once, on the way in. The pill gets a reading
        // every time it is pulled open; a calendar nobody opens has to ask for
        // one — but only for the marks it comes up with, because every move
        // after that already writes the day down and reads the folder again as
        // part of moving. A scan per day change here would be the same scan a
        // second time.
        .task {
            await settleTheDayOnScreen()
            await calendar.scan()
        }
    }

    /// The pane itself: the day, the month, and the grid under them.
    ///
    /// The system's own glass, exactly as the pill is drawn in it. What the
    /// palette has is an *account* of glass, kept for the grounds a contrast
    /// floor is measured against; a pane floating beside a page of somebody's
    /// writing should be the real thing — it refracts what is behind it,
    /// lights its own edge against it, and answers Reduce Transparency without
    /// being asked.
    private var pane: some View {
        VStack(spacing: 0) {
            header
            monthRow
            WeekdayNames(month: calendar.month, height: weekdayHeight)
            grid
            TheGridsOwnSentence(calendar: calendar)
        }
        .frame(width: paneWidth)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
    }

    /// The day being written, across the top — and the way back to today
    /// beside it on every day but today's.
    ///
    /// The pill's header without its chevron, which is the whole of what
    /// "does not collapse" comes to on screen. A chevron says how far open a
    /// thing is and offers to change it, and there is nothing here to change.
    private var header: some View {
        HStack(spacing: Spacing.close) {
            BackToToday(calendar: calendar, accent: accent) { pick(calendar.today) }
            Text(dayBeingWritten)
                .lettering(.dayOnScreen)
                .foregroundStyle(Palette.inkColor)
                // One line, shrunk a little before it truncates, exactly as
                // the pill sets it: the header is one row tall at every text
                // size, and a date that wrapped to two would push the month
                // down the pane.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("sidebarDay")
        }
        .padding(.horizontal, Spacing.comfortable)
        .frame(height: rowHeight)
    }

    /// The day named on the pane — with its year only when that is news, since
    /// the journal can be left on a day years back and every February has a
    /// 14th.
    private var dayBeingWritten: String {
        let day = calendar.dayBeingWritten
        return day.spelledOut(withYear: day.year != calendar.today.year)
    }

    /// The month, with a step either side of it.
    ///
    /// The chevrons and not a gesture: there is no pulling this open, so
    /// nothing has claimed the finger, and a pair of buttons is what a
    /// calendar with room for them should have.
    private var monthRow: some View {
        HStack(spacing: 0) {
            Button("Previous month", systemImage: "chevron.left") {
                calendar.showPreviousMonth()
            }
            .frame(width: rowHeight)
            .contentShape(.rect)
            .accessibilityIdentifier("sidebarPreviousMonth")

            Spacer(minLength: 0)

            Text(calendar.month.name)
                .lettering(.sectionHeader)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("sidebarMonth")

            Spacer(minLength: 0)

            Button("Next month", systemImage: "chevron.right") {
                calendar.showNextMonth()
            }
            .frame(width: rowHeight)
            .contentShape(.rect)
            .accessibilityIdentifier("sidebarNextMonth")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Palette.inkFaintColor)
        .padding(.horizontal, Spacing.comfortable)
        .frame(height: monthRowHeight)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(Array(calendar.month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    // Identified by the place in the grid rather than by the
                    // day, so that a scan arriving changes what a cell says
                    // and never which cell it is.
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        DayCell(day: day, accent: accent, side: rowHeight) { pick(day.day) }
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .padding(.horizontal, Spacing.close)
    }
}

#Preview("The sidebar, beside a page") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let written = [today.adding(days: -1), today.adding(days: -3), today.adding(days: -8)]
    let calendar = JournalCalendar(
        store: InMemoryJournalStore(
            Dictionary(
                uniqueKeysWithValues: written.map { (PathTemplate.default.render($0), "Words.\n") }
            )
        )
    )

    HStack(spacing: 0) {
        SidebarCalendarView(
            calendar: calendar,
            accent: .driftwood,
            pick: { calendar.pick($0) },
            settleTheDayOnScreen: {}
        )
        Text(String(repeating: "Words on the page. ", count: 60))
            .lettering(.prose)
            .padding(Spacing.apart)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .background(Palette.backgroundColor)
}
