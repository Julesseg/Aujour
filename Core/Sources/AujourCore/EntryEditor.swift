import Foundation
import Observation

/// One day's Entry while it is open in front of the user: which day it is,
/// what the editor shows, and when what has been typed reaches the folder.
///
/// Every decision behind the Today view is here, so that the screen is left
/// with the typing and the pixels:
///
/// - **Which day.** The current Journal Day at this moment, Rollover Hour
///   respected — so 1 AM with a 4 AM rollover opens yesterday, and an app
///   left running overnight moves on when it comes back to the front.
/// - **What to show.** An Entry that exists is shown as the file has it. One
///   that does not is *spawned*: the Content Template rendered for the day,
///   which is what the user starts typing into.
/// - **When to write.** A spawned Entry is not a file. Nothing reaches the
///   folder until the user's first edit, so a day nobody wrote on leaves no
///   empty husk behind (`v1-decisions.md`) and "the file is there" keeps
///   meaning "that day is journaled" (ADR 0001). From the first edit on, the
///   words are written continuously: shortly after the typing stops, at the
///   ceiling if it does not stop, and at once when the app goes away.
///
/// It reaches the world through three seams and nothing else — a Journal
/// Store, a clock, and a way of waiting — so all of the above is tested
/// against an in-memory folder with no second passing.
@MainActor
@Observable
public final class EntryEditor {
    /// What the screen should be showing.
    public enum State {
        /// Finding out what the folder holds for this day.
        case opening

        /// The Entry is on screen, and can be typed into.
        case editing

        /// The Entry could not be opened. Never an empty page: an empty
        /// editor over a folder Aujour could not read is indistinguishable
        /// from a day the user never wrote, and only one of those is true
        /// (ADR 0001).
        case unavailable(any Error)

        public var isEditing: Bool {
            if case .editing = self { return true }
            return false
        }
    }

    public private(set) var state: State = .opening

    /// The Journal Day on screen. Known before the folder answers, so the
    /// screen can say which day it is opening.
    public private(set) var day: JournalDay

    /// What the editor shows — the file's content, or the text the Content
    /// Template spawned for a day that has none yet.
    ///
    /// Writing to it is how the editor says the user typed, and is what
    /// starts the saving: this is the property the text view is bound to, so
    /// there is no keystroke that does not come through here. Written by hand
    /// rather than left to `@Observable` because the setter has to do that
    /// work, and because putting text on screen (opening a day) is not the
    /// same event as someone typing it.
    public var content: String {
        get {
            access(keyPath: \.content)
            return typedContent
        }
        set {
            // Typing into a day that is still opening, or into a failure
            // notice, is not an edit of anything.
            guard state.isEditing, newValue != typedContent else { return }
            show(newValue)
            scheduleSave()
        }
    }

    @ObservationIgnored private var typedContent = ""

    /// The last save that did not land, if it has not since been made good.
    ///
    /// Surfaced rather than swallowed: a journaling app that quietly stops
    /// saving is the one failure that costs words (ADR 0001). The screen says
    /// so; the words stay in the editor, and the next edit tries again.
    public private(set) var saveProblem: (any Error)?

    @ObservationIgnored private let store: any JournalStore
    @ObservationIgnored private let settings: JournalSettings
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let timing: AutosaveTiming
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let wait: @MainActor (Duration) async throws -> Void

    /// Where this day's Entry belongs, once the Path Template has been read.
    @ObservationIgnored private var entryPath: String?

    /// The text a save would be a no-op against: what the folder holds, or —
    /// before there is a file — the text the template spawned, which is
    /// exactly the text that must never be written on its own.
    @ObservationIgnored private var savedContent: String?

    /// Whether anything has been typed that the running autosave has not yet
    /// taken account of. Reset each time the loop looks, so that "the typing
    /// has stopped" is a fact about the last wait rather than a guess.
    @ObservationIgnored private var editedWhileWaiting = false

