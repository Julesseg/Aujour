import AujourCore
import SwiftUI
import UIKit

// The pieces both of Aujour's calendars are made of.
//
// There are two calendars: the month that grows out of the date pill on a
// narrow window, and the month that lives in the sidebar on a wide one
// (``JournalLayout``). What differs between them is geometry — one is clipped
// to however far a finger has pulled it open and the other is simply there —
// and what must not differ is a single thing a reader could read off a day. A
// journal whose Tuesdays were marked one way on a phone and another on an iPad
// would be two apps, so everything a reader reads lives here.
//
// The grid itself is not here, and that is not an oversight. The pill's is
// three pages laid side by side, slid up by whole rows and hit-tested against
// a ceiling that moves with a finger; the sidebar's is six rows. They draw the
// same cells and nothing else in common, and a shared grid would be one view
// with the pill's whole gesture as parameters.

/// One day in the grid, in whichever of its six states it is in.
///
/// Which state that is comes from ``DayCellLook``, which is a value and not a
/// pile of conditionals in a body: six states that have to stay six *different*
/// states is a thing to be able to measure.
struct DayCell: View {
    let day: JournalCalendar.Day
    let accent: Accent

    /// How tall a row is, which is also how wide a column is.
    let side: CGFloat

    let pick: () -> Void

    private var look: DayCellLook { DayCellLook(day, accent: accent) }

    var body: some View {
        Button(action: pick) {
            ZStack {
                RoundedRectangle(cornerRadius: Rounding.control, style: .continuous)
                    .fill(Color(look.fill))
                    // Square, and measured off whichever of the cell's two
                    // sides is shorter rather than off the row height — a
                    // fixed square in a column a seventh of the screen wide is
                    // a tint that spills onto the day beside it.
                    .aspectRatio(1, contentMode: .fit)
                    .padding(Spacing.tight)
                VStack(spacing: 2) {
                    Text(day.day.day.formatted(.number.grouping(.never)))
                        .lettering(.rowValue)
                        .foregroundStyle(Color(look.numeral))
                        // Scaled down rather than let out sideways: seven
                        // columns is seven columns, and a number that grew past
                        // its own cell would land on the day next to it.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    // Always laid out and shown only when the day has a file: a
                    // dot that took up no room when it was absent would move
                    // every other number in the row.
                    Circle()
                        .fill(look.dot.map(Color.init) ?? .clear)
                        .frame(width: 4, height: 4)
                        .opacity(0.7)
                }
            }
            .opacity(look.dimmed ? 0.4 : 1)
            .frame(maxWidth: .infinity, minHeight: side)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Visible and not writable: the day is on the calendar, and there is
        // no Entry to write before it has arrived.
        .disabled(!day.isOpenable)
        .accessibilityIdentifier("day-\(day.day)")
        .accessibilityLabel(day.day.spelledOut(withYear: true))
        .accessibilityValue(day.isJournaled ? "Written" : "Not written")
        .accessibilityAddTraits(day.isBeingWritten ? [.isSelected] : [])
    }
}

/// How a day in the grid is drawn: the tint under it, the colour of its
/// number, the mark that says it was written on, and whether the whole cell is
/// turned down because the day belongs to the month next door.
///
/// A value rather than four computed properties on a view, because the thing
/// worth holding this to is that the six states are six states — that no two of
/// them come out looking the same on any accent, in either appearance — and
/// that is a measurement, not a screenshot.
struct DayCellLook: Equatable {
    /// The tint under the number.
    let fill: UIColor

    /// What the number is written in.
    let numeral: UIColor

    /// The mark that says this day has an Entry, or `nil` where there is none
    /// to make — including on the day being written, whose fill already says
    /// more than a dot could.
    let dot: UIColor?

    /// Whether the cell is turned down as a whole: a day from the month either
    /// side of the one on screen, on the grid to keep the weeks whole.
    let dimmed: Bool

    init(_ day: JournalCalendar.Day, accent: Accent) {
        // In order, because the states overlap and the order is the answer:
        // the day being written is filled whether or not it is also today, and
        // today is tinted whether or not it was written on.
        fill =
            if day.isBeingWritten {
                accent.uiColor
            } else if day.relation == .current {
                accent.softColor
            } else if day.isJournaled {
                Palette.field
            } else {
                .clear
            }

        numeral =
            if day.isBeingWritten {
                // The paper, on a solid accent. Every accent is held to 4.5:1
                // against the page it is drawn on, and contrast does not care
                // which way round it is asked (ADR 0006).
                Palette.background
            } else if !day.isOpenable {
                Palette.inkFaint
            } else if day.relation == .current {
                // A word on a wash of its own accent, which is the one case
                // the accent alone cannot carry.
                accent.inkColor
            } else {
                Palette.ink
            }

        // The accent as it is, looked up rather than thinned into a colour of
        // its own: how strong the mark is drawn is the cell's business, and a
        // dynamic colour built afresh on every body is one SwiftUI cannot tell
        // has not changed (`Palette`).
        dot = day.isJournaled && !day.isBeingWritten ? accent.uiColor : nil
        dimmed = !day.isInTheMonthOnScreen
    }
}

/// The sentence under a month, on the two occasions there is one.
///
/// A grid with no marks on it is four different things (ADR 0001): a folder
/// nothing has looked in yet, a folder that would not answer, a month a
/// journal does not reach into, and a journal nobody has written in.
/// ``JournalCalendar`` tells them apart; only two of them are worth saying
/// anything about.
///
/// A month a journal does not reach into is not one of them. It is an ordinary
/// gap — August was quiet — and the grid has already said so by having no
/// marks on it; a line underneath explaining the same thing in words is the app
/// narrating what the reader is looking at. Nor is a folder nobody has read
/// yet, which knows nothing and so says nothing.
///
/// A line and not a page. On the screen this came off it could be a
/// `ContentUnavailableView` with room around it, and on a pane of glass an inch
/// tall it cannot — but the beginning of a journal is worth a sentence wherever
/// it is said, because the grid *is* the way in and somebody who has just
/// installed the app has no reason to know that.
///
/// One view for both calendars: what a grid cannot say for itself does not
/// depend on how wide the window it is in happens to be.
struct TheGridsOwnSentence: View {
    let calendar: JournalCalendar

