import Foundation
import Observation

/// One nudge: a day, and the moment somebody is asked about it.
///
/// A nudge is per Journal Day and not per notification, because that is the
/// whole promise — one gentle reminder a day, and a day already written in is
/// a day with no nudge rather than a nudge with different words.
public struct Nudge: Hashable, Sendable, Identifiable {
    /// The Journal Day it asks about: the day that will be current when it
    /// arrives, Rollover Hour and all. At 1 AM under a 4 AM rollover that is
    /// yesterday's date, which is the day somebody answering it would write.
    public let day: JournalDay

    /// When it is due, as a wall-clock instant on this device.
    public let at: Date

    /// One nudge per day, and the day is what it is about.
    public var id: JournalDay { day }

    public init(day: JournalDay, at: Date) {
        self.day = day
        self.at = at
    }

    /// The line above it — the day it is asking about, so that a nudge
    /// arriving after midnight under a late Rollover Hour still names the day
    /// somebody would be writing rather than the one the clock has moved on
    /// to.
    public var heading: String { day.spelledOut() }

    /// What it says, and the whole of what it says.
    ///
    /// A question, and no count, no streak and no reproach. Everything else a
    /// journal could say about a day nobody has written on is a way of
    /// telling somebody off for it, and the reminder is an invitation — the
    /// user asked to be offered the day, not to be marked against it.
    public var words: String { "A few words about your day?" }
}

/// Whether Aujour may put a nudge in front of the user.
///
/// Three answers rather than a `Bool`, for the reason ``PhotoLibraryAccess``
/// has three: an undecided device is one that has never been asked, a refused
/// one is a reminder that will not arrive however carefully it is booked — and
/// which the settings screen therefore has to say out loud — and only an
/// allowed one nudges.
public enum NudgeAccess: Hashable, Sendable {
    /// Nobody has been asked yet.
    case undecided

    /// Aujour may nudge.
    case allowed

    /// The user said no, here or in Settings afterwards.
    case refused
}

/// The device's own way of nudging somebody, as the daily reminder sees it —
/// the fourth seam between the domain and the device, after the Journal Store,
/// Day Data and the photo library.
///
/// One operation and no more, because a reminder is a standing arrangement
/// rather than a stream of events: ``book(_:)`` says what should be pending
/// *and nothing else*, so there is no way to add a notification here without
/// saying which ones go — which is what makes "no other notifications of any
/// kind" a property of the seam rather than a rule somebody remembers.
///
/// Asking to be allowed is separate, and happens because the user chose a time
/// and at no other moment. Where the permission stands is a question rather
/// than a property, unlike the photo library's, because the device answers it
/// asynchronously and Aujour has nowhere to keep an answer that Settings can
/// change while the app is closed.
public protocol Nudges: Sendable {
    /// Where the permission stands, without asking for it.
    func access() async -> NudgeAccess

    /// Puts the system's question in front of the user, and answers what they
    /// said. A permission already decided is answered from what is known — the
    /// way back from a refusal is Settings, not another alert.
    func ask() async -> NudgeAccess

    /// Leaves exactly these pending, in place of whatever was pending before.
    func book(_ nudges: [Nudge]) async
}