    /// The save that is waiting to happen, if one is. Internal so that a test
    /// can wait for what the app never waits for.
    @ObservationIgnored private(set) var autosave: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the folder this Journal lives in.
    ///   - settings: the Path Template, Content Template and Rollover Hour
    ///     that shape which file this is and what it starts as.
    ///   - timeZone: the zone the Journal Day and the template's dates are
    ///     read in.
    ///   - locale: picks month and weekday names in the Content Template.
    ///   - timing: how long typing may go unsaved.
    ///   - now: the wall clock. Read again on every open, so an app left
    ///     running overnight is not still holding yesterday.
    ///   - wait: how the editor waits between a keystroke and a save. The app
    ///     waits on the clock; a test waits on the test.
    public init(
        store: any JournalStore,
        settings: JournalSettings = .default,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        autosave timing: AutosaveTiming = .default,
        now: @escaping @MainActor () -> Date = { Date() },
        wait: @escaping @MainActor (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.store = store
        self.settings = settings
        self.timeZone = timeZone
        self.locale = locale
        self.timing = timing
        self.now = now
        self.wait = wait
        self.day = JournalDay.current(
            at: now(),
            in: timeZone,
            rolloverHour: settings.rolloverHour
        )
    }

    // MARK: - Opening

    /// Opens the current Journal Day's Entry: its file if it has one, the
    /// rendered Content Template if it does not.
    public func open() async {
        await open(JournalDay.current(at: now(), in: timeZone, rolloverHour: settings.rolloverHour))
    }

    /// Saves, and moves to the new day if the Journal Day has turned since
    /// the Entry on screen was opened.
    ///
    /// For the app that was left open overnight and comes back to the front
    /// in the morning: today's Entry is a different file by then, and going on
    /// writing into yesterday's would put today's words in the wrong day.
    public func reopenIfTheDayTurned() async {
        guard state.isEditing else { return }

        let today = JournalDay.current(at: now(), in: timeZone, rolloverHour: settings.rolloverHour)
        guard today != day else { return }
        await open(today)
    }

    private func open(_ day: JournalDay) async {
        // Whatever is on screen belongs to the day being left, and this is the
        // last moment it can be written to that day's file. Nothing to save on
        // a first open, and nothing to lose on any other.
        await save()

        state = .opening
        saveProblem = nil
        do {
            // The Path Template is a string until it is read, and one that
            // cannot name a day names no Entry at all. Falling back to the
            // default would write today somewhere this user's other devices
            // do not look, so this is a sentence for them rather than a guess
            // (ADR 0002).
            let template = try PathTemplate(settings.pathTemplate)
            let path = template.render(day)

            let journaled = try await store.fileExists(at: path)
            let text =
                journaled
                ? try await store.readText(at: path)
                : spawn(day, from: template)

            self.day = day
            entryPath = path
            show(text)
            // Either way this is the text that needs no saving: what the file
            // says, or what the template spawned and the user has not touched.
            savedContent = text
            state = .editing
        } catch {
            state = .unavailable(error)
        }
    }

    /// The text a day with no file starts as: the Content Template, rendered.
    private func spawn(_ day: JournalDay, from template: PathTemplate) -> String {
        ContentTemplate(settings.contentTemplate).render(
            at: SpawnContext(
                day: day,
                instant: now(),
                title: template.entryName(for: day),
                timeZone: timeZone,
                locale: locale,
                dateFormat: template.entryNameFormat
            )
        )
    }

    // MARK: - Typing

    /// Puts text on screen without treating it as something the user typed —
    /// which is the difference between opening a day and writing in it.
    private func show(_ text: String) {
        withMutation(keyPath: \.content) { typedContent = text }
    }

    /// Whether the folder is behind what is on screen.
    private var needsSaving: Bool {
        savedContent != nil && typedContent != savedContent
    }

    private func scheduleSave() {
        guard needsSaving else { return }
        editedWhileWaiting = true
        guard autosave == nil else { return }
        autosave = Task { await autosaveLoop() }
    }

    /// Waits out the typing, then writes — over and over until the typing and
    /// the writing have caught up with each other.
    private func autosaveLoop() async {
        defer { autosave = nil }

        while editedWhileWaiting {
            var waited: Duration = .zero
            while editedWhileWaiting {
                editedWhileWaiting = false
                let pause = timing.pause(afterWaiting: waited)
                // The ceiling is up: the user is still typing, and the words
                // so far have waited long enough.
                guard pause > .zero else { break }
                do {
                    try await wait(pause)
                } catch {
                    // Cancelled, which only `save()` does — and it writes
                    // itself, right now, rather than after another wait.
                    return
                }
                waited += pause
            }
            await write()
        }
    }

    /// Writes what is on screen right now, without waiting — what the app does
    /// on its way into the background, where there is no next second to save
    /// in.
    public func save() async {
        let pending = autosave
        pending?.cancel()
        // Waited out rather than abandoned: a loop cancelled mid-write is
        // still writing, and two saves racing would decide the day's content
        // by whichever finished last.
        await pending?.value
        autosave = nil
        editedWhileWaiting = false
        await write()
    }

    private func write() async {
        guard needsSaving, let entryPath else { return }

        // Held onto, because the user goes on typing while the folder is
        // being written to: what is saved is what was written, not whatever
        // the screen says when the write comes back.
        let saving = typedContent
        do {
            try await store.writeText(saving, at: entryPath)
            savedContent = saving
            saveProblem = nil
        } catch {
            saveProblem = error
        }
    }
}

// MARK: - How long words may go unsaved

/// How long what has been typed may sit in the editor before it is in the
/// folder.
///
/// Two numbers rather than one, because a debounce alone has a hole in it: a
/// quiet period only elapses when the typing stops, and someone writing
/// steadily for ten minutes has stopped for none of them. So the quiet period
/// decides when a *pause* is saved, and the ceiling decides how long a
/// stretch of unbroken typing may go unwritten.
public struct AutosaveTiming: Hashable, Sendable {
    /// The quiet period after the last keystroke.
    public var afterTyping: Duration

    /// The longest the oldest unsaved words may wait while the typing goes on.
    public var atMost: Duration

    public init(afterTyping: Duration = .seconds(1), atMost: Duration = .seconds(10)) {
        self.afterTyping = afterTyping
        self.atMost = atMost
    }

    public static let `default` = AutosaveTiming()

    /// How long to wait next, given how long these words have waited already:
    /// another quiet period, or whatever is left of the ceiling.
    func pause(afterWaiting waited: Duration) -> Duration {
        max(.zero, min(afterTyping, atMost - waited))
    }
}
