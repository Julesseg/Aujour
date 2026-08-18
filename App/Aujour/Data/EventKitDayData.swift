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
    /// Which of the two an item comes from — the one thing the two reads do
    /// not have in common.
    enum Kind: Sendable {
        case events
        case reminders

        var entityType: EKEntityType {
            switch self {
            case .events: .event
            case .reminders: .reminder
            }
        }
    }

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
            .events: EventKitSource(kind: .events, reading: self),
            .reminders: EventKitSource(kind: .reminders, reading: self),
        ])
    }

    /// The day's items, or none — see the type's discussion for why none is
    /// so often the answer and why that is not a failure.
    fileprivate func items(_ kind: Kind, during day: DateInterval) async -> [DayItem] {
        // Full access and nothing less: an app allowed only to *add* events
        // cannot read the day, and neither can one nobody has been asked
        // about yet.
        guard EKEventStore.authorizationStatus(for: kind.entityType) == .fullAccess else {
            return []
        }
        switch kind {
        case .events: return events(during: day)
        case .reminders: return await reminders(during: day)
        }
    }

    /// Asks for access, once, and only where nobody has been asked yet.
    ///
    /// Called before a day is opened rather than while one is being spawned;
    /// a permission already decided — granted or refused — is left decided,
    /// because the way back from a refusal is Settings and not another alert.
    fileprivate func prepare(_ kind: Kind) async {
        guard EKEventStore.authorizationStatus(for: kind.entityType) == .notDetermined else {
            return
        }
        switch kind {
        case .events: _ = try? await store.requestFullAccessToEvents()
        case .reminders: _ = try? await store.requestFullAccessToReminders()
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

    private func reminders(during day: DateInterval) async -> [DayItem] {
        let matching = store.predicateForIncompleteReminders(
            withDueDateStarting: day.start,
            ending: day.end,
            calendars: nil
        )
        // EventKit answers reminders with a callback and no `async` twin, and
        // the reminders themselves may not leave the queue it answers on — so
        // what crosses back is the day's items, made here.
        let items: [DayItem] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: matching) { reminders in
                continuation.resume(returning: dayItems(from: reminders ?? []))
            }
        }
        // Sorted here rather than by the predicate, which has no order to ask
        // for: earliest first, and the ones due today at no particular hour
        // after them.
        return items.sorted {
            switch ($0.time, $1.time) {
            case (let mine?, let theirs?): mine < theirs
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): false
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
    let kind: EventKitDayData.Kind
    let reading: EventKitDayData

    func items(during day: DateInterval) async -> [DayItem] {
        await reading.items(kind, during: day)
    }

    func prepare() async {
        await reading.prepare(kind)
    }
}

extension DayItem {
    /// An item, or nothing at all for one with no name.
    ///
    /// A nameless event would be written as a bullet with nothing after it —
    /// a line in somebody's journal that says only that a line was written.
    fileprivate init?(named title: String?, at time: Date?) {
        let named = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else { return nil }
        self.init(title: named, time: time)
    }
}

/// Reminders as items, made where EventKit hands them over.
///
/// Free of the actor deliberately: this is called from EventKit's own
/// completion, which is nobody's isolation, and an `EKReminder` may not travel
/// any further than the queue it arrived on.
private func dayItems(from reminders: [EKReminder]) -> [DayItem] {
    reminders.compactMap { reminder in
        DayItem(named: reminder.title, at: reminder.dueTime)
    }
}

extension EKReminder {
    /// When in the day it is due, or `nil` for one due on the day and at no
    /// particular time — which is most of them.
    fileprivate var dueTime: Date? {
        guard let due = dueDateComponents, due.hour != nil else { return nil }
        return due.date ?? Calendar.current.date(from: due)
    }
}
