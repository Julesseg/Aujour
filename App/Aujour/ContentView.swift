import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// The app's one screen: today's Entry, over the folder the journal lives in.
///
/// Two things have to be true before there is anything to type into, and they
/// are the two states around the editor here — Aujour has found a folder, and
/// it has read what that folder holds for today. Neither is ever shown as an
/// empty page: an empty editor over a folder that could not be read is
/// indistinguishable from a day nobody wrote on (ADR 0001).
struct ContentView: View {
    @State private var journal: Journal
    @State private var showingSettings = false
    /// The screen on top of today's Entry, if one is — nil while today's is
    /// what is on screen.
    ///
    /// One piece of state for both, rather than a flag each: two
    /// `navigationDestination(isPresented:)` modifiers on one view are two
    /// destinations the stack picks between, and which one a tap opens stops
    /// being a thing this screen decides.
    @State private var wayIn: WayIntoTheJournal?

    /// The day the app is on, when it is not today's — its editor, made once
    /// and kept for as long as that day is on screen.
    ///
    /// `nil` while today is the day being written, because today's Entry is
    /// the Journal's own and there must never be two editors over one file:
    /// two of them autosaving over each other is a day's words losing to
    /// themselves. Which of the two is on screen is the calendar's to say, and
    /// this is only where the other one is kept.
    @State private var dayPickedOutOfTheGrid: OpenedDay?

    /// The day the page on screen is for — what makes a page a page, and so
    /// what turning one is a change of.
    ///
    /// The calendar is the authority on which day the journal is on, and this
    /// is not a second opinion: it is set in the same breath as the calendar
    /// moves, and a change in the journal that came from anywhere else puts it
    /// back in step. It is held here for one reason — a transition runs only
    /// when the change that triggered it was made inside the animation, and an
    /// identity read straight off the calendar is an observed read that
    /// SwiftUI is free to deliver in an update of its own. That is a page that
    /// turns sometimes and appears the rest of the time.
    @State private var dayOnScreen: JournalDay?

    /// Which way the journal last moved, so that the day leaving the screen
    /// goes the way the reader sent it and the day arriving comes from the
    /// other side.
    ///
    /// Forwards until something says otherwise, which is also what the clock
    /// does: a journal left open across the rollover moves on to the new day,
    /// and that is a step forwards like any other.
    @State private var goingForwards = true

    /// How far open the date pill is.
    ///
    /// Here rather than inside the pill for the two things only this screen
    /// can do with it. One is old: the rest of the page is a way out of an
    /// open month, and a state nothing outside the glass could reach would be
    /// a pill only the pill could shut. The other is why it is *here* and not
    /// one view further down — a window resized past the threshold takes the
    /// pill away and puts a sidebar in its place, and the pill has to come
    /// back shut when the window narrows again (``JournalLayout``).
    @State private var pill = DatePill()

    /// How wide this window is, which is the only thing that decides which of
    /// the two presentations the journal is read in.
    ///
    /// The window and not the screen, and measured rather than inferred from a
    /// size class: an iPad in Slide Over has no more room than a phone, and an
    /// iPad mini stood up reports a regular width at 744 points, which is too
    /// narrow to hold a calendar and a readable page at once.
    ///
    /// Nought until the first layout, which is the page presentation — an app
    /// with no room yet is not one to put a sidebar in.
    @State private var windowWidth: CGFloat = 0

    @Environment(\.scenePhase) private var scenePhase

    /// Whether this reader has asked for less movement, which the day sliding
    /// in and out is squarely a piece of.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What this window is actually drawing in, light or dark — never "no
    /// preference", because this is the answer and not the question.
    ///
    /// Read here so that a sheet can be told it. A sheet is its own
    /// presentation: the appearance the window asks for reaches it when it is
    /// put up and not afterwards, so it has to be told again on every change.
    /// And told a *resolved* scheme, because the interesting case is Auto —
    /// "no preference" does not undo an override a sheet is already under, so
    /// a sheet told dark and then told nothing goes on being dark while the
    /// window behind it turns light.
    @Environment(\.colorScheme) private var drawnIn

    /// The two ways back into a day that is not today's: by when it was, and
    /// by what was written in it.
    private enum WayIntoTheJournal: Hashable {
        case search
    }

    /// How this device wants Aujour to look, held for the one screen that
    /// changes it. The app is already drawn in it — the appearance, the tint
    /// and the editor's typeface are applied above this view — so all this
    /// does is carry it as far as the page that offers the choices.
    private let appearance: DeviceAppearance

