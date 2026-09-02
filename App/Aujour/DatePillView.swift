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

    /// What walking the journal a day does, as a number of days: the day
    /// before is -1 and the day after is 1.
    ///
    /// Not `pick`, and the difference is the point. Picking is refused for a
    /// day that has not arrived, because a cell in the grid is the way *in* to
    /// writing a day and a locked one has to refuse where it cannot be tapped
    /// around. Walking is looking, so it reaches tomorrow and the screen
    /// behind puts up a page saying the day has not started.
    let turn: (Int) -> Void

    /// What has to be written down before the folder is read.
    ///
    /// The marks are a scan of the folder and nothing else (ADR 0001), so a
    /// day being written in this second is a day with no file yet — and a
    /// month opened over it would say, correctly and uselessly, that nothing
    /// had been written on it. The screen this came off saved the day it was
    /// leaving on the way in; the pill leaves nothing, so it settles what is
    /// underneath it instead.
    let settleTheDayOnScreen: () async -> Void

    /// How far open it is. Held above this view rather than inside it, because
    /// the rest of the screen is a way out of the pill and a state nothing
    /// else could reach would be a pill only the pill could shut.
    @Binding var pill: DatePill

    /// The sideways gesture on a shut pill, which walks the journal a day.
    ///
    /// Held here and not above, unlike how far open the pill is: nothing
    /// outside the glass is a way of walking a day, and this is back at nought
    /// by the time anything could ask it a question.
    @State private var swipe = DaySwipe()

    /// How wide the pill is when it is only the pill — measured rather than
    /// guessed, because it is a sentence in the reader's language at the
    /// reader's text size, and a number typed in here would be right in
    /// English at the factory setting and wrong everywhere else.
    @State private var closedWidth: CGFloat = 0

    /// How much width there is to grow into.
    @State private var roomToOpenInto: CGFloat = 0

    /// How tall the sentence under the grid is, when there is one — measured,
    /// because it is prose at the reader's own text size.
    @State private var noticeHeight: CGFloat = 0

    /// How far along the pages a finger has walked, in points: nought on the
    /// page being read, a page's width either side.
    ///
    /// Only the grid moves. The weekday names over it say the same thing in
    /// every week of every month, and a heading that slid with the days would
    /// be movement carrying no news; the month's name is not slid but swapped,
    /// at the moment the page it names is the nearer one.
    @State private var walked: CGFloat = 0

    // The grid's geometry, which is arithmetic and so has to be numbers rather
    // than whatever SwiftUI would have laid out: the panel's height, the
    // distance the grid slides and the width the glass grows to are all read
    // off these, at every frame of a drag.
    @ScaledMetric(relativeTo: .body) private var pillHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption2) private var weekdayHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var monthRowHeight: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            // Not built at all while it is shut, rather than built and hidden.
            // A shut pill is not a calendar with the lights off: the days of
            // the month are not there to be found by a finger, by VoiceOver or
            // by anything else until it has been opened.
            if pill.progress > 0 {
                panel
            }
        }
        .frame(width: width)
        .clipShape(shape)
        // The system's own glass, rather than the identity's fill, ring and
        // pair of shadows. What the palette has is an *account* of glass, kept
        // for the grounds a contrast floor is measured against; a pane that
        // floats over a page of somebody's writing should be the real thing —
        // it refracts what scrolls under it, lights its own edge against it,
        // and answers Reduce Transparency without being asked.
        .glassEffect(.regular, in: shape)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { roomProbe }
        .background(alignment: .top) { noticeProbe }
        // Leaning towards the day being asked for. The whole pane and not what
        // is written in it: the pill is sized to the day it names, so a name
        // slid inside it would be a name half under the glass's own edge,
        // while the pane has room either side to lean into.
        .offset(x: lean)
        // While a finger is on it there is nothing to animate: the pill is
        // wherever the finger left it. The spring is only for the settling.
        .animation(pill.isBeingDragged ? nil : settle, value: pill.progress)
        .animation(swipe.isBeingDragged ? nil : settle, value: lean)
        // And nothing at all when the day changes, which is a page being
        // turned behind this and not a thing happening to the pill. The pill
        // is as wide as the day it names, and that width is a measurement
        // taken a frame after the name it belongs to — so a spring hung on it
        // starts from the old day's geometry, and a page turn that carries an
        // ambient animation with it would pick up the same stale start. It
        // snaps to the new day's width instead, which is what a label doing
        // nothing but changing should do.
        .animation(nil, value: dayBeingWritten)
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
            await settleTheDayOnScreen()
            await calendar.scan()
        }
    }

    // MARK: - The pill itself

    private var header: some View {
        headerContent
            .contentShape(.rect)
            // One gesture for all three, which is why `minimumDistance` is
            // zero: a tap, a pull and a walk through the days arrive as the
            // same finger, and gestures competing over one finger is how a
            // pill ends up ignoring one of them. Which is also why the axis is
            // *declared* rather than read afresh each frame — a pull that
            // wandered a few points across must not both open the calendar and
            // change the day.
            //
            // Sideways is answered only while the pill is shut, and that is
            // the whole of the arrangement with the panel below. Open, the
            // pages are what a sideways finger moves and they carry a gesture
            // of their own; a header that walked the days as well would be a
            // second answer to the same finger, and one that merely leaned
            // would be the whole pane sliding while the grid inside it slid
            // the other way.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { finger in
                        swipe.dragged(
                            across: finger.translation.width,
                            down: finger.translation.height
                        )
                        // Sideways opens nothing, whether or not it will go on
                        // to move the journal: a shut pill leans towards the
                        // day being asked for and an open one does not stir.
                        guard swipe.axis != .sideways else { return }
                        pill.dragged(by: finger.translation.height)
                    }
                    .onEnded { finger in
                        guard swipe.axis != .sideways else {
                            let landing = swipe.letGo(
                                heading: finger.predictedEndTranslation.width
                            )
                            // Only a shut pill walks the days. Open, this is a
                            // finger on the header rather than on the pages,
                            // and the answer is nothing at all.
                            guard pill.detent == .closed else { return }
                            // And shut it stays: the few points before the
                            // axis was known went into the pill, and a walk
                            // that left it a fraction ajar would be a pill
                            // nobody had asked to open.
                            pill.close()
                            if landing != .whereItStarted { turn(landing.days) }
                            return
                        }
                        swipe.calledOff()
                        pill.letGo(afterMoving: finger.translation.height)
                    }
            )
            // Measured and not drawn: the same row at its own natural width,
            // which is what the pill shrinks back to.
            .background(alignment: .center) {
                headerContent
                    .fixedSize()
                    .hidden()
                    // Collapsed into one element and then hidden, rather than
                    // hidden alone. This copy carries the pill's own
                    // identifiers and the way back to today, and a second
                    // `backToToday` behind the first is a button a finger
                    // cannot reach and nothing else can tell from the real one
                    // — so the children are given up before the parent is put
                    // out of sight.
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        closedWidth = $0
                    }
            }
    }

    /// How far the pill leans towards the day being asked for.
    ///
    /// Nothing at all while it is open, and that is not thrift: an open pill
    /// is a pane the height of the screen with a grid in it that slides
    /// sideways on its own, and a pane leaning one way while its contents go
    /// the other is two answers to one finger.
    private var lean: CGFloat {
        pill.detent == .closed ? swipe.carried : 0
    }

    private var headerContent: some View {
        HStack(spacing: Spacing.close) {
            // And the month it was tapped in goes away with it: the day is
            // chosen, so the grid it was chosen from has nothing left to say.
            BackToToday(calendar: calendar, accent: accent) {
                pick(calendar.today)
                pill.close()
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
        // The way out that tapping the page is, for somebody who is not
        // aiming a finger at the page: an open pill is dismissible, and a
        // two-finger scrub is how that is said.
        .accessibilityAction(.escape) { pill.close() }
        // And the walk, as two named actions rather than as an adjustable
        // value. The pill's value is how far open it is, and a control that
        // announced "Closed" and then changed the day when it was adjusted
        // would be answering with one thing and moving another.
        .accessibilityAction(named: "Previous day") { turn(-1) }
        .accessibilityAction(named: "Next day") { turn(1) }
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
        case .month: "Shows the week around this day"
        }
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
            WeekdayNames(month: calendar.month, height: weekdayHeight)
            grid
            whatTheGridCannotSayForItself
        }
        // Pulled up by the month row's height until the month is nearly out,
        // so that in the week strip the weekday names sit at the top of the
        // panel and the month name is above the ceiling rather than in the way.
        .offset(y: -monthRowHeight * (1 - pill.spread))
        .frame(height: panelHeight, alignment: .top)
        .clipped()
        .opacity(min(pill.progress * 2.2, 1))
        // A tap anywhere on the grid is the grid's, even where there is
        // nothing on it to tap: the gap between two cells, and a day that has
        // not arrived. Without this both would fall through to the way out
        // behind the pill, and a finger aimed at a locked day would shut the
        // month it was aimed into.
        //
        // On the grid and not on the whole pill, because the row above it is
        // holding the one gesture that opens and closes this thing, and a
        // second gesture over the top of that one wins often enough to leave
        // the pill unopenable.
        .contentShape(.rect)
        .onTapGesture {}
        // Sideways is the other way through the calendar, and the one there is
        // no room on a strip to put a pair of chevrons for.
        //
        // Ahead of the day cells rather than beside them. A cell is a button,
        // and a button pressed and then dragged off still counts the press —
        // so a swipe that began on a Tuesday would pick that Tuesday and shut
        // the pill it was drawn across. Given the first claim on the finger,
        // this only takes it once the finger has travelled, which is exactly
        // the difference between choosing a day and walking past it.
        .highPriorityGesture(walkSideways)
        // The same journey for a reader who scrolls by gesture rather than by
        // finger, since the week strip has no control on it that does this.
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: walk(-1)
            case .trailing: walk(1)
            default: break
            }
        }
    }

    // MARK: - Walking the pages

    /// A finger drawn across the grid, carrying the page either side of this
    /// one into view and letting go on one of them.
    private var walkSideways: some Gesture {
        DragGesture(minimumDistance: Self.startsWalking)
            .onChanged { walked = followed($0) }
            .onEnded { land(after: $0) }
    }

    /// How far a finger has to travel before it is walking the pages rather
    /// than resting on a day.
    private static let startsWalking: CGFloat = 12

    /// How far along the pages the grid has been carried.
    ///
    /// Nought until the finger is going sideways more than it is going down,
    /// so that pulling the pill open along a slightly crooked line does not
    /// take the days with it — and so that a walk turned downward mid-gesture
    /// puts them back as it turns.
    ///
    /// And no further than the page waiting either side: there are three
    /// drawn and there is not a fourth, so a finger that could carry the grid
    /// past the last of them would be carrying it onto nothing.
    private func followed(_ finger: DragGesture.Value) -> CGFloat {
        let across = finger.translation.width
        guard abs(across) > abs(finger.translation.height) else { return 0 }
        return min(max(across, -pageWidth), pageWidth)
    }

    /// Lets go of the pages on one of them, and never between two.
    ///
    /// The step is taken when the page it was heading for has arrived, and
    /// that page becomes the middle one. Nothing moves as it does: what the
    /// calendar now shows is already what is under the finger, so putting the
    /// pages back where they started is a swap the eye cannot see.
    private func land(after finger: DragGesture.Value) {
        let page = pageItLandsOn(finger)
        // On the animation being *gone* and not on it being logically over: a
        // spring is logically over well before it has stopped moving, and the
        // swap has to happen at the moment the page is where it is going to
        // be. A frame early is the one thing that would show.
        withAnimation(snap, completionCriteria: .removed) {
            walked = -CGFloat(page) * pageWidth
        } completion: {
            if page != 0 { walk(page) }
            walked = 0
        }
    }

    /// Which page a finger has let go on.
    ///
    /// Read off where the finger was *going* and not merely where it got to,
    /// so that a flick turns the page rather than needing to drag a third of
    /// one out — which is what makes this a scroll rather than a threshold
    /// somebody has to find.
    private func pageItLandsOn(_ finger: DragGesture.Value) -> Int {
        let heading = finger.predictedEndTranslation.width
        let across = abs(heading) > abs(finger.translation.width)
            ? heading
            : finger.translation.width
        // A finger on its way up to shut the pill passes over the grid, and a
        // gesture that took every diagonal for a walk would turn the page on
        // the way out.
        guard abs(across) > abs(finger.translation.height) else { return 0 }
        guard abs(across) > Self.turnsThePage(of: pageWidth) else { return 0 }
        return across < 0 ? 1 : -1
    }

    /// How far a finger has to be going to turn a page of a given width.
    ///
    /// A third of it, and never more than a good push. A proportion alone is
    /// right on a phone and wrong on a pill that runs the width of an iPad,
    /// where a third of a page is most of a hand's reach — and the question a
    /// walk asks is whether the finger meant it, which is a distance and a
    /// flick rather than a fraction of however wide the glass happens to be.
    private static func turnsThePage(of width: CGFloat) -> CGFloat {
        min(width / 3, 120)
    }

    /// One step through the calendar, in whichever unit is on screen: the
    /// month when the month is out, and otherwise the week.
    private func walk(_ steps: Int) {
        switch (pill.detent, steps) {
        case (.month, 1...): calendar.showNextMonth()
        case (.month, _): calendar.showPreviousMonth()
        case (_, 1...): calendar.showNextWeek()
        case (_, _): calendar.showPreviousWeek()
        }
    }

    /// The three pages a walk moves between: the one being read, and the one
    /// either side of it.
    ///
    /// Three and not a run of them, because a page is one walk away from
    /// becoming the middle one — what a finger can reach before it lets go is
    /// the page next door, and the calendar is endless in both directions.
    private static let pages = [-1, 0, 1]

    /// How wide a page is, which is the room the open pill has: a page is what
    /// fills the glass, so that letting go on one leaves it filling the glass.
    private var pageWidth: CGFloat { max(widthWhenOpen, 1) }

    /// The grid a page is drawn from — the month either side when the month is
    /// out, and the week either side when it is a strip.
    private func pageGrid(_ page: Int) -> JournalCalendar.Month {
        pill.detent == .month ? calendar.monthAlong(page) : calendar.weekAlong(page)
    }

    /// Which page the grid is currently nearest, which is the one the month
    /// over it should be naming.
    private var pageNearest: Int {
        min(max(Int((-walked / pageWidth).rounded()), -1), 1)
    }

    // MARK: - What a grid of numbers cannot say for itself

    /// The sentence under the month, on the two occasions there is one —
    /// which is ``TheGridsOwnSentence``, and what is added here is when the
    /// pill shows it.
    @ViewBuilder private var whatTheGridCannotSayForItself: some View {
        if somethingToSay {
            TheGridsOwnSentence(calendar: calendar)
                // With the month row, because it belongs to the month the same
                // way: no grid, nothing to say about one. And out of the
                // reading order until then, because opacity is drawing and
                // VoiceOver does not read what is drawn.
                .opacity(monthIsOut)
                .accessibilityHidden(pill.detent != .month)
        }
    }

    /// The sentence at its natural height, laid out where nothing squeezes it
    /// and drawn nowhere.
    ///
    /// Measured *inside* the panel it would be measured at whatever height the
    /// panel had opened to — and the panel opens to a height worked out from
    /// this, which is a loop that lays out until something gives. So it is
    /// measured out here, at the width the open pill has, and the panel is
    /// told how much room to leave.
    @ViewBuilder private var noticeProbe: some View {
        if somethingToSay, roomToOpenInto > 0 {
            TheGridsOwnSentence(calendar: calendar)
                .frame(width: widthWhenOpen)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    noticeHeight = $0
                }
        }
    }

    /// Whether there is a sentence to put under the grid at all — and so
    /// whether the panel has to open far enough to hold one.
    private var somethingToSay: Bool {
        TheGridsOwnSentence.isThereOne(for: calendar)
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

            // Named for whichever page the grid is nearest rather than for the
            // one the calendar is still on, so that a month scrolled halfway
            // into view is not sitting under the name of the one it replaced.
            Text(pageGrid(pageNearest).name)
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
        .opacity(monthIsOut)
        // And out of a finger's way until then. Clipping is drawing and not
        // hit testing: this row is above the ceiling in the week strip, drawn
        // nowhere and still sitting squarely on the pill it came out of.
        .allowsHitTesting(pill.detent == .month)
    }

    /// The pages, side by side, with the one being read in the middle.
    ///
    /// Laid out all three and carried across rather than swapped when the walk
    /// is over: a page-turn tells you where you arrived, and a scroll tells you
    /// where you are going while you are still deciding.
    private var grid: some View {
        let onHand = pagesOnHand
        return HStack(spacing: 0) {
            ForEach(onHand, id: \.self) { page($0) }
        }
        // Whichever page is first sits at the leading edge, so this is what
        // brings the one being read back to it.
        .offset(x: CGFloat(onHand.first ?? 0) * pageWidth + walked)
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
    }

    /// Which pages are built: the one being read, and the one either side of
    /// it only while a finger is walking between them.
    ///
    /// Not three at rest, and this is not thrift. In the week strip all three
    /// pages are rows of one month, so every day would be in the tree three
    /// times over with nothing to tell the copies apart — and the first one
    /// found is the one off the side of the glass. Hiding them does not do it:
    /// `accessibilityHidden` on a container leaves the buttons inside it
    /// exactly where they were. So at rest there is one page and one of every
    /// day, which is the state anything ever asks a question in.
    private var pagesOnHand: [Int] { walked == 0 ? [0] : Self.pages }

    private func page(_ page: Int) -> some View {
        let grid = pageGrid(page)
        let beingRead = page == 0
        return VStack(spacing: 0) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { row, week in
                HStack(spacing: 0) {
                    // Identified by the place in the grid rather than by the
                    // day, so that a scan arriving mid-drag changes what a cell
                    // says and never which cell it is.
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        DayCell(day: day, accent: accent, side: rowHeight) { pickAndClose(day.day) }
                    }
                }
                .frame(height: rowHeight)
                // A row above or below the ceiling is not merely not drawn:
                // it is not there to be tapped either. Clipping in SwiftUI is
                // drawing alone, so a week strip whose other five rows were
                // only *clipped* would be five rows of invisible buttons — and
                // the ones the grid has slid up past sit directly on the pill,
                // swallowing the tap that would have opened it further.
                .allowsHitTesting(beingRead && rowIsUnderTheCeiling(row, of: grid))
            }
        }
        // Slid up by whole rows until the week being read is under the weekday
        // names, and back down as the month comes out. This is the week strip:
        // there is no second view of one.
        .offset(y: gridSlide(of: grid))
        .frame(height: CGFloat(grid.weeks.count) * rowHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, Spacing.close)
        .frame(width: pageWidth)
        // A page either side is drawn, and that is all it is: it exists for
        // the length of the walk and is not there to be reached into.
        .accessibilityHidden(!beingRead)
        .allowsHitTesting(beingRead)
    }

    /// Whether a row of a page is one a finger can reach: on screen in whole,
    /// in the room the panel is currently open to.
    private func rowIsUnderTheCeiling(_ row: Int, of grid: JournalCalendar.Month) -> Bool {
        // Within the panel, the grid starts below whatever of the month row
        // has come out and below the weekday names, and stops above whatever
        // of the sentence under it has come out with the month.
        let notice = (somethingToSay ? noticeHeight : 0) * pill.spread
        let ceiling = panelHeight - monthRowHeight * pill.spread - weekdayHeight - notice
        let top = CGFloat(row) * rowHeight + gridSlide(of: grid)
        // Half a point of slack, because these are two sums of the same
        // scaled numbers and a row exactly on the line should be reachable.
        return top >= -0.5 && top + rowHeight <= ceiling + 0.5
    }

    private func pickAndClose(_ day: JournalDay) {
        pick(day)
        pill.close()
    }

    // MARK: - The geometry, read off how far open it is

    /// How wide the pill is when it is all the way open: the room it has,
    /// until the room is more room than a month wants.
    ///
    /// A month wants seven columns as wide as its rows are tall, and not a
    /// point more. Rows stop growing at a row's height (see ``rowHeight``), so
    /// past that every point of extra width goes into the gaps between the
    /// days and none of it into the days — a tint is the same square at 44
    /// points of column as at 90, with three times the air around it. That is
    /// what a stretched calendar *is*: not big days, but far-apart ones, read
    /// as seven numbers rather than as a week.
    ///
    /// Which matters because every window that gets a pill at all is narrower
    /// than ``JournalLayout/sidebarNeeds`` — and that still runs from Slide
    /// Over to an iPad mini stood up, whose room is more than twice what the
    /// grid can use.
    ///
    /// Never narrower than the shut pill, which is the one case the square has
    /// to give way for: at the largest text sizes the day's own name is wider
    /// than any grid wants to be, and a pill that got *smaller* as it opened
    /// would be a calendar coming out of nowhere.
    private var widthWhenOpen: CGFloat {
        let square = pillHeight * 7 + Spacing.close * 2
        return min(roomToOpenInto, max(square, closedWidth))
    }

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
        let column = max(0, widthWhenOpen - Spacing.close * 2) / 7
        return column > 0 ? min(pillHeight, column) : pillHeight
    }

    private var panelHeight: CGFloat {
        let week = weekdayHeight + rowHeight
        let month = monthRowHeight + weekdayHeight
            + CGFloat(calendar.month.weeks.count) * rowHeight
            + (somethingToSay ? noticeHeight : 0)
        return pill.spread > 0
            ? week + (month - week) * pill.spread
            : week * pill.openness
    }

    /// How far out the month is, as the fraction the things that belong to it
    /// alone are drawn at: the name over the grid, and the sentence under it.
    private var monthIsOut: Double {
        min(max((pill.progress - 1.45) * 3, 0), 1)
    }

    private func gridSlide(of grid: JournalCalendar.Month) -> CGFloat {
        // Nought at both ends and a whole row's travel at the week strip in
        // between, which is the same thing said forwards and then backwards.
        -CGFloat(grid.weekOnScreen) * rowHeight * (pill.openness - pill.spread)
    }

    private var width: CGFloat {
        // Before either has been measured there is nothing to be wide, and on
        // a text size where the day's name alone is wider than the screen
        // there is nothing to grow into — so the pill is simply the room it
        // has, at every state.
        guard roomToOpenInto > 0 else { return closedWidth }
        let open = widthWhenOpen
        guard closedWidth > 0, closedWidth < open else { return open }
        return closedWidth + (open - closedWidth) * pill.openness
    }

    private var shape: RoundedRectangle {
        // The corner a pill has, kept as the panel grows: a capsule 44 points
        // tall is a 22-point corner, and the identity's glass keeps it rather
        // than squaring off into a card (`Metrics`).
        RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous)
    }

    /// What it does when it is let go: the identity's own settle, or a plain
    /// short fade for a reader who asked for less movement.
    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(stiffness: 320, damping: 30)
    }

    /// And what the pages land with, which is the settle given a duration.
    ///
    /// The walk is over at a moment this has to know — the calendar steps
    /// then, and the pages go back to where they started — and a spring that
    /// asymptotes towards its rest has no such moment to offer.
    private var snap: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0.1)
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
    /// - Parameters:
    ///   - calendar: the days to draw, or `nil` for no pill at all — which is
    ///     both a journal that has not opened yet and a window wide enough
    ///     that the calendar lives in a sidebar instead (``JournalLayout``).
    ///   - pill: how far open it is. Held by the screen rather than by the
    ///     pill for the two things only the screen can do with it: shut a
    ///     month somebody opened by mistake by tapping the page behind it, and
    ///     shut one that a window resize has just put a sidebar underneath.
    func datePill(
        over calendar: JournalCalendar?,
        accent: Accent,
        openedTo pill: Binding<DatePill>,
        pick: @escaping (JournalDay) -> Void,
        turning turn: @escaping (Int) -> Void,
        settling settleTheDayOnScreen: @escaping () async -> Void
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if calendar != nil {
                RoomForTheShutPill()
            }
        }
        // Aligned to the top, and not left to the overlay's own middle. A shut
        // pill is one row tall, so an overlay sized to its content and centred
        // would hang the day's name halfway down the page — and then jump it
        // to the top the moment the calendar came out, because an open pill
        // carries the full-height way out of itself and fills the screen.
        .overlay(alignment: .top) {
            if let calendar {
                DatePillOverThePage(
                    calendar: calendar,
                    accent: accent,
                    pick: pick,
                    turn: turn,
                    settleTheDayOnScreen: settleTheDayOnScreen,
                    pill: pill
                )
            }
        }
    }
}

