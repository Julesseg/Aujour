import SwiftUI
import UIKit

import AujourCore

/// The Suggestions key pressed, and the way back into the Entry for what is
/// tapped on the sheet it puts up.
///
/// ``PhotoRequest``'s twin, and shaped like it for the same reason: the key is
/// pressed on a text view and the tapping happens on a sheet, so what crosses
/// between them is where the caret was, folded into a closure that writes
/// its attachment there, and a word for when the sheet has gone.
struct SuggestionsRequest: Identifiable {
    /// New for every press, so that pressing the key twice puts the sheet up
    /// twice.
    let id = UUID()

    /// Writes this photograph into the Entry where the caret was when the key
    /// was pressed.
    let insert: (Attachment) -> Void

    /// Writes one line of the day's data at that same caret. The editor owns
    /// the shared on-its-own-line placement rule, so pictures and events stay
    /// in one contiguous insertion list.
    let insertLine: (String) -> Void

    /// The sheet has gone, with or without anything written. Somebody who
    /// pressed a key above the keyboard was writing, and the keyboard is asked
    /// back.
    let finished: () -> Void
}

/// The sheet the Suggestions key puts up: the day's own material, offered to
/// be written into it.
///
/// A journal is written in the evening about a day that is already on the
/// phone — in pictures, in the calendar, in what the list said — so the
/// shortest way between the two is a sheet of that day's own things, one tap
/// each. Everything on it is an insertion, which is why it is reached from the
/// row above the keyboard and nowhere else: an insertion needs a caret, and a
/// day being read has none.
///
/// One section per kind, drawn only where there is something to offer, and one
/// line for the whole sheet where there is nothing in any of them. The
/// photographs are what M1 has; the day's events and its reminders come next,
/// and arrive as two more sections under this one.
///
/// The sheet holds no rules. Which photographs belong to the day, whether
/// there is anything to offer and what asking for the library means are
/// ``AujourCore/PhotoSuggestions``'s, unit-tested on Linux; what a tapped
/// photograph becomes on its way into the folder is ``InsertedPhotographs``'s;
/// where the markdown lands is the editor's (``SuggestionsRequest``). What is
/// here is the grid, the words for a count, and the offer to look.
struct SuggestionsSheet: View {
    /// The Journal Day being written about, whose material is offered — a
    /// Monday filled in on Friday is offered Monday's.
    let day: JournalDay

    /// The pipeline into the folder, and the one place that says whether a
    /// photograph is already on its way.
    let photographs: InsertedPhotographs

    /// Where a tapped photograph goes — the request's own closure, which knows
    /// where the caret was.
    let insert: (Attachment) -> Void

    /// Where an event's rendered line goes — the same request anchor a
    /// photograph uses, so later taps stay adjacent.
    let insertLine: (String) -> Void

    /// The day's events, permission standing, and permission request. The
    /// Journal hands these over so this view reads no device service itself.
    let eventsFrom: (JournalDay) async -> [DayItem]
    let eventAccess: () -> DayDataAccess
    let prepareEvents: () async -> Void
    let eventFormat: DataPlaceholderFormat

    /// The day's reminders, permission standing, and permission request. Like
    /// events, these arrive from the Journal so this view never reads EventKit.
    let remindersFrom: (JournalDay) async -> [DayItem]
    let reminderAccess: () -> DayDataAccess
    let prepareReminders: () async -> Void
    let reminderFormat: DataPlaceholderFormat

    /// The day's photographs, read out of the library for the day on screen.
    /// Made with the sheet and gone with it: the library is read when it is
    /// looked at and not while the day is being written.
    @State private var suggestions: PhotoSuggestions

    /// The event section's answer for this one opening. Like the photograph
    /// section, it is read when the sheet comes up and not while typing.
    @State private var eventState = DaySuggestionsState.checking

    /// The reminder section's answer for this one opening.
    @State private var reminderState = DaySuggestionsState.checking

    /// Rows written during this opening. The Entry is never read back: closing
    /// the sheet forgets these, and reopening offers the day afresh.
    @State private var insertedEventIndices: Set<Int> = []