    init(journal: Journal = Journal(), appearance: DeviceAppearance) {
        _journal = State(wrappedValue: journal)
        self.appearance = appearance
    }

    /// Whether a welcome is owed, as something a cover can be presented on.
    ///
    /// Read-only in the direction that matters: the welcome ends when it has
    /// been answered, and it says so itself by no longer being due. Nothing
    /// SwiftUI can do to this binding is a way out of it, which is the point —
    /// a cover dismissed by anything but one of its own buttons would be a
    /// device that had been welcomed without hearing any of it.
    private var theWelcomeIsDue: Binding<Bool> {
        Binding(get: { journal.welcome.isDue }, set: { _ in })
    }

    /// The way out of a folder that has gone: the user's Entries are still in
    /// it, and Aujour's own folder is somewhere to write in the meantime.
    ///
    /// Offered only when the folder that failed is one they chose — for
    /// Aujour's own folder there is nowhere else to go, and a button that
    /// does nothing is worse than no button.
    private var wayBackToAujoursOwnFolder: (() async -> Void)? {
        guard journal.hasACustomFolder else { return nil }
        return { await journal.useAujoursOwnFolder() }
    }

    /// The day the app is showing, and the editor over it — or `nil` for the
    /// one day there is no editor for.
    ///
    /// Today's until a day is picked out of the grid, and today's again the
    /// moment today is picked — which is the calendar's answer and not a copy
    /// of it kept here, so that a phone left open past the rollover moves on
    /// to the new day rather than staying on the old one.
    private var entryOnScreen: OpenedDay? {
        // A day that has not arrived has no Entry to open, and this is where
        // the screen stops looking for one: an editor is the only thing that
        // can write an Entry, so a day with no editor is a day with no file,
        // however hard the screen is tapped.
        guard journal.calendar?.writingOpensAt == nil else { return nil }
        if let picked = dayPickedOutOfTheGrid, journal.calendar?.dayBeingWritten == picked.day {
            return picked
        }
        return journal.today.map { OpenedDay(day: $0.day, editor: $0) }
    }

    /// Opens a day picked out of the date pill's grid.
    ///
    /// Every reason a pick might come to nothing is the calendar's, and this
    /// takes its word for all of them: a day that has not arrived, which the
    /// grid disables and the calendar refuses again where it cannot be tapped
    /// around, and the day already being written, which would otherwise be a
    /// second editor over one Entry.
    ///
    /// A jump through the grid slides the same way a step does, because it is
    /// the same journey: what the direction says is which way through the
    /// journal the reader went, and the 3rd picked from the 14th went back.
    private func pick(_ day: JournalDay) {
        guard let calendar = journal.calendar else { return }
        move(forwards: day > calendar.dayBeingWritten) { calendar.pick(day) }
    }

    /// Moves the journal a day, which is what a finger drawn sideways across
    /// the shut date pill does.
    ///
    /// Not `pick`'s refusal, deliberately: a cell in the grid is the way *in*
    /// to writing a day and a locked one has to refuse, while a swipe is the
    /// calendar walked rather than chosen from. So this reaches a day that has
    /// not arrived, and what is found there is a page saying so.
    ///
    /// - Parameter days: which way, as the number of days a swipe landed —
    ///   the day before is -1 and the day after is 1.
    private func turn(_ days: Int) {
        guard let calendar = journal.calendar else { return }
        move(forwards: days > 0) {
            if days > 0 { calendar.showNextDay() } else { calendar.showPreviousDay() }
            return true
        }
    }