/// One gentle nudge a day, at a time the user chose — and none at all on a day
/// whose Entry is already in the folder.
///
/// The reminder is a Device Setting (ADR 0003): a phone that buzzes at nine and
/// an iPad that never does are not in disagreement about anything, and nothing
/// here shapes what is written into the Journal. It is off until a time is
/// chosen, which is what makes the app something the user invited rather than
/// something that started nudging them.
///
/// Three decisions live here, so that the app layer is left with a notification
/// centre to hand a list to:
///
/// - **Whether to nudge at all.** No time chosen is no nudges, and turning the
///   reminder off books an empty list rather than simply stopping — what an
///   earlier launch left pending has to be taken away, or a reminder switched
///   off would go on arriving for a week.
/// - **Which day each nudge is about.** The Journal Day current at the moment
///   it arrives, Rollover Hour respected, which is the day answering it would
///   write.
/// - **Whether that day still needs asking about.** A day whose Entry file
///   exists is journaled and nothing else (ADR 0001), and the nudge for it is
///   dropped — silently, because a notification that arrived to say "you have
///   already done this" is the nagging the reminder exists not to be.
///
/// It reaches the world through a Journal Store, a key-value store and the
/// nudging seam, so all of the above is tested against an in-memory folder on
/// any platform.
@MainActor
@Observable
public final class DailyReminder {
    /// How many days of nudges are kept pending at once.
    ///
    /// One would do while the app is opened every day — but the days worth
    /// asking somebody about are exactly the days they did not open it, and a
    /// single pending nudge would go quiet after the first one nobody
    /// answered. A week is how long Aujour can be left alone and still ask.
    public static let daysBookedAhead = 7

    /// The time offered to somebody who has just turned the reminder on.
    ///
    /// The evening, because that is when a day is over and there is something
    /// to say about it. It is a starting point and not a default: the reminder
    /// is off until a time is chosen, and this is only what the first choice
    /// lands on.
    public static let suggestedTime = TimeOfDay(hour: 21, minute: 0)!

    /// The time chosen, or `nil` for a reminder that is off.
    ///
    /// Follows the setting rather than copying it, so a screen showing this
    /// redraws when the reminder is turned off from anywhere in the app.
    public private(set) var time: TimeOfDay?

    /// What is pending, in the order it is due — the same list the device was
    /// last handed.
    public private(set) var booked: [Nudge] = []

    /// Where the permission stands, as of the last reckoning.
    ///
    /// Read again on every ``reconsider(over:journal:)`` rather than kept from
    /// when it was asked: notifications are turned off for an app in Settings,
    /// where Aujour is not running to hear about it.
    public private(set) var access: NudgeAccess = .undecided

    @ObservationIgnored private let settings: DeviceSettingsStore
    @ObservationIgnored private let nudging: any Nudges
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: @MainActor () -> Date

    /// Whether the device has been handed a list at all this launch. Until it
    /// has, an empty plan is still worth booking — it is what clears whatever
    /// a previous launch left pending.
    @ObservationIgnored private var hasBooked = false

    /// Held for as long as this object is, and reporting every change until
    /// then.
    @ObservationIgnored private var watchingTheSettings: SettingsObservation?

    /// - Parameters:
    ///   - settings: the device-local settings the chosen time lives in. The
    ///     same store everything else device-local reads, and never one of its
    ///     own: a second store over the same `UserDefaults` would write a time
    ///     this one never hears about.
    ///   - nudges: the device's notifications. The real one in the app, a fake
    ///     in tests and in a UI test — a permission alert from another process
    ///     is not something a test can answer.
    ///   - timeZone: the zone the chosen time is read as, and the one the
    ///     Journal Day is resolved in.
    ///   - now: the wall clock. Read on every reckoning rather than once, so
    ///     an app left running overnight books tomorrow's nudges from tomorrow.
    public init(
        settings: DeviceSettingsStore,
        nudges: any Nudges,
        timeZone: TimeZone = .current,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.settings = settings
        self.nudging = nudges
        self.timeZone = timeZone
        self.now = now
        self.time = settings.settings.dailyReminder
        watchingTheSettings = settings.observe { [weak self] in
            self?.time = $0.dailyReminder
        }
    }

