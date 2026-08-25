import Foundation
import Testing

@testable import AujourCore

// The reminder is one gentle nudge a day and nothing else, so what there is to
// get right is which nudges exist: one per day at the time the user chose,
// none at all until they choose one, and none for a day whose Entry is already
// in the folder. All three are decided here, over a device that is told rather
// than rung — a notification centre and a permission alert are the app's, and
// neither is a thing this module has ever seen.

@MainActor
@Suite("The daily reminder")
struct DailyReminderTests {
    // MARK: - Whether there is a reminder at all

    @Test("a reminder nobody has set a time for books nothing")
    func offUntilATimeIsChosen() async {
        let device = ADeviceToNudge()
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        #expect(reminder.booked.isEmpty)
        #expect(await device.booked == [])
        // Booked all the same, and with nothing in it: a reminder turned off
        // has to take away what an earlier launch left pending.
        #expect(await device.bookings == 1)
    }

    @Test("a time chosen books one nudge a day, at that time")
    func oneADayAtTheChosenTime() async {
        let reminder = aReminder(at: TimeOfDay(hour: 21, minute: 30), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        #expect(reminder.booked.count == DailyReminder.daysBookedAhead)
        #expect(
            reminder.booked.map(\.day) == (0..<DailyReminder.daysBookedAhead).map {
                JournalDay(year: 2026, month: 3, day: 14).adding(days: $0)
            }
        )
        #expect(reminder.booked.first?.at == instant(2026, 3, 14, 21, 30, in: paris))
        #expect(reminder.booked.last?.at == instant(2026, 3, 20, 21, 30, in: paris))
    }