    /// Moves the journal a day, and turns the page to it.
    ///
    /// Everything on screen moves in one breath, and that is the whole of it:
    /// the day the pill names, the editor under it and the page's own identity
    /// are three answers to one question, and a screen that changed them in
    /// three transactions would be one that flashed a different day between
    /// two of them.
    ///
    /// The folder is read *behind* the move and never in front of it. Settling
    /// a divergence reaches iCloud through a system call that answers on the
    /// main actor's own thread, and a journal that would not move until that
    /// came back is a journal a folder can stop moving — which is a stall
    /// measured in seconds on a machine with a real iCloud folder, in exchange
    /// for a frame of "Opening" on a page that is turning anyway. The page
    /// holds its own size while that frame is on it, so nothing else on screen
    /// is at its mercy.
    ///
    /// The direction is handed in rather than worked out afterwards from the
    /// two days, and that is a timing matter and not a taste one: a transition
    /// is chosen at the moment the page changes identity, so a direction
    /// settled from the day it turned out to be would arrive one frame after
    /// the slide it was meant to shape. Both callers know which way they are
    /// going before they go.
    ///
    /// - Parameter go: the move itself, answering whether anything changed.
    ///   Asked rather than compared afterwards, because "the day on screen is
    ///   the same day" is not the same as "nothing happened": picking today
    ///   while pinned to it hands the journal back to the clock without moving
    ///   it a day.
    private func move(forwards: Bool, _ go: () -> Bool) {
        guard let calendar = journal.calendar else { return }
        let leaving = dayPickedOutOfTheGrid

        goingForwards = forwards
        var arriving: OpenedDay?
        var moved = false
        withAnimation(theDaySlidesBy) {
            guard go() else { return }
            let day = calendar.dayBeingWritten
            // Today's Entry is the Journal's own, so arriving on today is
            // putting this one down rather than making another — and a day
            // that has not arrived has no editor to make at all. One
            // assignment for all three, so the day held here and the day the
            // calendar is on cannot come apart.
            arriving =
                calendar.isOnToday
                ? nil
                : calendar.editor(for: day).map { OpenedDay(day: day, editor: $0) }
            dayPickedOutOfTheGrid = arriving
            dayOnScreen = day
            moved = true
        }
        guard moved else { return }

        if let arriving {
            Task {
                // Before it is read, for the same reason today's Entry is: a
                // past day can have been written on two devices too —
                // backfilled on the iPad on the train and on the iPhone that
                // evening — and the version that loses its path is set aside
                // rather than left in iCloud where nobody would ever see it.
                await journal.settleAnyDivergence(before: arriving.editor)
                await arriving.editor.open()
            }
        }

        Task {
            // The day left behind is saved and the folder read again — which
            // is what puts the dot on a day that has just been filled in, and
            // what keeps the app to one editor per Entry.
            if let leaving {
                await leaving.editor.save()
            } else {
                await journal.today?.save()
            }
            await calendar.scan()
        }
    }

    /// The page the day being written is: an Entry to write in, or the one
    /// day there is no Entry for.
    ///
    /// Under the pill either way, and swiped between either way. A day that
    /// has not arrived is a page of the journal like any other — it is
    /// reachable, it names itself on the pill above, and it is left the way it
    /// was arrived at — and the only thing it does not have is somewhere to
    /// type.
    @ViewBuilder private var theDayOnScreen: some View {
        if let onScreen = entryOnScreen {
            EntryView(
                editor: onScreen.editor,
                photographsFrom: journal.photoLibrary,
                placesFrom: journal.places
            )
            .parkedFilesNotice(from: journal, for: onScreen.day, in: appearance.accent)
        } else if let calendar = journal.calendar, let opensAt = calendar.writingOpensAt {
            ADayThatHasNotArrived(writingOpensAt: opensAt)
        } else {
            // There is no open journal without today's Entry over it — but a
            // blank page is the one thing this screen must never be, so the
            // unreachable case is the spinner.
            ProgressView("Opening today's entry")
                .accessibilityIdentifier("openingEntry")
        }
    }

    /// Which day the journal is on, as something that can be watched.
    private var theDayTheJournalIsOn: JournalDay? {
        journal.calendar?.dayBeingWritten ?? journal.today?.day
    }

    // MARK: - Which presentation the window is wide enough for

    /// Which of the two presentations the journal is being read in.
    ///
    /// A pinned answer where a UI test has pinned one, and the window's own
    /// otherwise. The suite drives the app from another process and cannot
    /// resize a window: on an iPhone and on an iPad mini a rotation crosses
    /// the threshold, but on a large iPad every orientation is wide, so a test
    /// about the *page* presentation has no window it can ask for. Pinning is
    /// how it asks — the presentation is stated, and everything downstream of
    /// it is the app's own code.
    private var layout: JournalLayout {
        UITestingJournal.pinnedLayout ?? JournalLayout(windowWidth: windowWidth)
    }

    /// The sidebar, on the windows there is room for one in.
    ///
    /// A slot that is sometimes empty rather than a view that comes and goes
    /// beside the page: the page next to it is a day's writing with an editor
    /// in it, and a resize that changed how many children the row had would be
    /// a resize that rebuilt the thing being typed into.
    @ViewBuilder private var theSidebar: some View {
        if layout == .sidebar, let calendar = journal.calendar {
            SidebarCalendarView(
                calendar: calendar,
                accent: appearance.accent,
                pick: pick,
                // Written down before the folder is read, for the same reason
                // the pill does it: the marks are a scan of the folder, and a
                // day being filled in this second is a day whose file is not
                // there yet.
                settleTheDayOnScreen: { await entryOnScreen?.editor.save() }
            )
            Divider()
        }
    }

