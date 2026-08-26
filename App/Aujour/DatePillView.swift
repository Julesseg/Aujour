import AujourCore
import SwiftUI

/// The header of the app: a pane of glass that says which day is open, and
/// grows downward into the week around it and then into the whole month.
///
/// One container and not three views. The week strip is the month grid slid up
/// until the week being written sits under the weekday names, so nothing
/// cross-fades and the same cells travel the whole way — which is what lets a
/// finger stop halfway and turn back. How far open it is is ``DatePill``'s;
/// every number here is that one number lerped into a height, a width or an
/// angle.
///
/// The view holds no rules. Which days are marked, which is today, which can
/// be picked at all and which day the app is on are ``JournalCalendar``'s.
struct DatePillView: View {
    let calendar: JournalCalendar

    /// The colour this device chose. Handed down rather than read from the
    /// environment: the accent is a Device Setting, the screen above already
    /// has it, and the tint alone would not do — a cell needs the accent, its
    /// wash and the shade a word takes on that wash, which are three colours
    /// and one decision (ADR 0006).
    let accent: Accent

    /// What picking a day does. The pill does not open Entries — it says which
    /// day was chosen, and the screen behind it is the one that is over a day.
    let pick: (JournalDay) -> Void

    @State private var pill = DatePill()

    /// How wide the pill is when it is only the pill — measured rather than
    /// guessed, because it is a sentence in the reader's language at the
    /// reader's text size, and a number typed in here would be right in
    /// English at the factory setting and wrong everywhere else.
    @State private var closedWidth: CGFloat = 0

    /// How much width there is to grow into.
    @State private var roomToOpenInto: CGFloat = 0