    @Test("the time already gone today is next asked tomorrow")
    func aTimeAlreadyPast() async {
        let reminder = aReminder(at: TimeOfDay(hour: 9, minute: 0), now: (2026, 3, 14, 22))

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 15))
        #expect(reminder.booked.first?.at == instant(2026, 3, 15, 9, in: paris))
    }

    @Test("changing the time books the nudges at the new one")
    func changingTheTime() async {
        let device = ADeviceToNudge()
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        let reminder = DailyReminder(
            settings: settings,
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )

        await reminder.remind(at: TimeOfDay(hour: 21, minute: 0))
        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)
        #expect(reminder.booked.first?.at == instant(2026, 3, 14, 21, in: paris))

        await reminder.remind(at: TimeOfDay(hour: 7, minute: 15))
        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)
        #expect(reminder.booked.first?.at == instant(2026, 3, 15, 7, 15, in: paris))
        #expect(reminder.time == TimeOfDay(hour: 7, minute: 15))
    }

    @Test("turning the reminder off takes every nudge away")
    func turningItOff() async {
        let device = ADeviceToNudge()
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )

        await reminder.remind(at: TimeOfDay(hour: 21, minute: 0))
        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)
        #expect(await device.booked.isEmpty == false)

        await reminder.remind(at: nil)
        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        #expect(reminder.time == nil)
        #expect(await device.booked == [])
    }

    @Test("the time chosen is the one still in force after a relaunch")
    func theTimeIsRemembered() async {
        let stored = InMemoryLocalKeyValueStore()
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: stored),
            nudges: ADeviceToNudge(),
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )
        await reminder.remind(at: TimeOfDay(hour: 21, minute: 30))

        let afterARelaunch = DailyReminder(
            settings: DeviceSettingsStore(storedOn: stored),
            nudges: ADeviceToNudge(),
            timeZone: paris,
            now: { instant(2026, 3, 15, 10, in: paris) }
        )

        #expect(afterARelaunch.time == TimeOfDay(hour: 21, minute: 30))
    }

    // MARK: - The day already written in

    @Test("a day whose Entry is already in the folder is not nudged about")
    func todaysEntryIsSkipped() async {
        let store = InMemoryJournalStore([
            PathTemplate.default.render(JournalDay(year: 2026, month: 3, day: 14)): "Walked."
        ])
        let reminder = aReminder(at: TimeOfDay(hour: 21, minute: 0), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: store, journal: .default)

        // Silently: the 14th is simply not among them, and the days either
        // side of it are asked about exactly as they would have been.
        #expect(!reminder.booked.map(\.day).contains(JournalDay(year: 2026, month: 3, day: 14)))
        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 15))
    }

    @Test("a day written after the nudge was booked stops being nudged about")
    func writingTheDayUnbooksIt() async {
        let store = InMemoryJournalStore()
        let reminder = aReminder(at: TimeOfDay(hour: 21, minute: 0), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: store, journal: .default)
        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 14))

        try? await store.write(
            Data("Walked.".utf8),
            at: PathTemplate.default.render(JournalDay(year: 2026, month: 3, day: 14))
        )
        await reminder.reconsider(over: store, journal: .default)

        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 15))
    }

    @Test("which file counts is the current Path Template's answer")
    func thePathTemplateDecidesWhichFile() async {
        var journal = JournalSettings.default
        journal.pathTemplate = "[journal]/YYYY-MM-DD"
        let store = InMemoryJournalStore(["journal/2026-03-14.md": "Walked."])
        let reminder = aReminder(at: TimeOfDay(hour: 21, minute: 0), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: store, journal: journal)

        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 15))
    }

    // MARK: - Which day a nudge is about

    @Test("a nudge before the Rollover Hour is about the day still being written")
    func theRolloverHourDecidesTheDay() async {
        var journal = JournalSettings.default
        journal.rolloverHour = RolloverHour(hour: 4)!
        // One in the morning, which under a 4 AM rollover is still the day
        // before — the day the user would be writing if they answered it.
        let reminder = aReminder(at: TimeOfDay(hour: 1, minute: 0), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: InMemoryJournalStore(), journal: journal)

        let first = reminder.booked.first
        #expect(first?.at == instant(2026, 3, 15, 1, in: paris))
        #expect(first?.day == JournalDay(year: 2026, month: 3, day: 14))
    }

    @Test("the day a late-night nudge is about is the day the skip is decided by")
    func theRolloverHourDecidesTheSkip() async {
        var journal = JournalSettings.default
        journal.rolloverHour = RolloverHour(hour: 4)!
        let store = InMemoryJournalStore([
            PathTemplate.default.render(JournalDay(year: 2026, month: 3, day: 14)): "Walked."
        ])
        let reminder = aReminder(at: TimeOfDay(hour: 1, minute: 0), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: store, journal: journal)

        // The nudge due at 1 AM on the 15th is about the 14th, and the 14th is
        // written — so it goes, and the next one asks about the 15th.
        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 15))
        #expect(reminder.booked.first?.at == instant(2026, 3, 16, 1, in: paris))
    }

    @Test("a time the clock skips is asked at the next one there is")
    func aTimeDaylightSavingSkips() async {
        // Paris springs forward on 29 March 2026: 2 AM becomes 3 AM, and 2:30
        // that morning is a time nobody's clock reads.
        let reminder = aReminder(at: TimeOfDay(hour: 2, minute: 30), now: (2026, 3, 28, 10))

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        // Three, which is the first time that morning anybody's clock reads —
        // and not half past two the previous night, which would be a reminder
        // arriving a day early.
        #expect(reminder.booked[0].at == instant(2026, 3, 29, 3, 0, in: paris))
        #expect(reminder.booked[0].day == JournalDay(year: 2026, month: 3, day: 29))
        #expect(reminder.booked[1].at == instant(2026, 3, 30, 2, 30, in: paris))
        // Every day is still asked about, the skipped half hour included.
        #expect(reminder.booked.map(\.day).count == Set(reminder.booked.map(\.day)).count)
    }

    // MARK: - What else is ever pending

    @Test("booking replaces everything Aujour had pending, so nothing else is ever there")
    func nothingElseIsEverPending() async {
        let device = ADeviceToNudge()
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )
        await reminder.remind(at: TimeOfDay(hour: 21, minute: 0))

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        // The whole of what the app ever asks the device for: this one list,
        // handed over as a replacement. There is no other call to make, so
        // what is pending is the daily reminder's nudges and nothing besides.
        #expect(await device.booked == reminder.booked)
        #expect(await device.booked.count == DailyReminder.daysBookedAhead)
    }

    @Test("a reckoning that changes nothing does not re-book")
    func anUnchangedPlanIsLeftAlone() async {
        let device = ADeviceToNudge()
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )
        await reminder.remind(at: TimeOfDay(hour: 21, minute: 0))

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)
        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)

        #expect(await device.bookings == 1)
    }

    // MARK: - Asking to be allowed

    @Test("choosing a time is what asks to be allowed, and nothing else is")
    func choosingATimeAsks() async {
        let device = ADeviceToNudge()
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )

        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)
        #expect(await device.timesAsked == 0)

        await reminder.remind(at: TimeOfDay(hour: 21, minute: 0))
        #expect(await device.timesAsked == 1)
        #expect(reminder.access == .allowed)

        // Turning it off is not a question, and neither is another reckoning.
        await reminder.remind(at: nil)
        await reminder.reconsider(over: InMemoryJournalStore(), journal: .default)
        #expect(await device.timesAsked == 1)
    }

    @Test("a device that will not nudge is said so rather than pretended about")
    func aRefusedDeviceIsReported() async {
        let device = ADeviceToNudge(answering: .refused)
        let reminder = DailyReminder(
            settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()),
            nudges: device,
            timeZone: paris,
            now: { instant(2026, 3, 14, 10, in: paris) }
        )

        await reminder.remind(at: TimeOfDay(hour: 21, minute: 0))

        #expect(reminder.access == .refused)
        // And the time is kept all the same: a permission granted later in
        // Settings is a reminder that starts working, not one to set again.
        #expect(reminder.time == TimeOfDay(hour: 21, minute: 0))
    }

    // MARK: - A folder that will not answer

    @Test("a folder that cannot be read is asked about rather than left silent")
    func aFolderThatWillNotAnswer() async {
        let reminder = aReminder(at: TimeOfDay(hour: 21, minute: 0), now: (2026, 3, 14, 10))

        await reminder.reconsider(over: nil, journal: .default)

        // Nothing is known about today, and the reminder the user asked for is
        // the thing that would be lost by guessing that they had written.
        #expect(reminder.booked.first?.day == JournalDay(year: 2026, month: 3, day: 14))
    }

    /// A reminder over an empty device, set to a time and pinned to an instant
    /// — the three lines every test above opens with.
    private func aReminder(at time: TimeOfDay?, now: (Int, Int, Int, Int)) -> DailyReminder {
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        settings.update { $0.dailyReminder = time }
        return DailyReminder(
            settings: settings,
            nudges: ADeviceToNudge(),
            timeZone: paris,
            now: { instant(now.0, now.1, now.2, now.3, in: paris) }
        )
    }
}