    /// The day on screen as the bar's title, where the bar is what names it —
    /// and nothing at all where the pill does.
    ///
    /// With its year only when that is news, exactly as the pill says it: the
    /// journal can be left on a day years back, and every February has a 14th.
    private var theDayIsNamedInTheBar: String {
        guard layout == .sidebar, let calendar = journal.calendar else { return "" }
        let day = calendar.dayBeingWritten
        return day.spelledOut(withYear: day.year != calendar.today.year)
    }

    /// What a window resized across the threshold does.
    ///
    /// The selected day is not mentioned here, and that is the point: which
    /// day the journal is on is the calendar's, the calendar outlives a
    /// resize, and a screen that put the day back would be a second opinion
    /// about it. What does have to be said is the pill — it is this screen's
    /// state, it survives the crossing that takes it off screen, and a month
    /// left open would come back over a sidebar already showing that month,
    /// which is the calendar drawn twice.
    ///
    /// Unanimated, and said out loud rather than left to luck. Going wide the
    /// pill has already been taken off screen by the time this runs, and going
    /// narrow it is coming back from a state it was shut in — but the pill
    /// hangs a settling spring on its own progress, and a shut that reached it
    /// as an animatable change would be a month folding itself away in the
    /// middle of a layout that is already moving.
    private func theWindowCrossedTheThreshold() {
        withTransaction(Transaction(animation: nil)) { pill.close() }
    }