    // The grid's geometry, which is arithmetic and so has to be numbers rather
    // than whatever SwiftUI would have laid out: the panel's height, the
    // distance the grid slides and the width the glass grows to are all read
    // off these, at every frame of a drag.
    @ScaledMetric(relativeTo: .body) private var pillHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption2) private var weekdayHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var monthRowHeight: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header
            panel
        }
        .frame(width: width)
        .background(glass, in: shape)
        .overlay(shape.strokeBorder(Palette.glassRingColor, lineWidth: 0.5))
        .clipShape(shape)
        .elevated(.floating)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { roomProbe }
        // While a finger is on it there is nothing to animate: the pill is
        // wherever the finger left it. The spring is only for the settling.
        .animation(pill.isBeingDragged ? nil : settle, value: pill.progress)
        // Opening puts the month being written back on screen, whatever month
        // was browsed to last time it was open. Straight away and not in a
        // task, so the grid is the right month in the first frame of the
        // opening rather than in the second.
        .onChange(of: pill.detent == .closed) { _, isClosed in
            guard !isClosed else { return }
            calendar.showTheMonthBeingWritten()
        }
        // And reads the folder, because the marks are a scan of it and nothing
        // else (ADR 0001). Keyed on whether it is open rather than on which
        // state it is in, so a drag from shut to the month is one reading and
        // not two — and a finger that wavers over the halfway mark cancels the
        // reading it started rather than stacking another on it.
        .task(id: pill.detent == .closed) {
            guard pill.detent != .closed else { return }
            await calendar.scan()
        }
    }

    // MARK: - The pill itself

    private var header: some View {
        headerContent
            .contentShape(.rect)
            // One gesture for both, which is why `minimumDistance` is zero: a
            // tap and a drag arrive as the same finger, and two gestures
            // competing over it is how a pill ends up ignoring one of them.
            // Which one it was is `DatePill`'s to say.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { pill.dragged(by: $0.translation.height) }
                    .onEnded { pill.letGo(afterMoving: $0.translation.height) }
            )
            // Measured and not drawn: the same row at its own natural width,
            // which is what the pill shrinks back to.
            .background(alignment: .center) {
                headerContent
                    .fixedSize()
                    .hidden()
                    // Twice over, because this copy carries the pill's own
                    // identifiers and the way back to today: a second
                    // `backToToday` behind the first is a button a finger
                    // cannot reach and a test cannot tell from the real one.
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        closedWidth = $0
                    }
            }
    }

    private var headerContent: some View {
        HStack(spacing: Spacing.close) {
            if !calendar.isOnToday {
                todayChip
            }
            theDayAndTheChevron
        }
        .padding(.horizontal, Spacing.comfortable)
        .frame(height: pillHeight)
    }

    /// The pill proper: the day, and the chevron that says how far open it is.
    ///
    /// One accessibility element and not two, with the state it is in as its
    /// *value* — because that is what it is. A control with three states that
    /// announced only its name would leave a reader who cannot see the chevron
    /// tapping it to find out where they had got to.
    private var theDayAndTheChevron: some View {
        HStack(spacing: Spacing.close) {
            Text(dayBeingWritten)
                .lettering(.dayOnScreen)
                .foregroundStyle(Palette.inkColor)
                // One line, and shrunk a little before it truncates — the way
                // an inline navigation title behaves, and for the same reason:
                // the room left for the pill over a day's words is one row,
                // and a date that wrapped to two would be a pill sitting on
                // the first line of the entry. It still grows with Dynamic
                // Type; what it will not do is grow *taller*.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkFaintColor)
                // Down when it is shut, out to the side halfway, up when the
                // month is out: one sweep across the whole travel, so the
                // chevron says where in the gesture the finger is and not
                // merely which of three states it ended in.
                .rotationEffect(.degrees(-90 * pill.progress))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("datePill")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(dayBeingWritten)
        .accessibilityValue(howOpenItIs)
        .accessibilityHint(whatATapWouldDo)
    }

    /// How far open the pill is, said in a word.
    private var howOpenItIs: String {
        switch pill.detent {
        case .closed: "Closed"
        case .week: "Week"
        case .month: "Month"
        }
    }

    private var whatATapWouldDo: String {
        switch pill.detent {
        case .closed: "Shows the week around this day"
        case .week: "Shows the whole month"
        case .month: "Closes the calendar"
        }
    }

    /// The way back to today, offered only when the app is not on it.
    private var todayChip: some View {
        Button("Today") {
            pick(calendar.today)
            pill.close()
        }
        .lettering(.chipLabel)
        .foregroundStyle(accent.ink)
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.tight)
        .background(accent.soft, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityIdentifier("backToToday")
    }

    /// The day named on the pill — with its year only when that is news, since
    /// the pill can be left on a day years back and every February has a 14th.
    private var dayBeingWritten: String {
        let day = calendar.dayBeingWritten
        return day.spelledOut(withYear: day.year != calendar.today.year)
    }

    // MARK: - The panel that grows out of it

    /// The grid, its weekday names and the month over them, clipped to
    /// whatever height the pill is currently open to.
    ///
    /// The whole of it is laid out at full height at every moment and the
    /// clipping is what hides the rest, so a cell never changes size, never
    /// re-lays out, and travels rather than appears.
    private var panel: some View {
        VStack(spacing: 0) {
            monthRow
            weekdayNames
            grid
        }
        // Pulled up by the month row's height until the month is nearly out,
        // so that in the week strip the weekday names sit at the top of the
        // panel and the month name is above the ceiling rather than in the way.
        .offset(y: -monthRowHeight * (1 - pill.spread))
        .frame(height: panelHeight, alignment: .top)
        .clipped()
        .opacity(min(pill.progress * 2.2, 1))
        // A shut pill is not a calendar with the lights off: nothing in here
        // is reachable by a finger or by VoiceOver until it is open.
        .allowsHitTesting(pill.detent != .closed)
        .accessibilityHidden(pill.detent == .closed)
    }

    private var monthRow: some View {
        HStack(spacing: 0) {
            Button("Previous month", systemImage: "chevron.left") {
                calendar.showPreviousMonth()
            }
            .frame(width: pillHeight)
            .contentShape(.rect)
            .accessibilityIdentifier("pillPreviousMonth")

            Spacer(minLength: 0)

            Text(calendar.month.name)
                .lettering(.sectionHeader)
                .accessibilityIdentifier("pillMonth")

            Spacer(minLength: 0)

            Button("Next month", systemImage: "chevron.right") {
                calendar.showNextMonth()
            }
            .frame(width: pillHeight)
            .contentShape(.rect)
            .accessibilityIdentifier("pillNextMonth")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Palette.inkFaintColor)
        .padding(.horizontal, Spacing.comfortable)
        .frame(height: monthRowHeight)
        // Only once the month is nearly all the way out: it names the grid,
        // and there is no grid to name until there is more than one week of it.
        .opacity(min(max((pill.progress - 1.45) * 3, 0), 1))
    }

    private var weekdayNames: some View {
        HStack(spacing: 0) {
            // By offset, because a week has two days with the same initial in
            // most languages and `id: \.self` would collapse them.
            ForEach(Array(calendar.month.weekdayNames.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .lettering(.marker)
                    .foregroundStyle(Palette.inkFaintColor)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.close)
        .frame(height: weekdayHeight)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(Array(calendar.month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    // Identified by the place in the grid rather than by the
                    // day, so that a scan arriving mid-drag changes what a cell
                    // says and never which cell it is.
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        DayCell(day: day, accent: accent, side: rowHeight) { pickAndClose(day.day) }
                    }
                }
                .frame(height: rowHeight)
            }
        }
        // Slid up by whole rows until the week being written is under the
        // weekday names, and back down as the month comes out. This is the
        // week strip: there is no second view of one.
        .offset(y: gridSlide)
        .frame(height: CGFloat(calendar.month.weeks.count) * rowHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, Spacing.close)
    }

    private func pickAndClose(_ day: JournalDay) {
        pick(day)
        pill.close()
    }

    // MARK: - The geometry, read off how far open it is

    /// How tall a row of the grid is — and how wide a column is, which is the
    /// same number until they disagree.
    ///
    /// The one place in the app where Dynamic Type is bounded rather than
    /// followed, and it is bounded by arithmetic and not by taste: a month is
    /// seven columns across whatever the reader's text size, so a column is a
    /// seventh of the room and no more. A row that went on growing past that
    /// would be a grid of tall thin cells that ran off the bottom of the
    /// screen while the numbers in them sat in the middle of nowhere.
    ///
    /// What still grows is everything the reader actually reads: the day named
    /// on the pill, the month over the grid, the weekday initials. Inside a
    /// cell the number is scaled down to fit rather than allowed to spill into
    /// the day beside it.
    private var rowHeight: CGFloat {
        let column = max(0, roomToOpenInto - Spacing.close * 2) / 7
        return column > 0 ? min(pillHeight, column) : pillHeight
    }

    private var panelHeight: CGFloat {
        let week = weekdayHeight + rowHeight
        let month = monthRowHeight + weekdayHeight
            + CGFloat(calendar.month.weeks.count) * rowHeight
        return pill.spread > 0
            ? week + (month - week) * pill.spread
            : week * pill.openness
    }

    private var gridSlide: CGFloat {
        let row = CGFloat(calendar.month.weekBeingWritten ?? 0)
        // Nought at both ends and a whole row's travel at the week strip in
        // between, which is the same thing said forwards and then backwards.
        return -row * rowHeight * (pill.openness - pill.spread)
    }

    private var width: CGFloat {
        // Before either has been measured there is nothing to be wide, and on
        // a text size where the day's name alone is wider than the screen
        // there is nothing to grow into — so the pill is simply the room it
        // has, at every state.
        guard roomToOpenInto > 0 else { return closedWidth }
        guard closedWidth > 0, closedWidth < roomToOpenInto else { return roomToOpenInto }
        return closedWidth + (roomToOpenInto - closedWidth) * pill.openness
    }

    private var shape: RoundedRectangle {
        // The corner a pill has, kept as the panel grows: a capsule 44 points
        // tall is a 22-point corner, and the identity's glass keeps it rather
        // than squaring off into a card (`Metrics`).
        RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous)
    }

    private var glass: Color {
        reduceTransparency ? Palette.glassSolidColor : Palette.glassColor
    }

    /// What it does when it is let go: the identity's own settle, or a plain
    /// short fade for a reader who asked for less movement.
    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(stiffness: 320, damping: 30)
    }

    private var roomProbe: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomToOpenInto = $0 }
    }
}