    /// Whether there is a sentence at all — asked before one is built, because
    /// the pill has to open far enough to hold whatever this comes out as.
    static func isThereOne(for calendar: JournalCalendar) -> Bool {
        calendar.problem != nil || calendar.theJournalIsAtItsBeginning
    }

    var body: some View {
        sentence
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Spacing.comfortable)
            .padding(.vertical, Spacing.close)
    }

    @ViewBuilder private var sentence: some View {
        if let problem = calendar.problem {
            // Said rather than swallowed. A folder that would not answer gives
            // a month with no marks on it, which is exactly what a journal
            // nobody has written in looks like.
            //
            // In the system's own face and at the size of a note, which is
            // what keeps it from reading as the sentence below it: a folder
            // that would not answer is not an Empty State, and the identity
            // arriving on this panel is not licence to start drawing the two
            // the same way (`CONTEXT.md`, Empty State).
            Text("Aujour couldn't read your folder, so days you've written may not be marked.")
                .lettering(.note)
                .foregroundStyle(Palette.inkMutedColor)
                .accessibilityIdentifier("indicatorsProblem")
                .accessibilityLabel(StorageProblem(problem).message)
        } else if calendar.theJournalIsAtItsBeginning {
            // The Empty State, in the identity's own aside — the same quiet
            // prose voice the other two are said in, cut down to a line
            // because this one is said on an inch of glass rather than on a
            // page of its own.
            //
            // The muted step and not the faint one it used to be drawn in.
            // This is a sentence, and the faint ink is held to the marker
            // floor (ADR 0006, and ``Palette/inkFaint``).
            Text("Your journal starts here. Tap any day up to today and write it.")
                .lettering(.aside)
                .foregroundStyle(Palette.inkMutedColor)
                .accessibilityIdentifier("aJournalNobodyHasWrittenIn")
        }
    }
}

/// The column headings over a month: the weekday initials, from the day the
/// reader's own week starts on.
///
/// One view for both calendars because it is the same seven letters said the
/// same way, and because getting them out of a `ForEach` right has one trap in
/// it: a week has two days with the same initial in most languages, so they are
/// identified by where they sit and never by what they say.
///
/// - Parameter height: how tall the row is. Handed in rather than owned,
///   because the pill does arithmetic with this number — how far its panel
///   opens and which rows of the grid a finger can reach are both worked out
///   from it — and a height only this view knew would be a height the pill
///   could not ask about.
struct WeekdayNames: View {
    let month: JournalCalendar.Month
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(month.weekdayNames.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .lettering(.marker)
                    .foregroundStyle(Palette.inkFaintColor)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.close)
        .frame(height: height)
    }
}

/// The way back to today, offered only when the journal is not on it.
///
/// One control and one view, whichever calendar is drawing it. There is one
/// way back to today in Aujour, and which presentation a reader happens to be
/// in is not something they — or a test — should have to know to find it.
///
/// With an arrow on it, because a chip reading "Today" beside a date that is
/// *not* today reads as a label on the date — a badge saying this is the
/// current day — rather than as the way back to it. The arrow is what says the
/// chip goes somewhere, and it points the way it travels: no day past today can
/// be picked, so the journey back is always forwards.
struct BackToToday: View {
    let calendar: JournalCalendar
    let accent: Accent

    /// What going back does. The pick is the same on both calendars; what
    /// differs is what else the tap has to put away, which on a narrow window
    /// is the month it was tapped in.
    let goBack: () -> Void

    var body: some View {
        if !calendar.isOnToday {
            Button(action: goBack) {
                Label("Today", systemImage: "arrow.uturn.forward")
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
            }
            .lettering(.chipLabel)
            .foregroundStyle(accent.ink)
            .padding(.horizontal, Spacing.comfortable)
            .padding(.vertical, Spacing.tight)
            .background(accent.soft, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier("backToToday")
            .accessibilityLabel("Today")
        }
    }
}