    /// How the day leaving and the day arriving pass each other: out the way
    /// the reader sent it, and in from the other side.
    ///
    /// The whole of what this adds is *which way*. A day changing on its own
    /// would say the journal had moved and leave the reader to work out where
    /// to; a day that leaves to the left says they went forwards, which is the
    /// one thing the pill above cannot say without being read.
    ///
    /// A plain fade for a reader who asked for less movement — the direction
    /// is worth having and is not worth sliding a screenful of somebody's
    /// writing across the page to say.
    private var theDaySlides: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: goingForwards ? .trailing : .leading),
            removal: .move(edge: goingForwards ? .leading : .trailing)
        )
    }

    /// What it slides with: the pill's own page-turn, because that is what
    /// this is — one of the pages under it, turned.
    private var theDaySlidesBy: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0.1)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch journal.state {
                case .opening:
                    ProgressView("Opening your journal")
                        .accessibilityIdentifier("openingJournal")
                        .navigationTitle("Aujour")

                case .open:
                    // The month down one side on a window with room for it,
                    // and nothing at all on a window without — and the day's
                    // words beside it either way.
                    HStack(spacing: 0) {
                        theSidebar

                        // A container of its own, and not the day itself: for
                        // the length of a slide there are two days on screen,
                        // and they need something to be laid over each other
                        // in and clipped to. Identified by the day, because
                        // that is what makes this a change of page rather than
                        // a change of contents — the same view told to say
                        // something else would have nothing to slide out.
                        ZStack {
                            theDayOnScreen
                                .id(dayOnScreen)
                                .transition(theDaySlides)
                        }
                        // The page is the page whatever is on it. Left to size
                        // itself, a container holding one day's writing would
                        // take the shape of whatever the day happened to be —
                        // and a day that is briefly a single line of prose
                        // would gather the whole screen in around it, pill and
                        // all.
                        //
                        // The whole room beside the calendar and not the
                        // measure: what is set at a measure is the day's
                        // words, and the page they are set on is the page. A
                        // day turned here slides across all of it.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .datePill(
                            // No pill where the month is already on screen: a
                            // window wide enough for a sidebar has answered
                            // the question the pill exists to ask, and a
                            // second calendar over the first is the calendar
                            // drawn twice.
                            over: layout == .page ? journal.calendar : nil,
                            accent: appearance.accent,
                            openedTo: $pill,
                            pick: pick,
                            turning: turn,
                            // Written down before the month is read: the marks
                            // are a scan of the folder, and a day being filled
                            // in this second is a day whose file is not there
                            // yet.
                            settling: { await entryOnScreen?.editor.save() }
                        )
                    }
                    // Which day is on screen, on the one presentation where
                    // nothing else says it. The pill names the day it is over,
                    // so on a narrow window a title would be the same sentence
                    // twice in two typefaces — the redesign's own worst
                    // screen. Beside a sidebar there is no pill, and a filled
                    // cell in a grid is a day pointed at rather than a day
                    // named: an Entry is its date, and the page you are
                    // writing on should say which one.
                    .navigationTitle(theDayIsNamedInTheBar)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            // The other way back into a day, and now the
                            // only one in the bar: by when it was is the
                            // pill's, and by what was written in it is
                            // this.
                            Button("Search", systemImage: "magnifyingglass") {
                                wayIn = .search
                            }
                            .accessibilityIdentifier("openSearch")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            // One way in for the folder and every setting
                            // over it, because they are one answer: this
                            // is your journal, and this is what Aujour
                            // will do with it. Named for what the sheet is
                            // titled, since the journal is only the first
                            // half of it — how the app looks is behind
                            // here too.
                            Button("Settings", systemImage: "slider.horizontal.3") {
                                showingSettings = true
                            }
                            .accessibilityIdentifier("openSettings")
                        }
                    }

                case .unavailable(let problem):
                    StorageProblemNotice(
                        problem: problem,
                        useAujoursOwnFolder: wayBackToAujoursOwnFolder
                    ) {
                        await journal.open()
                    }
                    .navigationTitle("Aujour")
                }
            }
            // Outside the states, like the calendar below and for the same
            // reason: choosing a folder closes the journal it was opened from
            // and opens another, and a sheet that lives inside one state is a
            // sheet that vanishes mid-decision.
            // Outside the states rather than inside `.open`: choosing a
            // folder closes the journal it was opened from and opens another,
            // and every setting on the sheet reopens it too — a sheet that
            // lived inside one state is a sheet that vanishes mid-decision.
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(journal: journal, appearance: appearance)
                    // The one sheet this matters most for: it is where the
                    // appearance is changed, so it is the one that would sit
                    // in yesterday's colours right under the control that had
                    // just changed them.
                    .preferredColorScheme(drawnIn)
                    // Counted again on the way in: the number from launch is
                    // one edit out of date the moment today's Entry is
                    // created.
                    .task { await journal.recount() }
            }
            // Declared outside the states rather than beside the button that
            // opens it: a destination registered only while one branch of a
            // switch is on screen is one the stack can find itself without.
            //
            // Today's Entry is what the app is for, so this is a step away
            // from it and back — and coming back is what re-reads the folder
            // for a day just filled in.
            .navigationDestination(item: $wayIn) { wayIn in
                switch wayIn {
                case .search:
                    if let search = journal.search {
                        JournalSearchView(search: search, journal: journal, accent: appearance.accent)
                    }
                }
            }
        }
        // Over everything rather than in place of it, and put up without
        // waiting for anything: the folder is being found and today's Entry
        // spawned behind this, so the app is ready to be written in the moment
        // the last page is answered. A first run that made somebody wait for a
        // folder before it would say hello would be a first run that made them
        // wait for iCloud.
        .fullScreenCover(isPresented: theWelcomeIsDue) {
            WelcomeView(journal: journal)
        }
        // How wide the window is, read off the one view in the app that fills
        // it. The window and not the screen: Slide Over, a half-width Split
        // View and a Stage Manager window dragged narrow all hand the app less
        // room than the glass it is on, and all three should be read the way a
        // phone is.
        //
        // The safe area is added back rather than taken off, and that is the
        // difference between a window and a *cutout*. A phone on its side is
        // the case: the notch and the home indicator eat 124 points of an
        // 874-point window, and a threshold read off what was left would put
        // the same window either side of the line depending on which handset
        // the notch belonged to. What the threshold is about is how much room
        // the reader has, and a strip of screen beside a camera is room.
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width + $0.safeAreaInsets.leading + $0.safeAreaInsets.trailing
        } action: {
            windowWidth = $0
        }
        .onChange(of: layout) { _, _ in theWindowCrossedTheThreshold() }
        // And put where a day can read it, which is the one thing downstream
        // of the window that is not this screen's own: how wide a day's words
        // are set. Every Entry in the app is under this, including one pushed
        // by a search — a day reached by what was written in it is set the
        // same way as the day reached by when it was.
        .environment(\.journalLayout, layout)
        .task { await journal.open() }
        // A journal that has been reopened — a folder changed, a Path Template
        // changed — is a new calendar over new files, and a day held from the
        // old one is an editor over a store nothing is journaling into any
        // more.
        .onChange(of: journal.calendar.map(ObjectIdentifier.init)) { _, _ in
            dayPickedOutOfTheGrid = nil
        }
        // Kept in step with the journal for every way the day moves that is
        // not somebody moving it: the first day there is one, the morning an
        // app left open overnight comes back to, a journal reopened onto
        // another folder. Those turn no page — there is nothing to slide out
        // of the way of a day that arrived on its own — so they are a plain
        // swap, and this is where they are noticed rather than three places.
        .onChange(of: theDayTheJournalIsOn, initial: true) { _, day in
            dayOnScreen = day
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive, .background:
                // The last chance to write: there is no next second to save in
                // once the app is out of the way, and the debounce the editor
                // is holding would be spent in it.
                //
                // And then the reminder, in that order and never the other
                // way: whether today still needs asking about is decided by
                // whether today's Entry is a file, and the words that would
                // make it one are the ones being saved here.
                //
                // Both editors, because a day backfilled from the pill is
                // being written into just as literally as today is.
                Task {
                    await journal.today?.save()
                    await dayPickedOutOfTheGrid?.editor.save()
                    await journal.reconsiderTheDailyReminder()
                }
            case .active:
                // What coming back to the front means for a journal that is
                // files in a folder — a new day, and a folder that moved on
                // while nothing was listening — is the Journal's to say. It
                // says it for today's Entry; a day picked out of the grid is
                // this screen's own, and catches up the same way, taking on
                // what its file says wherever nothing here is waiting to be
                // written to it.
                // Whatever the last move was, the one that may be about to
                // happen here is the clock's, and the clock only goes one way:
                // an app left open across the rollover comes back to a new day
                // that arrived from ahead of it.
                goingForwards = true
                Task {
                    await journal.cameBackToTheFront()
                    await dayPickedOutOfTheGrid?.editor.reloadIfClean()
                }
            @unknown default:
                break
            }
        }
    }
}