    /// The sheet's own insertion record. It is distinct from a reminder that
    /// had already been completed on its day.
    @State private var insertedReminderIndices: Set<Int> = []

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - day: the Journal Day whose material is offered.
    ///   - library: where its photographs are read from. `nil` is a sheet with
    ///     no library behind it — nothing from the day, ever, which is what a
    ///     preview and a test of something else want.
    ///   - photographs: the way a tapped photograph reaches the folder.
    ///   - insert: the way a photograph reaches the Entry.
    init(
        for day: JournalDay,
        photographsFrom library: (any PhotoLibrary)?,
        through photographs: InsertedPhotographs,
        inserting insert: @escaping (Attachment) -> Void,
        insertingLine: @escaping (String) -> Void,
        eventsFrom: @escaping (JournalDay) async -> [DayItem] = { _ in [] },
        eventAccess: @escaping () -> DayDataAccess = { .refused },
        preparingEvents: @escaping () async -> Void = {},
        formattingEventsWith eventFormat: DataPlaceholderFormat = .default(for: .events),
        remindersFrom: @escaping (JournalDay) async -> [DayItem] = { _ in [] },
        reminderAccess: @escaping () -> DayDataAccess = { .refused },
        preparingReminders: @escaping () async -> Void = {},
        formattingRemindersWith reminderFormat: DataPlaceholderFormat = .default(for: .reminders)
    ) {
        self.day = day
        self.photographs = photographs
        self.insert = insert
        self.insertLine = insertingLine
        self.eventsFrom = eventsFrom
        self.eventAccess = eventAccess
        self.prepareEvents = preparingEvents
        self.eventFormat = eventFormat
        self.remindersFrom = remindersFrom
        self.reminderAccess = reminderAccess
        self.prepareReminders = preparingReminders
        self.reminderFormat = reminderFormat
        _suggestions = State(wrappedValue: PhotoSuggestions(from: library))
    }

