import SwiftUI
import AujourCore

/// The Journal a month at a time: a dot on every day that was written on, and
/// the way back into any of them.
///
/// The view holds no rules. Which days are marked, which day is today, and
/// which days can be opened at all are ``JournalCalendar``'s — including the
/// one this screen exists to show, that a day with no file can still be
/// opened and written into (backfill), while a day that has not arrived
/// cannot.
struct JournalCalendarView: View {
    let calendar: JournalCalendar

    /// The Journal the calendar is over, for the one thing a day being opened
    /// needs that the grid does not know: a day two devices wrote is settled
    /// before it is put in front of anybody, and the file set aside is said
    /// on that day's own screen.
    let journal: Journal

    /// The day being written in, pushed on top of the grid — nil while the
    /// grid is what is on screen.
    @State private var opened: OpenedDay?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 7
    )

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            grid
            Spacer(minLength: 0)
            // Between two spacers, so that whichever of the two it is sits in
            // the middle of the room the grid left rather than clinging to the
            // bottom of it.
            if let nothingToShow = calendar.nothingToShow {
                NothingOnTheCalendar(nothingToShow: nothingToShow, month: calendar.month.name)
                Spacer(minLength: 0)
            }
            if let problem = calendar.problem {
                IndicatorsProblemNotice(problem: StorageProblem(problem))
            }
        }
        .padding(.horizontal, 12)
        .navigationTitle("Your journal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { opened in
            EntryView(
                editor: opened.editor,
                photographsFrom: journal.photoLibrary,
                placesFrom: journal.places
            )
                .parkedFilesNotice(from: journal, for: opened.day)
                // With its year: a day reached from the calendar can be years
                // back, and every February has a 14th.
                .navigationTitle(opened.day.spelledOut(withYear: true))
                .navigationBarTitleDisplayMode(.inline)
        }
        // Read on the way in rather than remembered: the indicators are a
        // scan of the folder and nothing else, so this is where they come
        // from (ADR 0001).
        .task { await calendar.scan() }
        .onChange(of: opened) { left, arrived in
            // Back from a day: whatever was typed into it has a moment to
            // land, and then the folder is read again — which is what puts
            // the dot on a day that has just been filled in.
            guard arrived == nil, let left else { return }
            Task {
                await left.editor.save()
                await calendar.scan()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The same last chance today's Entry gets: a day being filled in
            // when the app goes away has no next second to be saved in.
            guard phase == .inactive || phase == .background, let opened else { return }
            Task { await opened.editor.save() }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") {
                calendar.showPreviousMonth()
            }
            .accessibilityIdentifier("previousMonth")

            Spacer()

            Text(calendar.month.name)
                .font(.headline)
                .accessibilityIdentifier("calendarMonth")

            Spacer()

            Button("Next month", systemImage: "chevron.right") {
                calendar.showNextMonth()
            }
            .accessibilityIdentifier("nextMonth")
        }
        .labelStyle(.iconOnly)
        .font(.title3)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Self.columns, spacing: 2) {
            // By offset, because a week has two days with the same initial
            // in most languages and `id: \.self` would collapse them.
            ForEach(Array(calendar.month.weekdayNames.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Self.columns, spacing: 2) {
            // One sequence rather than a row of seven per week: a cell is
            // identified by its place in the grid, and seven identities
            // repeated once per row would let cells swap what they do the
            // moment a scan changes one of them. The padding a month starts
            // and ends with is part of the sequence, which is what keeps a
            // column one weekday all the way down.
            ForEach(Array(calendar.month.cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(day: day) { open(day.day) }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func open(_ day: JournalDay) {
        // Today is not somewhere to go: it is the screen this calendar was
        // opened from, so tapping it goes back rather than forward. Which is
        // also what keeps the app to one editor per Entry — the one already
        // open over today's file, not a second autosaving over it.
        guard day != calendar.today else {
            dismiss()
            return
        }
        // Nothing for a day that has not arrived — the cell is disabled, and
        // this is the same refusal said where it cannot be tapped around.
        guard let editor = calendar.editor(for: day) else { return }
        opened = OpenedDay(day: day, editor: editor)
        Task {
            // Before it is read, for the same reason today's Entry is: a past
            // day can have been written on two devices too — backfilled on the
            // iPad on the train and on the iPhone that evening — and the
            // version that loses its path is set aside rather than left in
            // iCloud where nobody would ever see it.
            await journal.settleAnyDivergence(before: editor)
            await editor.open()
        }
    }
}

/// A day open in front of the user, on top of the screen they reached it
/// from — the calendar, or a search result.
///
/// Identified by its day, because that is an Entry's identity — the editor
/// over March 1st is the same thing on screen however often the list or the
/// grid redraws underneath it.
struct OpenedDay: Hashable {
    let day: JournalDay
    let editor: EntryEditor

    static func == (lhs: OpenedDay, rhs: OpenedDay) -> Bool { lhs.day == rhs.day }

    func hash(into hasher: inout Hasher) { hasher.combine(day) }
}

/// One day in the grid: its number, whether it was written on, and whether it
/// can be opened.
private struct DayCell: View {
    let day: JournalCalendar.Day
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 3) {
                Text(day.day.day.formatted(.number.grouping(.never)))
                    .font(.callout.weight(day.relation == .current ? .bold : .regular))
                // Always laid out, shown only when the day has a file: a dot
                // that takes up no room when it is absent would move every
                // other number in the row.
                Circle()
                    .frame(width: 5, height: 5)
                    .opacity(day.isJournaled ? 1 : 0)
            }
            // Dimmed rather than hidden: a day that has not arrived is on
            // the calendar to be seen, and only not to be written in.
            .opacity(day.isOpenable ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                day.relation == .current ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Visible and not writable: the day is on the calendar, and there is
        // no Entry to write before it has arrived.
        .disabled(!day.isOpenable)
        .accessibilityIdentifier("day-\(day.day)")
        .accessibilityLabel(day.day.spelledOut(withYear: true))
        .accessibilityValue(day.isJournaled ? "Written" : "Not written")
    }
}

/// A month with no dots on it, said as the thing it is.
///
/// A grid of numbers and nothing else is the least legible screen in the app:
/// it looks the same whether the journal has not been started, has not been
/// read, or simply does not reach into the month somebody scrolled to. What
/// the calendar can prove of those is what is said here, and the two it cannot
/// are said elsewhere — a folder still being read says nothing at all, and a
/// folder that would not answer gets the notice below.
///
/// The beginning of a journal gets the room, and the invitation with it: the
/// grid *is* the way in — every day up to today can be tapped and written — and
/// somebody who has just installed the app has no reason to know that yet.
private struct NothingOnTheCalendar: View {
    let nothingToShow: JournalCalendar.NothingToShow

    /// The month on screen, spelled out — for the case where the answer is
    /// about this month rather than about the journal.
    let month: String

    var body: some View {
        switch nothingToShow {
        case .aJournalNobodyHasWrittenIn:
            ContentUnavailableView {
                Label("Your journal starts here", systemImage: "calendar.badge.plus")
                    .accessibilityIdentifier("aJournalNobodyHasWrittenIn")
            } description: {
                Text(
                    """
                    Tap any day up to today and write it. Nothing goes into \
                    your folder until you do.
                    """
                )
            }

        case .aMonthNobodyWroteIn:
            // A line and not a page: the journal has a past, this month is
            // simply not part of it, and a full-height notice over an ordinary
            // gap would read as something having gone wrong.
            Text("Nothing written in \(month).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("aMonthNobodyWroteIn")
        }
    }
}

/// Indicators that could not be read. Says so rather than showing a month
/// with no dots on it, which is what a journal nobody has written in looks
/// like (ADR 0001).
private struct IndicatorsProblemNotice: View {
    let problem: StorageProblem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aujour couldn't read your journal folder, so days you've written on may not be marked.")
                    .font(.footnote.weight(.semibold))
                Text(problem.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("indicatorsProblem")
    }
}

// Previews journal into memory, so the month on screen is the one the preview
// is named after rather than whatever this Mac's journal folder holds.
#Preview("A month with a few days written") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let written = [today.adding(days: -1), today.adding(days: -3), today.adding(days: -8)]

    NavigationStack {
        JournalCalendarView(
            calendar: JournalCalendar(
                store: InMemoryJournalStore(
                    Dictionary(
                        uniqueKeysWithValues: written.map {
                            (PathTemplate.default.render($0), "Words.\n")
                        }
                    )
                )
            ),
            journal: Journal.inAPreview(over: .preview(.onThisDevice))
        )
    }
}

#Preview("A month nobody has written in") {
    NavigationStack {
        JournalCalendarView(
            calendar: JournalCalendar(store: InMemoryJournalStore()),
            journal: Journal.inAPreview(over: .preview(.onThisDevice))
        )
    }
}