/// The pill, and the rest of the page under it — which is a way out of it.
///
/// The two are one view because they are one decision. How far open the pill
/// is has to be reachable from outside the glass, or the only way to shut a
/// month somebody opened by mistake would be to open it further first.
private struct DatePillOverThePage: View {
    let calendar: JournalCalendar
    let accent: Accent
    let pick: (JournalDay) -> Void
    let turn: (Int) -> Void
    let settleTheDayOnScreen: () async -> Void

    @Binding var pill: DatePill

    var body: some View {
        ZStack(alignment: .top) {
            // Going back to a day's own words is a way of saying you are done
            // with the calendar, so it is one. Nothing is drawn here and the
            // page is not dimmed: a grid over a page is left by returning to
            // the page, and darkening it would be the app making more of the
            // moment than the reader did.
            if pill.detent != .closed {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { pill.close() }
                    // Not a thing to be found and wondered about: the same way
                    // out is on the pill itself, as the escape a dismissible
                    // thing has.
                    .accessibilityHidden(true)
            }

            DatePillView(
                calendar: calendar,
                accent: accent,
                pick: pick,
                turn: turn,
                settleTheDayOnScreen: settleTheDayOnScreen,
                pill: $pill
            )
                .padding(.horizontal, Spacing.apart)
                .padding(.top, Spacing.close)
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
    @Previewable @State var pill = DatePill()

    DatePillView(
        calendar: previewCalendar(),
        accent: .driftwood,
        pick: { _ in },
        turn: { _ in },
        settleTheDayOnScreen: {},
        pill: $pill
    )
        .padding(.horizontal, Spacing.apart)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.backgroundColor)
}

#Preview("Over a page of words") {
    @Previewable @State var pill = DatePill()

    let calendar = previewCalendar()
    ScrollView {
        Text(String(repeating: "Words on the page, behind the glass. ", count: 60))
            .lettering(.prose)
            .padding(Spacing.apart)
    }
    .datePill(
        over: calendar,
        accent: .driftwood,
        openedTo: $pill,
        pick: { calendar.pick($0) },
        turning: { $0 > 0 ? calendar.showNextDay() : calendar.showPreviousDay() },
        settling: {}
    )
    .background(Palette.backgroundColor)
}
