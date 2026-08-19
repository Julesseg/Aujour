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
/// - **When to take the file's version instead.** The folder is shared with
///   Obsidian and with the user's other devices, so the file can move on
///   without Aujour. While nothing is waiting to be saved, the Entry follows
///   it; while something is, the words on screen are the newest anybody has
///   and nothing may replace them.
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
    /// The day this editor stays on, if it was made for a particular one.
    @ObservationIgnored private let pinnedDay: JournalDay?
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

    /// The write going on right now, if one is — what the next write queues
    /// behind.
    @ObservationIgnored private var writing: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the folder this Journal lives in.
    ///   - settings: the Path Template, Content Template and Rollover Hour
    ///     that shape which file this is and what it starts as.
    ///   - timeZone: the zone the Journal Day and the template's dates are
    ///     read in.
    ///   - locale: picks month and weekday names in the Content Template.
    ///   - day: the one Journal Day this editor is over, or `nil` for
    ///     whichever day it is now. Today's Entry follows the clock — the app
    ///     left open overnight moves on — while a day opened from the
    ///     calendar is the day it was opened on and stays it. Which days may
    ///     be opened at all is ``JournalCalendar``'s to decide.
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
        day pinnedDay: JournalDay? = nil,
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
        self.pinnedDay = pinnedDay
        self.timing = timing
        self.now = now
        self.wait = wait
        // Before anything has been read: the screen can say which day it is
        // opening while the folder is still answering.
        self.day =
            pinnedDay
            ?? JournalDay.current(at: now(), in: timeZone, rolloverHour: settings.rolloverHour)
    }

    // MARK: - Opening

    /// Opens this editor's Journal Day: its file if it has one, the rendered
    /// Content Template if it does not.
    public func open() async {
        await open(currentDay)
    }

    /// The Journal Day this editor is for: the day it was pinned to, or — for
    /// today's Entry, which is pinned to nothing — the day it is right now,
    /// asked again every time because the answer changes under a running app.
    private var currentDay: JournalDay {
        pinnedDay
            ?? JournalDay.current(at: now(), in: timeZone, rolloverHour: settings.rolloverHour)
    }

    /// Saves, and moves to the new day if the Journal Day has turned since
    /// the Entry on screen was opened.
    ///
    /// For the app that was left open overnight and comes back to the front
    /// in the morning: today's Entry is a different file by then, and going on
    /// writing into yesterday's would put today's words in the wrong day.
    ///
    /// A day opened from the calendar has no such morning: it is pinned, so
    /// the day it is over never turns and this does nothing to it.
    public func reopenIfTheDayTurned() async {
        guard state.isEditing else { return }

        let today = currentDay
        guard today != day else { return }
        await open(today)
    }

    private func open(_ day: JournalDay) async {
        // Whatever is on screen belongs to the day being left, and this is the
        // last moment it can be written to that day's file. Nothing to save on
        // a first open, and nothing to lose on any other.
        await save()
        // Unless it would not go: words that could not be written are not
        // words to leave behind. The day stays on screen, with what went
        // wrong with it, until they land (v1-decisions: no words are ever
        // silently discarded).
        guard !needsSaving else { return }

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
                : await spawn(day, from: template)

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
    private func spawn(_ day: JournalDay, from template: PathTemplate) async -> String {
        ContentTemplate(await contentTemplate()).render(
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

    /// The Content Template's markdown: the file the settings name, read out
    /// of the Journal Root — or nothing at all, which is a blank page.
    ///
    /// Nothing is what an unreadable template comes to as well, and
    /// deliberately: the file is the user's own, sitting in their vault, and
    /// they may have renamed it, moved it, or not brought it down from iCloud
    /// yet. A day that refused to open because of it would be a day they
    /// cannot write in — worse than the blank page they had before they ever
    /// set one (ADR 0005).
    private func contentTemplate() async -> String {
        guard !settings.contentTemplateFile.isEmpty else { return "" }
        return (try? await store.readText(at: settings.contentTemplateFile)) ?? ""
    }

    // MARK: - What this Entry points at

    /// The bytes of the file an Embed in this Entry names, or `nil` for a
    /// target that names nothing in the Journal Root.
    ///
    /// The Entry is asked because the Entry is what knows: an Embed's target
    /// is written relative to the file holding it — `![](market.jpg)` in
    /// `2026/03/2026-03-14.md` means the picture beside that day — so nothing
    /// but this object has both halves of the question. Which is also why the
    /// editor above does not get handed the folder to go rummaging in.
    ///
    /// Bytes rather than a picture, because what a JPEG looks like needs a
    /// screen and this module has none. Decoding is the app's; deciding which
    /// file is meant is the domain's, and is `EmbedTarget`'s to spell out.
    ///
    /// `nil` for every way of failing, deliberately: no file, an unreadable
    /// one, a path the store refuses, a target climbing out of the folder the
    /// user pointed Aujour at. All four mean the same thing on screen — the
    /// Embed is drawn as the markdown it is, visible and harmless — and a
    /// notice about a photograph would be a notice in front of somebody who is
    /// writing.
    public func attachment(named target: String) async -> Data? {
        for path in EmbedTarget.candidates(for: target, inEntryAt: entryPath) {
            if let contents = try? await store.read(at: path) { return contents }
        }
        // A bare name and nowhere obvious to look: Obsidian's `![[market.jpg]]`
        // names a file and leaves finding it to the app, so the folder is
        // searched — last, and only for a target that could be found this way,
        // because a listing costs the whole Journal Root.
        guard let name = EmbedTarget.bareName(of: target),
            let files = try? await store.listFiles(),
            let named = EmbedTarget.match(name, among: files)
        else { return nil }
        return try? await store.read(at: named)
    }

    // MARK: - Adding a photograph to it

    /// Writes a file into the Journal Root for this Entry to point at, and
    /// answers the embed that points at it.
    ///
    /// The Entry is asked for the same reason it is asked to find one: an
    /// Attachment's whole address is relative to the file holding the embed,
    /// and nothing but this object has both the Journal Day the Attachment
    /// Path Template is rendered for and the Entry path the reference is
    /// written from. What is left for the app is the two halves that need a
    /// device — the picker, and turning what comes back into bytes a folder
    /// can keep (``AttachmentFormat``).
    ///
    /// The file is written *before* the Entry points at it, deliberately. An
    /// embed naming a file that is not there is drawn as its own markdown
    /// (``EmbedTarget``), so the other order would put a line of punctuation
    /// in front of the user and turn it into a photograph a moment later — and
    /// would leave that line behind for good on the write that failed.
    ///
    /// Nothing is written over. The path is one the folder does not hold, and
    /// a folder that has gained a file there since it was listed refuses the
    /// write (``JournalStore/create(_:at:)``) rather than replacing it, which
    /// is answered here by picking the next name and trying again.
    ///
    /// - Returns: where the file went, and the markdown to put at the cursor —
    ///   which the editor writes in through the same door a keystroke goes
    ///   through, so that it is one undo step and the Entry saves it as
    ///   typing.
    /// - Throws: `NoEntryIsOpen` for an Entry that is not on screen,
    ///   `PathTemplateError` for an Attachment Path Template that cannot be
    ///   read, and whatever the folder throws for a write it will not take.
    public func attach(
        _ contents: Data,
        keeping format: AttachmentFormat
    ) async throws -> Attachment {
        guard state.isEditing, let entryPath else { throw NoEntryIsOpen() }
        // A stored template that cannot be read names no folder to write into,
        // and falling back to the default would scatter this user's photographs
        // across two folders. A sentence for them instead, as with the Path
        // Template (ADR 0002).
        let folders = try AttachmentPathTemplate(settings.attachmentPathTemplate)

        var taken = Set(try await store.listFiles())
        // The listing is a moment old by the time the write happens, and the
        // folder is shared — so a refusal is a name to cross off and try past,
        // and not the write failing. Bounded, because a folder that says
        // something is already at every name in turn is a folder answering
        // something other than the truth, and the refusal is better handed on
        // than retried for ever.
        var refusals = 0
        while true {
            let attachment = try Attachment(
                format,
                writtenOn: day,
                under: folders,
                embeddedIn: entryPath,
                as: settings.embedSyntax,
                beside: taken
            )
            do {
                try await store.create(contents, at: attachment.path)
                return attachment
            } catch JournalStoreError.fileAlreadyExists(let occupied) {
                refusals += 1
                guard refusals < 8 else {
                    throw JournalStoreError.fileAlreadyExists(occupied)
                }
                taken.insert(attachment.path)
            }
        }
    }

    // MARK: - The file changing underneath

    /// Shows what this day's file says now, unless there are words on screen
    /// that are not in it yet.
    ///
    /// The folder is shared. Obsidian writes the same file, and iCloud brings
    /// down what another device wrote, so the Entry on screen can fall behind
    /// its own file while nobody is typing — a day written on the iPad at
    /// lunchtime, opened on the iPhone that still has the morning's version.
    /// This is what catches it up, so that the two apps agree without the user
    /// thinking about it (`v1-decisions.md`).
    ///
    /// Only while nothing is unsaved, and that is the whole policy. Words in
    /// the editor that have not reached the file are the newest anybody has,
    /// and taking the file's version over them would lose the sentence being
    /// typed. Two versions that have *both* been written is a real divergence,
    /// and setting the loser aside as a Parked File is its own job; this is
    /// the far commoner case, where nothing has diverged and the only question
    /// is whether the screen is current.
    ///
    /// A file that is *not* there is left alone, deliberately. An Entry on
    /// screen is on screen because somebody wrote it, and emptying it back to
    /// the template because its file went missing for a moment — a sync
    /// replacing it, an app that saves by deleting first — is the app losing
    /// the day, whatever the folder is doing. The words stay, and the next
    /// keystroke writes them back where they were.
    ///
    /// Silent when the folder will not answer. Nobody asked for this read, the
    /// Entry on screen is still the last thing the file said, and a notice
    /// about a refresh that did not happen would be a notice in front of
    /// somebody who is writing.
    public func reloadIfClean() async {
        guard state.isEditing else {
            // An Entry that could not be opened has nothing on screen to lose
            // and everything to gain from another look: a file arriving from
            // iCloud is exactly the change that makes the last failure stale.
            if case .unavailable = state { await open() }
            return
        }
        // Everything below is about *this* day's file, and the answers come
        // back after a wait — during which the day can turn under the editor.
        guard !needsSaving, let path = entryPath else { return }
        let reloading = day

        do {
            guard try await store.fileExists(at: path) else { return }
            let text = try await store.readText(at: path)

            // The wait is where a keystroke lands, and where the morning
            // arrives for an app left open overnight. Either way what came
            // back is about a day that is no longer the one to put on screen.
            guard state.isEditing, day == reloading, entryPath == path else { return }
            guard !needsSaving, text != typedContent else { return }

            show(text)
            savedContent = text
        } catch {
            // Left as it was, deliberately — see above.
        }
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

    /// Writes, behind whatever write is already going on.
    ///
    /// Queued rather than concurrent because saving is asked for from more
    /// than one direction — the autosave loop, and the app on its way out,
    /// which SwiftUI announces twice. Two writes of one Entry in flight
    /// together would leave the day saying whichever the folder happened to
    /// finish last.
    private func write() async {
        let precedingWrite = writing
        let thisWrite = Task {
            await precedingWrite?.value
            await writeWhatIsOnScreen()
        }
        writing = thisWrite
        await thisWrite.value
    }

    private func writeWhatIsOnScreen() async {
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

/// Asked to add an Attachment to an Entry that is not open.
///
/// Not reachable from the screen — the accessory row a photograph is added
/// from is up only while an Entry is being written in — and said in the two
/// sentences every other storage failure is said in rather than as a silence,
/// because a photograph that appeared to insert nothing is the one outcome a
/// user would repeat.
public struct NoEntryIsOpen: LocalizedError, Hashable, Sendable {
    public init() {}

    public var errorDescription: String? { "Aujour hasn't opened this day yet." }

    public var recoverySuggestion: String? {
        "Nothing has been changed. Wait for the day to open, then add your photo again."
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