extension View {
    /// Puts the date pill over a day's Entry.
    ///
    /// Over and not above: the pill is glass, and what is behind it should be
    /// legible as *being* behind it. The inset is the room the shut pill needs
    /// so that the first line of the day is not under it; everything the pill
    /// grows into is drawn over the words, which is what lets a month open
    /// without a day's writing jumping down the screen.
    ///
    /// A modifier because the pill belongs to whichever day is on screen and
    /// the screen it is on is one `switch` deep, and because a calendar the
    /// journal has not opened yet is a day with no pill rather than a pill with
    /// no days.
    func datePill(
        over calendar: JournalCalendar?,
        accent: Accent,
        pick: @escaping (JournalDay) -> Void
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if calendar != nil {
                RoomForTheShutPill()
            }
        }
        .overlay(alignment: .top) {
            if let calendar {
                DatePillView(calendar: calendar, accent: accent, pick: pick)
                    .padding(.horizontal, Spacing.apart)
                    .padding(.top, Spacing.close)
            }
        }
    }
}

/// The room a day's words leave for the shut pill above them.
///
/// The shut pill's own height and not the open one's: what the pill grows into
/// is drawn *over* the words, so an inset that followed it would push a day's
/// writing down the screen every time somebody opened the month.
///
/// A view of its own so that it can hold the same `@ScaledMetric` the pill's
/// rows do — the pill is one row tall at every text size, and a fixed number
/// here would be a pill sitting on the first line of the entry for anybody who
/// had turned the text up.
private struct RoomForTheShutPill: View {
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

    var body: some View {
        Color.clear.frame(height: rowHeight + Spacing.close * 2)
    }
}

/// One day in the grid, in whichever of its six states it is in.
///
/// Which state that is comes from ``DayCellLook``, which is a value and not a
/// pile of conditionals in a body: six states that have to stay six *different*
/// states is a thing to be able to measure.
private struct DayCell: View {
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

// Previews journal into memory, so the month on screen is the one the preview
// is named after rather than whatever this Mac's journal folder holds.
@MainActor private func previewCalendar() -> JournalCalendar {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let written = [today.adding(days: -1), today.adding(days: -3), today.adding(days: -8)]
    let calendar = JournalCalendar(
        store: InMemoryJournalStore(
            Dictionary(
                uniqueKeysWithValues: written.map { (PathTemplate.default.render($0), "Words.\n") }
            )
        )
    )
    Task { await calendar.scan() }
    return calendar
}

#Preview("Closed, on today") {
    DatePillView(calendar: previewCalendar(), accent: .driftwood) { _ in }
        .padding(.horizontal, Spacing.apart)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.backgroundColor)
}

#Preview("Over a page of words") {
    let calendar = previewCalendar()
    ScrollView {
        Text(String(repeating: "Words on the page, behind the glass. ", count: 60))
            .lettering(.prose)
            .padding(Spacing.apart)
    }
    .datePill(over: calendar, accent: .driftwood) { calendar.pick($0) }
    .background(Palette.backgroundColor)
}