    /// Sets the time to be nudged at, or turns the reminder off with `nil`.
    ///
    /// Asking to be allowed happens here and nowhere else, because this is the
    /// one moment the user has said they want to be nudged — a permission
    /// alert in front of a day that is merely being opened is a question
    /// nobody asked for. Nothing is booked yet: what should be pending depends
    /// on which days are already written, which is
    /// ``reconsider(over:journal:)``'s to say.
    public func remind(at time: TimeOfDay?) async {
        settings.update { $0.dailyReminder = time }
        guard time != nil else { return }
        // Asked again for a device that said no, deliberately: the system
        // answers from what it already knows without putting up a second
        // alert, and it is how a permission granted in Settings since is
        // noticed at the moment somebody is setting a time.
        if access != .allowed {
            access = await nudging.ask()
        }
    }

    /// Works out what should be pending and leaves exactly that with the
    /// device.
    ///
    /// Called wherever what it depends on can have moved: on launch, on the
    /// app coming back to the front, on the way into the background — where
    /// today's words have just been saved, so today's nudge is the one to drop
    /// — and after any settings change, since the Rollover Hour and the Path
    /// Template both decide which day is which.
    ///
    /// - Parameters:
    ///   - store: the folder the Journal lives in, or `nil` when there is none
    ///     open. A folder that cannot be read leaves every day looking
    ///     unwritten and so still worth asking about: a reminder the user set
    ///     is the thing that would be lost by guessing the other way, and the
    ///     cost of guessing wrong is one question about a day they have
    ///     already written.
    ///   - journal: the settings that say where an Entry belongs and when the
    ///     day turns.
    public func reconsider(over store: (any JournalStore)?, journal: JournalSettings) async {
        access = await nudging.access()
        let due = await whatIsDue(over: store, journal: journal)
        // A reckoning that changed nothing leaves the device alone. Coming
        // back to the front and a folder finishing a sync both land here, and
        // neither is a reason to tear down a week of pending nudges and
        // rebuild it.
        guard !hasBooked || due != booked else { return }
        booked = due
        hasBooked = true
        await nudging.book(due)
    }

    private func whatIsDue(
        over store: (any JournalStore)?,
        journal: JournalSettings
    ) async -> [Nudge] {
        guard let time else { return [] }
        let planned = Self.nudges(
            at: time,
            after: now(),
            in: timeZone,
            rolloverHour: journal.rolloverHour,
            count: Self.daysBookedAhead
        )
        // A Path Template that cannot name a day cannot say which file an
        // Entry is either (ADR 0002), so no day can be shown to be written and
        // every one of them is still asked about.
        guard let store, let entries = try? PathTemplate(journal.pathTemplate) else {
            return planned
        }
        var due: [Nudge] = []
        for nudge in planned {
            let written = (try? await store.fileExists(at: entries.render(nudge.day))) ?? false
            if !written { due.append(nudge) }
        }
        return due
    }

    /// The next `count` times a reminder set for `time` comes round, each
    /// paired with the Journal Day it would be asking about.
    ///
    /// One per Journal Day: a clock time comes round once a calendar date, and
    /// the Rollover Hour maps consecutive dates onto consecutive days, so the
    /// days are already distinct — keeping only the first nudge for each is
    /// what makes that a promise rather than an observation.
    ///
    /// Found by asking the calendar for the next matching time rather than by
    /// adding days to an instant, because a day is not always 24 hours long:
    /// nine in the evening is nine in the evening on both sides of a daylight
    /// saving change, and a half hour the clock skips over is asked at the
    /// next time there is.
    static func nudges(
        at time: TimeOfDay,
        after now: Date,
        in timeZone: TimeZone,
        rolloverHour: RolloverHour,
        count: Int
    ) -> [Nudge] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var due: [Nudge] = []
        var days: Set<JournalDay> = []
        var cursor = now
        while due.count < count {
            guard
                let at = calendar.nextDate(
                    after: cursor,
                    matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                    matchingPolicy: .nextTime,
                    direction: .forward
                )
            else { break }
            cursor = at
            let day = JournalDay.current(at: at, in: timeZone, rolloverHour: rolloverHour)
            guard days.insert(day).inserted else { continue }
            due.append(Nudge(day: day, at: at))
        }
        return due
    }
}
