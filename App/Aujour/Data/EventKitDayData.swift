import EventKit
import Foundation

import AujourCore

/// The user's calendar and reminders, as the data placeholders read them.
///
/// An actor over one `EKEventStore`, because both placeholders read the same
/// thing and one connection to the calendar daemon is enough for both — and
/// because EventKit is not something to be in two places of at once. The
/// connection is made on the first question and not before, so a journal whose
/// Content Template never mentions the calendar never opens one.
///
/// Two promises hold this apart from what it wraps, and both are
/// ``DayItemSource``'s:
///
/// - **Reading never asks.** `items` reads the authorization status and
///   answers with nothing at all where it is anything but granted. It is
///   called with a day about to go on screen, and a spawn behind a system
///   alert is an Entry that does not appear until somebody answers one.
/// - **Reading never fails.** A calendar that is not there, not permitted or
///   not answering is a day with no meetings in it, which is a sentence the
///   Entry can be spawned from. Nothing about a permission ever reaches the
///   user as a journal that would not open (ADR 0001).
actor EventKitDayData {
    private var connection: EKEventStore?

    private var store: EKEventStore {
        if let connection { return connection }
        let opened = EKEventStore()
        connection = opened
        return opened
    }

    /// The seam Core spawns through: one source per data placeholder, both
    /// over this.
    nonisolated var dayData: DayData {
        DayData([
            .events: EventKitSource(placeholder: .events, reading: self),
            .reminders: EventKitSource(placeholder: .reminders, reading: self),
        ])
    }

    /// The day's items, or none — see the type's discussion for why none is
    /// so often the answer and why that is not a failure.
    fileprivate func items(
        for placeholder: DataPlaceholder,
        during day: DateInterval
    ) async -> [DayItem] {
        // Full access and nothing less: an app allowed only to *add* events
        // cannot read the day, and neither can one nobody has been asked
        // about yet.
        guard EKEventStore.authorizationStatus(for: entityType(for: placeholder)) == .fullAccess
        else { return [] }
        switch placeholder {
        case .events: return events(during: day)
        case .reminders: return await reminders(during: day)
        }
    }

    /// Asks for access, once, and only where nobody has been asked yet.
    ///
    /// Called before a day is opened rather than while one is being spawned;
    /// a permission already decided — granted or refused — is left decided,
    /// because the way back from a refusal is Settings and not another alert.
    fileprivate func prepare(for placeholder: DataPlaceholder) async {
        guard
            EKEventStore.authorizationStatus(for: entityType(for: placeholder)) == .notDetermined
        else { return }
        switch placeholder {
        case .events: _ = try? await store.requestFullAccessToEvents()
        case .reminders: _ = try? await store.requestFullAccessToReminders()
        }
    }

    /// Which of EventKit's two halves a placeholder is about.
    ///
    /// Switched over rather than mapped, so that a data placeholder added to
    /// Core is a build error here — the moment to decide whether EventKit is
    /// where it reads from at all.
    private nonisolated func entityType(for placeholder: DataPlaceholder) -> EKEntityType {
        switch placeholder {
        case .events: .event
        case .reminders: .reminder
        }
    }

    private func events(during day: DateInterval) -> [DayItem] {
        let matching = store.predicateForEvents(
            withStart: day.start,
            end: day.end,
            calendars: nil
        )
        return
            store
            .events(matching: matching)
            .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
            .compactMap { event in
                DayItem(
                    named: event.title,
                    // An event that began before this day did — a trip, a
                    // conference — has no hour *in* this day, so it is written
                    // as one of the things the day held rather than as
                    // something that started at yesterday's o'clock.
                    at: event.isAllDay || event.startDate < day.start ? nil : event.startDate
                )
            }
    }

    /// What the day's list held: what was still to do, and what got done.
    ///
    /// Two questions, because EventKit answers one at a time and a day needs
    /// both. Asking only what is incomplete is right for today and wrong for
    /// every day behind it: a Monday written up on Tuesday would have lost
    /// every reminder Monday actually got through — which is the half of the
    /// day most worth writing down, and exactly the case a backfill is for.
    ///
    /// The two answers overlap by a reminder or none, so they are joined on
    /// what EventKit calls a reminder rather than appended blindly.
    private func reminders(during day: DateInterval) async -> [DayItem] {
        let stillToDo = store.predicateForIncompleteReminders(
            withDueDateStarting: day.start,
            ending: day.end,
            calendars: nil
        )
        let gotDone = store.predicateForCompletedReminders(
            withCompletionDateStarting: day.start,
            ending: day.end,
            calendars: nil
        )

        var seen: Set<String> = []
        var items: [DayItem] = []
        for answer in [await fetch(matching: stillToDo), await fetch(matching: gotDone)] {
            for reminder in answer where seen.insert(reminder.id).inserted {
                items.append(reminder.item)
            }
        }
        // A reminders list is a set of things to do and not a timetable, so
        // the order is this app's to give it.
        return items.throughTheDay()
    }

    /// One predicate's worth of reminders, as items.
    ///
    /// EventKit answers reminders with a callback and no `async` twin, and the
    /// reminders themselves may not leave the queue it answers on — so what
    /// crosses back is the day's items, made there, each with the identity
    /// that says whether two answers are the same reminder.
    private func fetch(matching predicate: NSPredicate) async -> [(id: String, item: DayItem)] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: dayItems(from: reminders ?? []))
            }
        }
    }
}

/// One data placeholder's half of ``EventKitDayData``.
///
/// A value rather than the actor itself, because a source is one placeholder's
/// answer and the actor is both of them — and because this is what makes
/// `{{events}}` and `{{reminders}}` two sources over one connection.
private struct EventKitSource: DayItemSource {
    let placeholder: DataPlaceholder
    let reading: EventKitDayData

    func items(during day: DateInterval) async -> [DayItem] {
        await reading.items(for: placeholder, during: day)
    }

    func prepare() async {
        await reading.prepare(for: placeholder)
    }
}

/// Reminders as items, made where EventKit hands them over.
///
/// Free of the actor deliberately: this is called from EventKit's own
/// completion, which is nobody's isolation, and an `EKReminder` may not travel
/// any further than the queue it arrived on.
private func dayItems(from reminders: [EKReminder]) -> [(id: String, item: DayItem)] {
    reminders.compactMap { reminder in
        guard
            let item = DayItem(
                named: reminder.title,
                at: reminder.dueTime,
                isDone: reminder.isCompleted
            )
        else { return nil }
        return (reminder.calendarItemIdentifier, item)
    }
}

extension EKReminder {
    /// When in the day it is due, or `nil` for one due on the day and at no
    /// particular time — which is most of them.
    ///
    /// A reminder's due components are usually floating — "six in the evening",
    /// wherever you are — so they are resolved against the device's own
    /// calendar, which is the same zone the Entry around them is written in.
    fileprivate var dueTime: Date? {
        guard let due = dueDateComponents, due.hour != nil else { return nil }
        return due.date ?? Calendar.current.date(from: due)
    }
}
