import AujourCore
import SwiftUI

/// The month, down the side of a window wide enough to hold it and a page of
/// words at once (``JournalLayout``).
///
/// The same calendar the date pill grows into, with the gesture taken out. On
/// a narrow window the month is somewhere a finger has to pull it out of and
/// put it back, because the room it needs is the room the day's words are
/// using; here there is room for both at once, so it is simply there — no
/// progress, no clipping, nothing to open and nothing to shut. What that buys
/// is the thing the pill cannot give: the day being written stays visible on
/// the grid while it is being written in.
///
/// It holds no more rules than the pill does. Which days are marked, which is
/// today, which can be picked at all and which day the app is on are
/// ``JournalCalendar``'s, and the cells are the same ``DayCell`` the pill
/// draws — a journal whose Tuesdays were marked one way on a phone and another
/// on an iPad would be two apps.
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
    /// opened, so it settles the page beside it whenever the day changes —
    /// which is the moment a day just written stops being the one on screen
    /// and starts being a day the grid has to mark.
    let settleTheDayOnScreen: () async -> Void

    /// How wide the column is.
    ///
    /// Wide enough that a day is a day-sized thing to aim a finger at — seven
    /// columns of this leave a cell of about forty points — and no wider:
    /// every point past that is taken off the page of words next door, which
    /// is what the whole layout is for. The narrowest window that gets a
    /// sidebar at all is ``JournalLayout/sidebarNeeds``, so this is also a
    /// promise about what is left over: five hundred points, which is a
    /// readable page in every face the editor offers.
    static let width: CGFloat = 320

    /// How tall a row is, and so how wide a column is.
    ///
    /// Bounded rather than followed, the same way the pill's is and for the
    /// same arithmetic: a month is seven columns across whatever the reader's
    /// text size, so a column is a seventh of the room and no more. What still
    /// grows is everything the reader actually reads — the month's name, the
    /// weekday initials — and inside a cell the number is scaled down to fit
    /// rather than allowed to spill into the day beside it.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

    /// How tall the row of weekday initials is — the pill's own number, so
    /// that one calendar's column headings are not a different size from the
    /// other's.
    @ScaledMetric(relativeTo: .caption2) private var weekdayHeight: CGFloat = 22

    /// How far in from the sidebar's edges the grid sits: the panel's own
    /// inset, and then the one the rows are laid out in.
    private static let inset = Spacing.close * 2

    /// How wide a column is: the room, less the inset at either end, over
    /// seven.
    private var side: CGFloat {
        let column = (Self.width - Self.inset * 2) / 7
        return min(rowHeight, column)
    }

    var body: some View {
        // Scrolls only where it has to, which at the reader's own text size is
        // never: six weeks of a bounded row plus a heading fits on any window
        // wide enough to have a sidebar at all. What it is here for is the far
        // end of Dynamic Type, where the month's name and the sentence under
        // the grid grow past the room — a calendar with its last week off the
        // bottom of the screen is a calendar somebody cannot reach December in.
        ScrollView {
            VStack(spacing: 0) {
                monthRow
                WeekdayNames(month: calendar.month, height: weekdayHeight)
                    .padding(.top, Spacing.close)
                grid
                // Under the grid and not beside the month's name. The row
                // above is already three things wide and a fourth would
                // squeeze the name it is there to carry — and a chip that
                // appeared *above* the grid would push every day of the month
                // down a line the moment somebody left today, which is a
                // calendar that moves under the finger picking from it.
                BackToToday(calendar: calendar, accent: accent) { pick(calendar.today) }
                    .padding(.top, Spacing.comfortable)
                TheGridsOwnSentence(calendar: calendar)
            }
            .padding(.horizontal, Spacing.close)
            .padding(.top, Spacing.close)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width)
        // The identity's own paper, against the page beside it. A calendar
        // that is always there is a panel and not a card: it is not floating
        // over anything and it casts nothing, so what separates it from the
        // day's words is a tone and a rule rather than a lift.
        .background(Palette.backgroundColor)
        // The month being written, whenever the journal moves to another one:
        // a day picked out of the grid, a swipe through the days, an app left
        // open across the rollover. The pill does this when it is opened,
        // which is a moment this calendar does not have.
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

    /// The month, with a step either side of it and the way back to today.
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
                .foregroundStyle(Palette.inkColor)
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
        .frame(height: rowHeight)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(Array(calendar.month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    // Identified by the place in the grid rather than by the
                    // day, so that a scan arriving changes what a cell says
                    // and never which cell it is.
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        DayCell(day: day, accent: accent, side: side) { pick(day.day) }
                    }
                }
                .frame(height: side)
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
        Divider()
        Text(String(repeating: "Words on the page. ", count: 60))
            .lettering(.prose)
            .padding(Spacing.apart)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .background(Palette.backgroundColor)
}