extension EnvironmentValues {
    /// Which presentation the journal is being read in, put where the views
    /// under it can reach it.
    ///
    /// Read off the window by ``ContentView`` and answered here, because the
    /// screen is the only thing that knows how much room there is and the
    /// views that care about it are several pushes down.
    ///
    /// The default is the page, which is what a preview and a test of
    /// something else want: the presentation that caps nothing.
    var journalLayout: JournalLayout {
        get { self[JournalLayoutKey.self] }
        set { self[JournalLayoutKey.self] = newValue }
    }
}

private struct JournalLayoutKey: EnvironmentKey {
    static let defaultValue = JournalLayout.page
}

extension View {
    /// Says, above a day's Entry, that another version of that day was kept
    /// beside it.
    ///
    /// A modifier because there are two ways into a day and both of them need
    /// it: today's screen, and a day filled in from the calendar. Each shows
    /// only its own day's Parked Files — a notice about March 1st over the
    /// Entry for the 14th would be about a file that is nowhere near it.
    ///
    /// Above the words rather than over them: a version of this day the user
    /// has not seen is news, and the day itself is still theirs to write in
    /// while the notice is up.
    func parkedFilesNotice(
        from journal: Journal,
        for day: JournalDay,
        in accent: Accent
    ) -> some View {
        safeAreaInset(edge: .top) {
            let parked = journal.parkedFiles(from: day)
            if !parked.isEmpty {
                ParkedFilesNotice(
                    files: parked,
                    accent: accent,
                    show: { file in
                        // Nothing to open where the journal can no longer say
                        // where the file is. It is still where it was left,
                        // which is the whole point of a Parked File.
                        guard let onDisk = journal.whereItLies(file) else { return }
                        TheFilesApp.show(onDisk)
                    },
                    acknowledge: { journal.acknowledgeParkedFiles(from: day) }
                )
            }
        }
    }
}

/// A day two devices both wrote, said where the user is writing it.
///
/// The Parked File beside the Entry is the lasting notice — it is a file in
/// their vault, which is where they will meet it again. This is so that they
/// meet it at all: without it, the only sign that a version of today was set
/// aside would be a file they have no reason to go looking for.
///
/// **Never an error colour.** Nothing went wrong: both versions are somebody's
/// words and both are still there. So the banner is the accent's, like the
/// rest of what the app says about itself, and the reader's own accent at
/// that.
///
/// Its one action is to show the Parked File where it lies. Aujour does not
/// offer to compare the two versions, or to merge them, or to delete either:
/// that is an opinion about the contents of somebody's files, and having none
/// is the whole of ADR 0001. Merging is their work in their own editor
/// (`CONTEXT.md`, Parked File).
struct ParkedFilesNotice: View {
    let files: [ParkedFile]

    /// The one colour the app spends on itself, and so the one this is
    /// tinted with — the reader's own choice, not a colour this banner picked
    /// to mean something.
    let accent: Accent