@MainActor
@Suite("A time on the clock")
struct TimeOfDaySpellingTests {
    @Test("a time is spelled out the way the reader's own clock writes it")
    func spelledOut() {
        let evening = TimeOfDay(hour: 21, minute: 30)!

        // Read in pieces rather than spelled out whole, the way a Journal Day
        // said out loud is: the space before a meridiem is Foundation's narrow
        // no-break one, and a test asserting an ordinary space would be
        // asserting a typo.
        let british = evening.spelledOut(locale: Locale(identifier: "en_GB"))
        #expect(british.contains("21:30"))

        let american = evening.spelledOut(locale: Locale(identifier: "en_US"))
        #expect(american.contains("9:30"))
        #expect(american.contains("PM"))

        // And the storage spelling is untouched by any of it.
        #expect(evening.description == "21:30")
    }
}

/// A device that is nudged rather than rung: what it was last asked to hold,
/// how many times it has been handed a list, and what it says when it is asked
/// to be allowed.
///
/// An actor because the seam it stands in for is one the app reaches from
/// anywhere, and the app's own is a notification centre with no isolation of
/// its own.
private actor ADeviceToNudge: Nudges {
    /// Exactly what is pending, which is the whole of what this seam is for.
    private(set) var booked: [Nudge] = []

    /// How many times a list has been handed over, so a test can say that a
    /// reckoning that changed nothing left the device alone.
    private(set) var bookings = 0

    private(set) var timesAsked = 0
    private var permission: NudgeAccess
    private let answering: NudgeAccess

    init(access: NudgeAccess = .undecided, answering: NudgeAccess = .allowed) {
        self.permission = access
        self.answering = answering
    }

    func access() async -> NudgeAccess { permission }

    func ask() async -> NudgeAccess {
        timesAsked += 1
        permission = answering
        return permission
    }

    func book(_ nudges: [Nudge]) async {
        booked = nudges
        bookings += 1
    }
}
