import Foundation
import Observation

/// The three pages a fresh install is shown, and the one thing they are for:
/// getting out of the way.
///
/// Aujour needs nothing configured to be written in — the folder is found on
/// launch and today's Entry is spawned over it before anybody has tapped
/// anything (ADR 0004) — so the welcome is not a setup wizard and has no step
/// that must be completed. It says what the app is, where the words will be,
/// and offers the one thing the app would ever do while nobody is looking; and
/// then it is over, whichever page it was left on.
///
/// It happens once per device rather than once per journal, and is remembered
/// as a Device Setting for the reason the reminder is one (ADR 0003): it is
/// about this install having been introduced to the app, and an iPad added a
/// year later has not been. Nothing about it shapes what goes into the Journal,
/// and nothing about it ever reaches the synced seam.
///
/// Two decisions live here, so that the app layer is left with three pages to
/// draw:
///
/// - **Whether there is a welcome at all**, and which page of it is on screen.
///   The ends hold: there is nothing before the first page and nothing after
///   the last, so running off either end is not a way out of it.
/// - **What the offer on the last page does.** A time taken up is the reminder
///   set and the device asked to be allowed to keep it; no time is the reminder
///   left exactly where it already was, and a device that is never asked
///   anything. Both end the welcome, because a welcome somebody has answered
///   is one they have been through.
@MainActor
@Observable
public final class Welcome {
    /// What a fresh install is told, in the order it is told it.
    public enum Page: Int, CaseIterable, Hashable, Sendable, Identifiable {
        /// What Aujour is: a day at a time, written in markdown.
        case whatThisIs

        /// Where the words go — the folder, and what being in it promises.
        case whereYourWordsGo

        /// The daily reminder, offered and skippable.
        case theDailyReminder

        public var id: Int { rawValue }
    }

    /// The page on screen.
    public private(set) var page: Page = .whatThisIs

    /// Whether this device is owed a welcome at all.
    ///
    /// Follows the setting rather than copying it, so that a welcome ended
    /// anywhere is a welcome gone from the screen.
    public private(set) var isDue: Bool

    /// Whether the page on screen is the one with the offer on it — where
    /// "Continue" stops being what the button says.
    public var isOnTheLastPage: Bool { page == Page.allCases.last }

    @ObservationIgnored private let settings: DeviceSettingsStore
    @ObservationIgnored private let reminder: DailyReminder

    /// Held for as long as this object is, and reporting every change until
    /// then.
    @ObservationIgnored private var watchingTheSettings: SettingsObservation?

    /// - Parameters:
    ///   - settings: the device-local settings that remember this device has
    ///     been through the welcome. The same store everything else
    ///     device-local reads, and never one of its own: a second store over
    ///     the same `UserDefaults` would write a welcome this one never hears
    ///     about.
    ///   - reminder: the daily reminder the last page offers. Handed in rather
    ///     than made, for the same reason and one more — it is the app's one
    ///     reminder, and a time chosen here is the time the settings screen
    ///     shows afterwards.
    public init(settings: DeviceSettingsStore, reminder: DailyReminder) {
        self.settings = settings
        self.reminder = reminder
        self.isDue = !settings.settings.hasBeenWelcomed
        watchingTheSettings = settings.observe { [weak self] in
            self?.isDue = !$0.hasBeenWelcomed
        }
    }

    /// On to the next page, or nowhere if this is the last one.
    ///
    /// Deliberately not a way out: the welcome ends when the user answers the
    /// offer, and a fourth tap on "Continue" is not an answer.
    public func next() {
        guard let onwards = Page(rawValue: page.rawValue + 1) else { return }
        page = onwards
    }

    /// Back a page, or nowhere if this is the first one.
    public func back() {
        guard let backwards = Page(rawValue: page.rawValue - 1) else { return }
        page = backwards
    }

    /// Ends the welcome, taking the reminder's offer up at `time` or declining
    /// it with `nil`.
    ///
    /// One way out and not two, because the two answers on the last page differ
    /// only in what they do with the offer — and because the way out of an
    /// earlier page is the same thing said with no time. Declining is therefore
    /// not a path with anything of its own on it: it sets the reminder to no
    /// time, which is where it already was, and the device is never asked for a
    /// permission it has no reason to want.
    ///
    /// Taking it up is the one moment there is a reason to want one, and the
    /// one case where this does not end anything: a device that says no is a
    /// reminder that cannot arrive however carefully it is booked, and a
    /// welcome that closed over it would have told somebody they had set
    /// something up that never will. So it stays on the last page for that to
    /// be said, with the same two buttons under it — and declining from there
    /// is what takes the time back off.
    ///
    /// Nothing is booked here either way. What should be pending depends on
    /// which days are already written, which is
    /// ``DailyReminder/reconsider(over:journal:)``'s to say — and the folder is
    /// what would have to be read to answer it.
    public func end(remindingAt time: TimeOfDay?) async {
        await reminder.remind(at: time)
        guard time == nil || reminder.access != .refused else { return }
        settings.update { $0.hasBeenWelcomed = true }
    }
}