    /// Shows one of them where it lies, outside the app.
    let show: (ParkedFile) -> Void

    let acknowledge: () -> Void

    /// The mark the banner opens with, and how far down the line it sits.
    /// Both grow with the sentence beside them: a seven-point dot against a
    /// line of accessibility-sized text would be a speck.
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 7
    @ScaledMetric(relativeTo: .subheadline) private var markDrop: CGFloat = 6

    init(
        files: [ParkedFile],
        accent: Accent,
        show: @escaping (ParkedFile) -> Void,
        acknowledge: @escaping () -> Void
    ) {
        self.files = files
        self.accent = accent
        self.show = show
        self.acknowledge = acknowledge
    }

    // MARK: - What it says

    /// What the other versions are called — the name and not the path,
    /// because the name is what the user will see the file called when they
    /// go looking for it.
    private var names: String {
        files.map(\.name).formatted(.list(type: .and))
    }

    /// The news, which is a file name: without it the only sign that a
    /// version of this day was set aside is a file nobody has a reason to
    /// look for.
    var sentence: String {
        files.count == 1
            ? "Another version of this day was kept as \(names)"
            : "Other versions of this day were kept, as \(names)"
    }

    /// And the whole of what it means. Two devices wrote one day and both
    /// versions are in the folder; there is nothing here for anybody to put
    /// right.
    var reassurance: String { "Nothing was lost." }

    /// Where the user is sent, said as what happens rather than as what the
    /// app would be doing: the design file's "Compare" named a screen Aujour
    /// does not have and will not have.
    static let action = "Show in Files"

    // MARK: - What it is drawn in

    // Every colour here is one of the identity's own, which is what "never an
    // error colour" comes to in practice — there is no error colour in the
    // palette to reach for. A shape takes the accent and a word takes its ink
    // shade, which is the one rule the palette rests on (`Accent.inkColor`).

    var mark: UIColor { accent.uiColor }
    var actionInk: UIColor { accent.inkColor }
    var sentenceInk: UIColor { Palette.ink }
    var reassuranceInk: UIColor { Palette.inkMuted }
    var dismissInk: UIColor { Palette.inkFaint }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.comfortable) {
            Circle()
                .fill(Color(mark))
                .frame(width: markSize, height: markSize)
                .padding(.top, markDrop)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(sentence)
                    .lettering(.rowValue)
                    .foregroundStyle(Color(sentenceInk))
                    .accessibilityIdentifier("parkedFileNotice")
                Text(reassurance)
                    .lettering(.note)
                    .foregroundStyle(Color(reassuranceInk))
                if let oneOfThem = files.first {
                    // One of them and not each: they were all set aside
                    // beside the same Entry, so the folder this opens is the
                    // folder the rest of them are in.
                    Button(Self.action) { show(oneOfThem) }
                        .lettering(.chipLabel)
                        .foregroundStyle(Color(actionInk))
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.tight)
                        .accessibilityIdentifier("showParkedFileInFiles")
                }
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: acknowledge)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Color(dismissInk))
                .accessibilityIdentifier("dismissParkedFileNotice")
        }
        .padding(Spacing.comfortable)
        // The system's own glass, rather than the palette's fill, ring and
        // pair of shadows — the same call the date pill makes, and for the
        // same reason. This is a pane over a page somebody is writing on and
        // scrolling under it: it has to refract what goes past, light its own
        // edge against it, and go opaque for a reader who has asked for less
        // transparency, none of which a colour can do. `Palette.glass` is the
        // account of it kept for the grounds the contrast floor is measured
        // against (ADR 0006).
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Rounding.card))
        .padding(.horizontal, Spacing.comfortable)
        .padding(.bottom, Spacing.close)
    }
}

/// The reminder cannot arrive, said where somebody is setting one.
///
/// Two screens set the same reminder — the welcome's last page and the journal
/// sheet — and a device that has said no makes both of them untrue in exactly
/// the same way, so they say so in the same words. The way back is Settings and
/// nothing on either screen, which is the whole of what there is to say.
struct NudgesAreTurnedOffNotice: View {
    /// What a test finds it by: either screen can be the one it is on.
    let identifier: String

    var body: some View {
        Text(
            """
            Notifications are turned off for Aujour, so this won't arrive. \
            Turn them on in Settings › Notifications › Aujour.
            """
        )
        .lettering(.note)
        // The identity's own alarm rather than the system's red, which reads
        // at 3.18:1 on the paper this lands on — a sentence under the floor,
        // on the one screen where the sentence is the whole point (ADR 0006).
        .foregroundStyle(Palette.alarmColor)
        .accessibilityIdentifier(identifier)
    }
}