    var body: some View {
        NavigationStack {
            List {
                theEvents
                theReminders
                thePhotographs
                nothingAtAll
            }
            // The sheet's own paper rather than the system's grouped grey, and
            // the rows on the identity's card — the same ground the place
            // widget's list stands on (`PlaceWidget`), so that one sheet looks
            // like one app whichever key put it up.
            .scrollContentBackground(.hidden)
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelSuggestions")
                }
            }
            // Dimmed while a photograph is on its way. One that is only in
            // iCloud takes seconds to come down, and a grid that looked
            // exactly the same throughout would be one somebody taps again —
            // the taps are refused underneath this too (``InsertedPhotographs``),
            // and this is only what says so.
            .opacity(photographs.isAddingOne ? 0.5 : 1)
            .disabled(photographs.isAddingOne)
        }
        // Read when the sheet comes up and not before: the library is asked
        // about one day, at the moment somebody wants its photographs.
        .task(id: day) { await suggestions.look(for: day) }
        .task(id: day) { await lookForEvents() }
        .task(id: day) { await lookForReminders() }
        // Half the screen to begin with, and draggable to all of it: a day at
        // the seaside is two hundred photographs, and a sheet that could only
        // ever be half is one nobody can reach the bottom of.
        .presentationDetents([.medium, .large])
        .sheetChrome()
        .accessibilityIdentifier("suggestionsSheet")
    }

    // MARK: - Nothing to suggest

    /// The one line the sheet says about itself, and only where every section
    /// has come up empty and there is nothing left to ask about.
    ///
    /// Once for the whole sheet rather than once per section: a day with no
    /// photographs has no photograph section rather than a sentence saying so,
    /// and only a day with nothing in any of them says so (`CONTEXT.md`,
    /// **Suggestions**).
    @ViewBuilder private var nothingAtAll: some View {
        if suggestions.state == .nothingToOffer,
            eventState == .nothingToOffer,
            reminderState == .nothingToOffer
        {
            Section {
                Text("Nothing to suggest from this day.")
                    .foregroundStyle(Palette.inkMutedColor)
                    .accessibilityIdentifier("nothingToSuggest")
            }
            .settingsRows()
        }
    }

    // MARK: - The day's events

    /// Events are a timeline: what the day held without an hour first, then
    /// the timed part in start order. Calendar names never cross the Day Data
    /// seam, so there is only the calendar's colour to draw beside each row.
    @ViewBuilder private var theEvents: some View {
        switch eventState {
        case .checking, .nothingToOffer:
            EmptyView()

        case .couldLook:
            Section {
                Button("Show events from this day", systemImage: "calendar") {
                    Task { await askToLookAtEvents() }
                }
                .accessibilityIdentifier("showEventSuggestions")
            }
            .settingsRows()

        case .offering(let events):
            let timeline = DayItemTimeline(events)
            let allDay = timeline.allDay
            let timed = timeline.timed

            Section {
                ForEach(Array(allDay.enumerated()), id: \.offset) { index, item in
                    eventRow(item, at: index)
                }
                ForEach(Array(timed.enumerated()), id: \.offset) { index, item in
                    eventRow(item, at: allDay.count + index)
                }
            } header: {
                Text("Events")
                    .textCase(nil)
                    .accessibilityIdentifier("eventSuggestions")
            }
            .settingsRows()
        }
    }

    /// One event's row, which remains available to VoiceOver after it has
    /// been written but is inert after its one insertion.
    private func eventRow(_ item: DayItem, at index: Int) -> some View {
        let inserted = insertedEventIndices.contains(index)
        return Button {
            guard !inserted else { return }
            insertLine(eventFormat.line(for: item, timeZone: .current, locale: .current))
            insertedEventIndices.insert(index)
        } label: {
            HStack(spacing: Spacing.close) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colour(of: item))
                    .frame(width: 4, height: 30)
                    .accessibilityHidden(true)
                Text(item.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(eventTime(for: item))
                    .foregroundStyle(Palette.inkMutedColor)
                    .monospacedDigit()
                if inserted {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("eventSuggestion\(index)")
        .accessibilityLabel(eventLabel(for: item, inserted: inserted))
    }

    private func colour(of item: DayItem, defaultingTo fallback: Color = .clear) -> Color {
        guard let colour = item.color else { return fallback }
        return Color(red: colour.red, green: colour.green, blue: colour.blue)
    }

    private func timeRange(starting start: Date, ending end: Date?) -> String {
        let beginning = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
        guard let end else { return beginning }
        return "\(beginning) – \(end.formatted(Date.FormatStyle(date: .omitted, time: .shortened)))"
    }

    private func eventLabel(for item: DayItem, inserted: Bool) -> String {
        return [item.title, eventTime(for: item), inserted ? "Inserted" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func eventTime(for item: DayItem) -> String {
        guard let time = item.time else { return "All day" }
        return timeRange(starting: time, ending: item.end)
    }

    private func lookForEvents() async {
        switch eventAccess() {
        case .undecided:
            eventState = .couldLook
        case .refused:
            eventState = .nothingToOffer
        case .allowed:
            let found = await eventsFrom(day)
            eventState = found.isEmpty ? .nothingToOffer : .offering(found)
        }
    }

    private func askToLookAtEvents() async {
        await prepareEvents()
        await lookForEvents()
    }

    // MARK: - The day's reminders

    /// Reminders are a checklist in the source's order, which keeps their
    /// individual insertions in the same order `{{reminders}}` would write.
    @ViewBuilder private var theReminders: some View {
        switch reminderState {
        case .checking, .nothingToOffer:
            EmptyView()

        case .couldLook:
            Section {
                Button("Show reminders from this day", systemImage: "checklist") {
                    Task { await askToLookAtReminders() }
                }
                .accessibilityIdentifier("showReminderSuggestions")
            }
            .settingsRows()

        case .offering(let reminders):
            Section {
                ForEach(Array(reminders.enumerated()), id: \.offset) { index, item in
                    reminderRow(item, at: index)
                }
            } header: {
                Text("Reminders")
                    .textCase(nil)
                    .accessibilityIdentifier("reminderSuggestions")
            }
            .settingsRows()
        }
    }

    /// The leading box says whether this reminder was already done. The
    /// trailing tick only says this opening has inserted its line.
    private func reminderRow(_ item: DayItem, at index: Int) -> some View {
        let inserted = insertedReminderIndices.contains(index)
        return Button {
            guard !inserted else { return }
            insertLine(reminderFormat.line(for: item, timeZone: .current, locale: .current))
            insertedReminderIndices.insert(index)
        } label: {
            HStack(spacing: Spacing.close) {
                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(colour(of: item, defaultingTo: .secondary))
                    .accessibilityHidden(true)
                Text(item.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let time = item.time {
                    Text(time.formatted(Date.FormatStyle(date: .omitted, time: .shortened)))
                        .foregroundStyle(Palette.inkMutedColor)
                        .monospacedDigit()
                }
                if inserted {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("reminderSuggestion\(index)")
        .accessibilityLabel(reminderLabel(for: item, inserted: inserted))
    }

    private func reminderLabel(for item: DayItem, inserted: Bool) -> String {
        [
            item.isDone ? "Done" : "Not done",
            item.title,
            item.time.map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened)) },
            inserted ? "Inserted" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func lookForReminders() async {
        switch reminderAccess() {
        case .undecided:
            reminderState = .couldLook
        case .refused:
            reminderState = .nothingToOffer
        case .allowed:
            let found = await remindersFrom(day)
            reminderState = found.isEmpty ? .nothingToOffer : .offering(found)
        }
    }

    private func askToLookAtReminders() async {
        await prepareReminders()
        await lookForReminders()
    }

    // MARK: - The day's own photographs

    /// The day's photographs, or the offer to look for them — and nothing at
    /// all where the library is refused, this device has none, or the camera
    /// missed the day.
    ///
    /// The one thing always drawn is the offer: a permission nobody has been
    /// asked about is a button in the words of the thing it would read, and
    /// tapping it is what asks — never opening the day, and never opening the
    /// sheet.
    @ViewBuilder private var thePhotographs: some View {
        switch suggestions.state {
        case .nothingToOffer:
            // Said once for the sheet, by `nothingAtAll` above, and not here:
            // a section that drew its own absence would be a sentence about
            // photographs on a day whose meetings are the thing on offer.
            EmptyView()

        case .couldLook:
            // The one place in Aujour that asks for a photo library besides
            // the `{{location}}` widget, and it asks because a finger landed
            // here. A day being opened never does.
            Section {
                Button("Show photos from this day", systemImage: "photo.on.rectangle.angled") {
                    Task { await suggestions.askToLook() }
                }
                .accessibilityIdentifier("showPhotoSuggestions")
            }
            .settingsRows()

        case .offering(let found):
            Section {
                // Lazily, because a day at the seaside is two hundred
                // photographs and only the first rows are ever on screen —
                // and a thumbnail is asked for by the square that shows it.
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: Self.narrowest, maximum: Self.square),
                            spacing: Spacing.close
                        )
                    ],
                    spacing: Spacing.close
                ) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { nth, photograph in
                        APhotographOfTheDay(
                            photograph: photograph,
                            suggestions: suggestions,
                            identifier: "photoSuggestion\(nth)",
                            add: { photograph in Task { await add(photograph) } }
                        )
                    }
                }
                .padding(.vertical, Spacing.tight)
            } header: {
                Text(headline(for: found.count))
                    // In the words the count was written in: a header is set
                    // in capitals by default, and "2 PHOTOS FROM THIS DAY" is
                    // a heading shouting about a count.
                    .textCase(nil)
                    .accessibilityIdentifier("photoSuggestions")
            }
            .settingsRows()
        }
    }

    /// "3 photos from this day" — the day's own count, because the sheet is
    /// about the day on screen and not about today.
    private func headline(for count: Int) -> String {
        count == 1 ? "1 photo from this day" : "\(count) photos from this day"
    }

    /// The most a square in the grid comes out at, and what a thumbnail is
    /// fetched for.
    ///
    /// `nonisolated` because it is also what the library sizes a thumbnail
    /// against, and that happens off the main actor — a square drawn at one
    /// size and fetched at another is somebody's whole photograph decoded and
    /// thrown away, once per square.
    nonisolated static let square: CGFloat = 150

    /// The least a square comes out at, which is what decides how many go in
    /// a row: three across a phone, more across a sheet on an iPad.
    private static let narrowest: CGFloat = 96

    // MARK: - One tap

    /// One tap on one of the day's photographs, and everything after it.
    ///
    /// A photograph closes the sheet: it did what it was for. It closes on a
    /// failure too, because what went wrong is said under the day
    /// (``EntryView``) and a notice behind a sheet is a notice nobody reads.
    /// It stays only when nothing happened at all, which leaves the way to try
    /// again where it was.
    private func add(_ photograph: DayPhotograph) async {
        let attachment = await photographs.insert(photograph, from: suggestions)
        if let attachment { insert(attachment) }
        guard attachment != nil || photographs.problem != nil else { return }
        dismiss()
    }
}

/// What one data section knows during this opening of Suggestions. It starts
/// empty until the sheet reads permission, so opening the sheet never asks.
private enum DaySuggestionsState: Equatable {
    case checking
    case couldLook
    case offering([DayItem])
    case nothingToOffer
}

/// One square in the grid: the photograph, and the tap that puts it in the
/// day.
private struct APhotographOfTheDay: View {
    let photograph: DayPhotograph
    let suggestions: PhotoSuggestions

    /// What a UI test finds this one by. By position in the grid, which is
    /// the only thing about a photograph a test outside the app can know —
    /// the library's own name for it is the library's.
    let identifier: String

    let add: (DayPhotograph) -> Void

    /// The thumbnail, once the library has handed one over. A square of
    /// nothing until then, which is what a photograph still coming down from
    /// iCloud looks like.
    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            add(photograph)
        } label: {
            // Square whatever the column came out at, and the photograph
            // filling it edge to edge.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Rounding.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Rounding.control, style: .continuous))
        }
        // Its own tap, and not the row's: buttons left to a list's own style
        // all fire together when the row is tapped.
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        // A square of pixels has nothing to say for itself, and the one thing
        // that tells two of them apart in a day is when each was taken.
        .accessibilityLabel("Photo taken at \(photograph.takenAt.formatted(date: .omitted, time: .shortened))")
        // Asked for by the square that shows it.
        .task(id: photograph.id) {
            thumbnail = await suggestions.thumbnail(of: photograph).flatMap(UIImage.init(data:))
        }
    }
}