/// Something that went wrong with a folder, in the two sentences it takes to
/// say what and what to do — the compact form, for beside the thing it is
/// about.
struct FolderProblemNotice: View {
    let problem: StorageProblem

    /// What a test would find it by — the sheet can show two of these at
    /// once, about two different folders.
    let identifier: String

    var body: some View {
        VStack(spacing: Spacing.tight) {
            // Two steps of ink rather than two weights of one. A folder that
            // could not be read is not an Empty State and must not start
            // looking like one (`CONTEXT.md`), so neither line is in the
            // identity's prose voice — what tells them apart is the ink and
            // the size, which is how the rest of the app says "this line, then
            // the one explaining it".
            Text(problem.message)
                .lettering(.rowLabel)
                .foregroundStyle(Palette.inkColor)
                .accessibilityIdentifier(identifier)
            Text(problem.suggestion)
                .lettering(.note)
                .foregroundStyle(Palette.inkMutedColor)
        }
        .multilineTextAlignment(.center)
    }
}

/// A folder that could not be reached. Says what happened and what to do, and
/// offers the retry — never a blank page that reads as a lost journal.
struct StorageProblemNotice: View {
    let problem: StorageProblem

    /// The way back to the folder Aujour finds for itself, offered only when
    /// the folder that failed is one the user chose.
    ///
    /// Without it, a vault folder renamed on another device is a journal the
    /// user cannot get out of: retrying a folder that is gone will go on
    /// failing, and their words are somewhere Aujour can no longer be pointed.
    var useAujoursOwnFolder: (() async -> Void)? = nil

    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(problem.message, systemImage: "exclamationmark.icloud")
                .accessibilityIdentifier("storageProblem")
        } description: {
            Text(problem.suggestion)
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
            .accessibilityIdentifier("retryOpeningJournal")

            if let useAujoursOwnFolder {
                Button("Use Aujour's Own Folder") {
                    Task { await useAujoursOwnFolder() }
                }
                // Not the sheet's button of the same words: a journal that
                // could not be opened can have both on screen at once.
                .accessibilityIdentifier("recoverWithAujoursOwnFolder")
            }
        }
    }
}

// Previews journal into a scratch folder rather than into whatever this Mac's
// iCloud Drive holds, so each one shows the state it is named after.
#Preview("Journaling into iCloud Drive") {
    ContentView(
        journal: Journal.inAPreview(over: .preview(.iCloudDrive)),
        appearance: .inMemory()
    )
}

#Preview("Journaling on the device") {
    ContentView(
        journal: Journal.inAPreview(over: .preview(.onThisDevice)),
        appearance: .inMemory()
    )
}

#Preview("Journaling into a folder of the user's own") {
    ContentView(
        journal: Journal.inAPreview(over: .previewCustomFolder),
        appearance: .inMemory()
    )
}

#Preview("Nowhere to journal") {
    ContentView(
        journal: Journal.inAPreview(over: .preview(nil)),
        appearance: .inMemory()
    )
}

extension JournalRootLocator {
    /// A locator over a scratch folder, pinned to one of Aujour's own
    /// locations — or to none, for the failure the user would see with iCloud
    /// Drive off and the app's own folder unreachable.
    ///
    /// Reachable from the other screens' previews too: any of them that takes
    /// a whole `Journal` needs one that is not this Mac's own.
    static func preview(_ location: JournalRoot.DefaultFolder?) -> JournalRootLocator {
        let folder = URL.temporaryDirectory.appending(path: "AujourPreview/\(location?.rawValue ?? "none")")
        return JournalRootLocator(
            iCloudDocuments: { location == .iCloudDrive ? folder : nil },
            onThisDeviceDocuments: { location == .onThisDevice ? folder : URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in }
        )
    }

    /// A locator already pointed at a folder of the user's own, so the sheet
    /// shows what someone journaling inside an Obsidian vault sees.
    fileprivate static var previewCustomFolder: JournalRootLocator {
        let vault = URL.temporaryDirectory.appending(path: "AujourPreview/Vault/Journal")
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        // Straight to a bookmark: a preview has no picker to tap.
        let bookmark = try? vault.bookmarkData()
        return JournalRootLocator(
            iCloudDocuments: { nil },
            onThisDeviceDocuments: { URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in },
            customRoot: CustomJournalRoot(
                storedBookmark: { bookmark },
                rememberBookmark: { _ in }
            )
        )
    }
}
