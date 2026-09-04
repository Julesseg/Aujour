import Foundation
import Observation
import AujourCore

/// Something that went wrong with the journal folder, in the two sentences a
/// screen needs: what happened, and what the user can do about it.
///
/// Every failure gets one. A storage error the app cannot name is still shown
/// — an unexplained empty page in a journaling app reads as lost words, and
/// that is the one thing it must never look like when nothing has been lost
/// (ADR 0001).
struct StorageProblem: Equatable, Sendable {
    let message: String
    let suggestion: String

    init(_ error: any Error) {
        let presentable = error as? any LocalizedError
        message = presentable?.errorDescription ?? "Aujour couldn't open your journal folder."
        suggestion =
            presentable?.recoverySuggestion
            ?? "Nothing has been changed. Try again in a moment — your entries are files in the folder, and they're still there."
    }
}

/// Asked to plan a Path Template change with no folder open to plan it over.
///
/// Not reachable from the screen — the entry path is only offered where the
/// journal is open — and said in the same two sentences as every other
/// storage failure rather than as a silence, because a change that appeared
/// to do nothing is the one outcome a user would repeat.
struct NoJournalIsOpen: LocalizedError {
    var errorDescription: String? { "Aujour hasn't opened your journal folder yet." }

    var recoverySuggestion: String? {
        "Nothing has been changed. Wait for the folder to open, then change where your entries go."
    }
}

/// The user's Journal, as this installation has it: the folder opened on
/// launch — the one they pointed Aujour at, or the one it found for itself —
/// a Journal Store over it, and whichever of the two answers came back for
/// the screen to render.
///
/// Moving it is here too, because a Journal is the folder it is over: pointing
/// Aujour at a folder in an Obsidian vault closes this journal and opens the
/// one that folder already is, entries, calendar and all.
///
/// There is exactly one per app installation, which is what the glossary
/// means by a Journal — the app holds no journal content of its own, only the
/// way in to the files. This is the whole of "a fresh install just works" as
/// the screen sees it; nothing above here knows about iCloud or `URL`s
/// (ADR 0001).
@MainActor
@Observable
final class Journal {
    enum State: Equatable {
        /// Finding the folder. Asking iCloud for the container is slow the
        /// first time on a device, so this is a state and not a blink.
        case opening
        /// Journaling, into a folder holding this many Entries — or `nil` for
        /// a Path Template that cannot say which files are Entries, where the
        /// honest number is no number.
        case open(JournalRoot, entryCount: Int?)
        case unavailable(StorageProblem)
    }

    private(set) var state: State = .opening

    /// The seam the rest of the app journals through, once there is a folder
    /// to journal into.
    private(set) var store: (any JournalStore)?

    /// Today's Entry, over that folder — the screen the app opens on.
    ///
    /// Made here rather than by the view, because it is the folder that
    /// decides whether there is an Entry to edit at all: until one has been
    /// found there is nothing for an editor to be over, and the screen says
    /// so instead of showing an empty page (ADR 0001).
    private(set) var today: EntryEditor?

    /// The Journal a month at a time, over the same folder: which days were
    /// written on, and the way back into any of them.
    ///
    /// Made once and kept, so that a month browsed to is still the month on
    /// screen the next time the calendar is opened. What it holds is only a
    /// scan of the folder, and throwing it away costs nothing (ADR 0001).
    private(set) var calendar: JournalCalendar?

    /// The Journal by something written in it, over the same folder — the way
    /// back into a day whose date nobody remembers.
    ///
    /// Made once and kept, like the calendar, so that what was read last time
    /// the search screen was open is on screen the moment it is opened again.
    /// What it holds is a reading of the folder and a cache of that reading,
    /// and throwing either away costs nothing (ADR 0001).
    private(set) var search: JournalSearch?

    /// Where a day's markdown is spawned from, over the open folder — kept so
    /// that every screen that opens a day starts it from the same file, and
    /// reads it afresh when it does (ADR 0005).
    private var template: ContentTemplateFile?

    /// What went wrong the last time the user pointed Aujour at a folder, if
    /// it did.
    ///
    /// Beside the journal rather than in place of it: a folder that could not
    /// be taken on is a request that did not happen, and the journal the user
    /// already had is still open and still theirs to write in.
    private(set) var folderProblem: StorageProblem?

    /// The Parked Files this journal has set aside since it was opened, oldest
    /// first — what the screen tells the user about.
    ///
    /// Kept until they say they have seen it, and not longer: the file itself
    /// is the lasting notice, sitting beside the Entry in their vault. This is
    /// only how they come to know it is there without going and looking.
    private(set) var parkedFiles: [ParkedFile] = []

    private let locator: JournalRootLocator

    /// The journal-shaping settings, and the seam they sync through: today's
    /// Entry is spawned and saved by these, and which files are Entries at all
    /// is the Path Template among them (ADR 0002, ADR 0003).
    private let settingsStore: JournalSettingsStore

    /// What they say right now — read afresh rather than copied, because they
    /// change under a running app, from this device and from another.
    private var settings: JournalSettings { settingsStore.settings }

    /// The settings observation that reopens the journal when they change.
    /// Held so that it lives exactly as long as this Journal.
    private var watchingTheSettings: SettingsObservation?

    /// The reopening a settings change set going, if one is still under way —
    /// what changing the Path Template here waits on before it says it is
    /// done.
    private var reopening: Task<Void, Never>?

    /// The template picked outside the journal folder, if one was — this
    /// device's own, kept in local storage because a bookmark means nothing on
    /// another device (ADR 0003, ADR 0005).
    private let templateElsewhere: BookmarkedTemplateFile

    /// Where the Content Template's data placeholders read the day from —
    /// EventKit, unless a test is standing in for it.
    ///
    /// Held for the life of the Journal rather than made per spawn: it is a
    /// connection to the calendar, and one is enough for every day the user
    /// opens.
    private let dayData: DayData

    /// Where the suggestions panel reads the day's photographs — the device's
    /// photo library, unless a test is standing in for it.
    ///
    /// Held here and handed to the screens rather than made by them, for the
    /// reason the calendar is: it is the device, and a UI test may not have
    /// the device's own.
    let photoLibrary: any PhotoLibrary

    /// Where the `{{location}}` widget reads the place from — the device's own
    /// location, unless a test is standing in for it.
    ///
    /// Held here and handed to the screens for the reason the photo library is:
    /// it is the device, and a UI test may not have the device's own — a real
    /// one would put a system permission alert in the middle of a test.
    let places: any Places

    /// What the system is holding besides the file at an Entry's path — iCloud,
    /// unless a test is standing in for it.
    private let versions: any EntryVersions

    /// The settings that belong to this device alone — the theme, the editor's
    /// font, and the time of the daily reminder (ADR 0003).
    ///
    /// Made once for the whole install and handed out rather than made by
    /// whoever needs one: two stores over the same `UserDefaults` would each
    /// write settings the other never hears about, and the appearance is read
    /// through this one too.
    let deviceSettings: DeviceSettingsStore

    /// The queries this device has searched with, kept across journals rather
    /// than per folder: what somebody looked for is a fact about them and not
    /// about a vault, and a journal moved into Obsidian is the same person
    /// looking for the same handful of things (ADR 0003).
    private let recentSearches: RecentSearchesStore

    /// One gentle nudge a day, at a time the user chose — and none on a day
    /// whose Entry is already in the folder.
    ///
    /// Here rather than beside the screen that sets it, because what it has to
    /// decide is a question about the journal: which day is current under this
    /// Rollover Hour, and whether that day's Entry file exists. Everything
    /// below that reopens or re-reads the folder tells it so.
    let dailyReminder: DailyReminder

    /// The brief hello a fresh install gets, and the offer of that reminder on
    /// its last page.
    ///
    /// Here for the reason the reminder is here, and not because a welcome is
    /// about a folder: it is made from the same Device Settings everything
    /// else device-local reads, and the offer it ends on is *this* reminder —
    /// the one the settings sheet shows a time for afterwards. Nothing it does
    /// touches the Journal, which is the point of it: the folder is found and
    /// today's Entry is spawned behind it, so the app is ready to be written
    /// in before anybody has tapped anything (ADR 0004).
    let welcome: Welcome

    /// How a day written twice is settled, over the open folder.
    private var parking: DivergenceParking?

    /// Whether a divergence is being settled right now.
    ///
    /// The app comes back to the front and the folder reports a change at the
    /// same moment more often than it sounds, and both ask for this. Two
    /// settlings of one divergence would each find the versions unresolved,
    /// and the second would leave a `_2` holding a copy of what the first had
    /// just parked — litter in somebody's vault, in the one place the app
    /// promises to be careful.
    private var settlingADivergence = false

    /// The open folder, presented: what Aujour's reads and writes take their
    /// turn through, and what says when somebody else has had theirs.
    ///
    /// Kept because presenting a folder is something held rather than done —
    /// letting go of it is what stops it, and a journal that has moved to
    /// another folder must not still be listening to the one it left.
    private var folder: CoordinatedJournalRoot?

    /// The reading of `folder.changes` that is currently running.
    private var keepingUpWithTheFolder: Task<Void, Never>?

    /// - Parameters:
    ///   - settings: the journal-shaping settings today's Entry is spawned and
    ///     saved by, and the seam they arrive through from the user's other
    ///     devices (ADR 0003).
    ///   - dayData: where `{{events}}` and `{{reminders}}` read the day being
    ///     spawned from. The user's own calendar and reminders, unless a test
    ///     says otherwise — a UI test journals into a folder of its own and
    ///     reads a calendar of its own with it.
    ///   - photoLibrary: where the suggestions panel reads the day's
    ///     photographs from. The device's own, unless a test says otherwise —
    ///     and for the same reason as the calendar, since a real library would
    ///     put a system permission alert in the middle of a UI test.
    ///   - places: where the `{{location}}` widget reads the place from. The
    ///     device's own, unless a test says otherwise — and for the same
    ///     reason as the library.
    ///   - deviceSettings: the settings that stay on this device — the theme,
    ///     the editor's font and the daily reminder's time. One per install,
    ///     and handed in rather than made here so that everything reading them
    ///     reads the same one.
    ///   - recentSearches: where the queries somebody searched with are kept.
    ///     This device's own `UserDefaults`, unless a test says otherwise —
    ///     one test's searches must not be the next test's list.
    ///   - nudges: where the daily reminder is booked — the device's
    ///     notification centre, unless a test says otherwise, since a
    ///     permission alert from another process is not something a UI test
    ///     can answer.
    init(
        locator: JournalRootLocator = .system,
        settings: JournalSettingsStore? = nil,
        templateElsewhere: BookmarkedTemplateFile = .stored(),
        versions: any EntryVersions = ICloudVersions(),
        dayData: DayData = EventKitDayData().dayData,
        photoLibrary: any PhotoLibrary = PhotoKitLibrary(),
        places: any Places = CoreLocationPlaces(),
        deviceSettings: DeviceSettingsStore? = nil,
        recentSearches: RecentSearchesStore? = nil,
        nudges: any Nudges = DeviceNudges()
    ) {
        // Made here rather than as a default argument: the store it is over
        // reads iCloud, which is main-actor work, and a default argument is
        // evaluated wherever the caller happens to be.
        let settings = settings ?? JournalSettingsStore(syncedThrough: SyncedSettingsStorage())
        // For the same reason: `UserDefaults` is read on the main actor.
        let deviceSettings =
            deviceSettings ?? DeviceSettingsStore(storedOn: LocalSettingsStorage())
        self.locator = locator
        self.settingsStore = settings
        self.templateElsewhere = templateElsewhere
        self.versions = versions
        self.dayData = dayData
        self.photoLibrary = photoLibrary
        self.places = places
        self.deviceSettings = deviceSettings
        // For the same reason as the device settings: `UserDefaults` is read
        // on the main actor, so it cannot be a default argument.
        self.recentSearches =
            recentSearches ?? RecentSearchesStore(storedOn: LocalSettingsStorage())
        // Held in a local first: the welcome offers this reminder rather than
        // one of its own, so a time taken up on its last page is the time the
        // settings sheet is showing a moment later.
        let reminder = DailyReminder(settings: deviceSettings, nudges: nudges)
        self.dailyReminder = reminder
        self.welcome = Welcome(settings: deviceSettings, reminder: reminder)

        // A Path Template changed on the iPad reshapes what an Entry is here
        // too (ADR 0002), and so does one changed on this device — which is
        // why adopting one is a write to the settings and nothing more. The
        // journal is reopened either way: today's Entry is a different file
        // afterwards, and so is every mark on the calendar.
        watchingTheSettings = settings.observe { [weak self] _ in
            guard let self else { return }
            reopening = Task { await self.open() }
        }
    }

    func open() async {
        state = .opening
        today = nil
        calendar = nil
        search = nil
        // Whatever was parked belonged to the folder being left. The files are
        // still there, beside the Entries they diverged from; it is the notice
        // that does not carry over into somebody else's vault.
        parkedFiles = []
        // Before anything is opened, whatever folder was open stops being
        // presented: a change arriving from the folder being left would be
        // answered by re-reading a file in a journal that is no longer this
        // one.
        stopKeepingUpWithTheFolder()
        do {
            let opened = try await Self.openJournal(using: locator, settings: settings)
            // Made here, once, and handed to both: today's Entry and a day
            // backfilled from the calendar start from the same file.
            let template = ContentTemplateFile(
                insideTheFolder: settings.contentTemplateFile,
                folder: opened.store,
                elsewhere: templateElsewhere
            )
            let editor = EntryEditor(
                store: opened.store,
                settings: settings,
                spawningFrom: template,
                dayData: dayData
            )
            store = opened.store
            self.template = template
            today = editor
            calendar = JournalCalendar(
                store: opened.store,
                settings: settings,
                spawningFrom: template,
                dayData: dayData
            )
            search = JournalSearch(
                store: opened.store,
                settings: settings,
                cache: SearchIndexFile(forJournalAt: opened.root.url),
                recent: recentSearches
            )
            folder = opened.folder
            parking = DivergenceParking(store: opened.store, versions: versions)
            state = .open(opened.root, entryCount: opened.entryCount)
            // Before the Entry is read, so that what is read is the version
            // that won the day's path: a divergence that arrived while the app
            // was closed is settled on the way in, not shown and then swapped
            // out from under the user.
            await settleAnyDivergence(before: editor)
            // Whatever the day's data placeholders need asking for, asked
            // here — before the day is spawned rather than during it, which is
            // what keeps a system permission alert out from in front of an
            // Entry that is meant to be appearing (`DayItemSource.prepare()`).
            // Only what this Content Template names is ever asked about, so a
            // journal with no `{{events}}` in it never mentions the calendar —
            // which means reading the template file here, as a spawn would
            // (ADR 0005), rather than guessing at what it says.
            await dayData.prepare(
                for: ContentTemplate(await template.markdown() ?? "").dataPlaceholders
            )
            await editor.open()
            keepUpWith(opened.folder.changes)
        } catch {
            store = nil
            calendar = nil
            search = nil
            template = nil
            parking = nil
            state = .unavailable(StorageProblem(error))
        }
        // After both outcomes, because both are news to it: a folder that
        // opened is one it can ask which days are written, and a folder that
        // did not is one where the reminder still has to be booked for the
        // days it knows nothing about. A Rollover Hour or a Path Template
        // changed anywhere reaches here too — every settings change reopens
        // the journal, and both of those decide which day a nudge is about.
        await reconsiderTheDailyReminder()
    }

    /// The way in to a day that already has a file — what a search result is
    /// opened with.
    ///
    /// Not the calendar's `editor(for:)`, which is about which days may be
    /// *written* and locks the ones that have not arrived. A day a search
    /// found is a day with an Entry in the folder, whatever its date says, and
    /// a file the user can open in Obsidian is one Aujour must not refuse to
    /// show them.
    ///
    /// A fresh editor each time, pinned to the day asked for, and the caller's
    /// to keep for as long as that day is on screen — two editors over one
    /// Entry would autosave that day's file over each other.
    func editor(for day: JournalDay) -> EntryEditor? {
        guard let store else { return nil }
        return EntryEditor(
            store: store,
            settings: settings,
            spawningFrom: template,
            dayData: dayData,
            day: day
        )
    }

    // MARK: - Keeping up with the folder

    /// Follows what other apps write in the folder, for as long as it is the
    /// open one.
    ///
    /// Today's Entry is what this catches up: it is the screen the app lives
    /// on, and the one that is still open while Obsidian is writing the same
    /// file on the other side of the multitasking split. A day reached from
    /// the calendar is a step away and reads its file each time it is opened,
    /// so it does not need telling.
    ///
    /// Takes the changes and not the folder they come from, deliberately: a
    /// task waiting on a stream is kept alive by the runtime, so holding the
    /// folder here would be one more thing keeping a presenter alive for a
    /// journal nobody has open. What ends both is `stopKeepingUpWithTheFolder`
    /// — the stream ends when the presenting does, and this ends with it.
    private func keepUpWith(_ changes: AsyncStream<JournalRootChange>) {
        keepingUpWithTheFolder = Task { [weak self] in
            for await _ in changes {
                await self?.catchUpWithTheFolder()
            }
        }
    }

    /// Shows what the folder says now: today's Entry catches up with its file
    /// where nothing is waiting to be written to it, and the calendar's
    /// indicators are read again.
    ///
    /// The indicators are only ever a scan of the folder (ADR 0001), so this
    /// is the same reading the calendar does on the way in, done at the moment
    /// there is something new to read. One at a time, because that is what a
    /// stream of changes read one at a time gives: a folder in the middle of a
    /// sync is walked once per catch-up and not once per file.
    private func catchUpWithTheFolder() async {
        // First, because it decides what the file at today's path says: a day
        // two devices wrote is settled before the Entry is re-read, and never
        // the other way round.
        if let today { await settleAnyDivergence(before: today) }
        await today?.reloadIfClean()
        await calendar?.scan()
        // A day written in Obsidian on the other side of the split, or arriving
        // from the iPad, is a day with no reason left to be asked about.
        await reconsiderTheDailyReminder()
    }

    /// Settles the day this editor is over if two devices wrote it, and
    /// remembers the Parked Files to tell the user about.
    ///
    /// Said of an editor rather than of a day, because it is having a day open
    /// that makes this worth doing: the Entry is about to be read, or has just
    /// been changed underneath, and the words in front of the user have to be
    /// part of the reckoning. Every way into a day goes through one — today's
    /// screen and a day filled in from the calendar alike — so every day the
    /// user actually opens is settled, and the days nobody has opened are left
    /// for the launch that opens them.
    func settleAnyDivergence(before editor: EntryEditor) async {
        guard let parking, let path = entryPath(for: editor.day) else { return }
        // Asked first because the answer is almost always no, and everything
        // below is work — including a save the user did not ask for.
        guard !settlingADivergence, parking.hasDiverged(path) else { return }
        settlingADivergence = true
        defer { settlingADivergence = false }

        // What is on screen goes into the file before the versions are weighed
        // against each other. Otherwise the words being typed are the one
        // version not on disk, and a version arriving from another device
        // could take the Entry path from underneath them.
        //
        // Which does decide it, and deliberately: an Entry with unsaved words
        // keeps its path, because writing them is what makes the file the
        // newest version — and they *are* the newest, typed after anything
        // that arrived while they were being typed. The version that arrived
        // is parked rather than dropped, so what this costs is which of the
        // two the user finds at the day's own path.
        await editor.save()
        // And if they would not go, nothing is settled at all. A version that
        // took the Entry path here would be written over by the next autosave
        // that does succeed — the one way this could actually lose a version.
        // The conflict stays open instead, and the next change tries again.
        guard editor.saveProblem == nil else { return }

        // Silent when it will not go, deliberately: nothing has been lost —
        // the file is as it was and the conflict is still open — so the next
        // change in the folder tries again. A notice here would be a notice
        // about something the user cannot act on.
        guard let parked = try? await parking.park(path, of: editor.day) else { return }
        parkedFiles.append(contentsOf: parked.filter { !parkedFiles.contains($0) })
    }

    /// The Parked Files set aside from one day — which is what that day's
    /// screen has to say, and the only screen that has anything to say about
    /// them.
    func parkedFiles(from day: JournalDay) -> [ParkedFile] {
        parkedFiles.filter { $0.day == day }
    }

    /// The user has seen the notice for a day; the Parked Files themselves
    /// stay where they are, which is the point of them.
    func acknowledgeParkedFiles(from day: JournalDay) {
        parkedFiles.removeAll { $0.day == day }
    }

    /// Where a Parked File lies, for the one thing the screen offers to do
    /// with one: show it, in the app the folder belongs to.
    ///
    /// `nil` for a journal that is no longer open over the folder the file
    /// was parked in — one the user has pointed somewhere else since. The
    /// file is still where it was left, which is the whole point of a Parked
    /// File; this journal has simply stopped being the one that can say
    /// where.
    func whereItLies(_ file: ParkedFile) -> URL? {
        parking?.whereItLies(file)
    }

    /// Where a day's Entry belongs — `nil` for a Path Template that cannot say,
    /// which is a sentence the editor is already showing (ADR 0002).
    private func entryPath(for day: JournalDay) -> String? {
        guard let template = try? PathTemplate(settings.pathTemplate) else { return nil }
        return template.render(day)
    }

    /// The app coming back to the front.
    ///
    /// Two things in the order they have to happen. An app left running
    /// overnight comes back to a different Journal Day, and moving to it is
    /// what decides *which* file the catch-up below is about — the other way
    /// round, yesterday's Entry would be caught up with, and then left.
    ///
    /// Both are needed because an app in the background is told nothing: no
    /// presenter callback arrives for the day Obsidian wrote while Aujour was
    /// away, and no clock ticks over for it either.
    func cameBackToTheFront() async {
        await today?.reopenIfTheDayTurned()
        await catchUpWithTheFolder()
    }

    private func stopKeepingUpWithTheFolder() {
        keepingUpWithTheFolder?.cancel()
        keepingUpWithTheFolder = nil
        folder?.stopWatching()
        folder = nil
    }

    // MARK: - The daily reminder

    /// Sets the time to be nudged at, or turns the reminder off with `nil`, and
    /// leaves the device holding what should be pending afterwards.
    ///
    /// The two together, because they are one thing the user asked for: a time
    /// chosen and nothing booked is a reminder that would not arrive until the
    /// next launch, and a reminder turned off that is still pending is the one
    /// failure this setting must not have.
    func remindMeDaily(at time: TimeOfDay?) async {
        await dailyReminder.remind(at: time)
        await reconsiderTheDailyReminder()
    }

    /// Works out what the reminder should have pending and books exactly that.
    ///
    /// Called from every direction that can have changed the answer: the
    /// journal opening or reopening, the folder changing underneath, the app
    /// coming back to the front, and the app going away — which is the moment
    /// today's words have just been written, and so the moment today's nudge
    /// stops being worth sending.
    ///
    /// It is the Journal that knows all of them, which is why the reminder is
    /// held here: what it has to decide is a question about a folder — which
    /// day is current under this Rollover Hour, and whether that day's Entry
    /// file exists — even though the time it asks at never leaves this device.
    func reconsiderTheDailyReminder() async {
        await dailyReminder.reconsider(over: store, journal: settings)
    }

    /// Ends the welcome, taking its offer up at `time` or leaving the reminder
    /// where it was with `nil` — and books whatever that leaves due.
    ///
    /// Here rather than on the `Welcome` for the reason ``remindMeDaily(at:)``
    /// is here: what should be pending is a question about this folder, and a
    /// time taken up with nothing booked is a reminder that would not arrive
    /// until the next launch. The reckoning is worth doing for the skip too —
    /// it is what clears anything a previous install left pending.
    func endTheWelcome(remindingAt time: TimeOfDay?) async {
        await welcome.end(remindingAt: time)
        await reconsiderTheDailyReminder()
    }

    /// Whether the Journal is pointed at a folder the user picked.
    ///
    /// Asked of what the device remembers rather than of the state, so that
    /// it is still true when the chosen folder is the reason there is no
    /// journal open — which is exactly when the way back has to be offered.
    var hasACustomFolder: Bool { locator.customRoot.hasBeenChosen }

    /// Points the Journal at a folder the user picked in the Files app, and
    /// opens it.
    ///
    /// The Journal *becomes* whatever Entries are already in that folder —
    /// nothing is written into it, and nothing is carried over from where the
    /// journal was before. That is the point of picking a folder inside an
    /// Obsidian vault: the daily notes that are already there are the journal
    /// from now on, and the rest of the vault is untouched, because only
    /// files the Path Template names are Entries at all (ADR 0002).
    func use(_ folder: URL) async {
        folderProblem = nil
        if let unsaved = await saveWhatIsOnScreenWhereItBelongsNow() {
            folderProblem = StorageProblem(unsaved)
            return
        }
        do {
            try locator.customRoot.choose(folder)
        } catch {
            // Nothing was changed, so nothing is closed: the journal that was
            // open stays open, with a sentence beside it.
            folderProblem = StorageProblem(error)
            return
        }
        await open()
    }

    /// Back to the folder Aujour finds for itself, and open it.
    ///
    /// The chosen folder is forgotten and never touched — the Entries written
    /// into it stay where the user can still find them in the Files app and
    /// in Obsidian (ADR 0001).
    func useAujoursOwnFolder() async {
        folderProblem = nil
        if let unsaved = await saveWhatIsOnScreenWhereItBelongsNow() {
            folderProblem = StorageProblem(unsaved)
            return
        }
        locator.customRoot.forget()
        await open()
    }

    // MARK: - Changing the Path Template

    /// The Path Template in force, exactly as it is stored — what the user is
    /// shown when they go to change it.
    var pathTemplate: String { settings.pathTemplate }

    /// Whether there is a folder open to change anything about. A journal
    /// still opening, or one that could not be, has no Entries to plan a
    /// migration over.
    var isOpen: Bool {
        if case .open = state { true } else { false }
    }

    /// The Journal Day the app is on — which is what an entry path is worth
    /// showing an example for, since it names a file the user could go and
    /// look at.
    ///
    /// Today's Entry where there is one, and the same reckoning it was made
    /// by where there is not: the Rollover Hour, and not the calendar date. At
    /// 1 AM under a 4 AM rollover the day being written is yesterday, and an
    /// example naming today's file would name a file nothing is going to write.
    var dayOnScreen: JournalDay {
        today?.day
            ?? JournalDay.current(
                at: Date(),
                in: .current,
                rolloverHour: settings.rolloverHour
            )
    }

    /// What changing the Path Template to this would do to the folder: which
    /// Entries move where, and which days already have a file sitting at the
    /// path they would move to.
    ///
    /// Asking changes nothing. The plan *is* the offer — a migration is
    /// skippable, so what is being skipped has to be sayable first (ADR 0002)
    /// — and it is worked out afresh every time, over the folder as it is
    /// this moment rather than as it was at launch.
    ///
    /// Today's words are written to the file they belong to *now* before the
    /// folder is read, so that the migration moves them along with the rest
    /// of the journal. A save that will not go stops the whole thing: what is
    /// on screen would otherwise be autosaved, a moment later, to a path that
    /// has stopped meaning anything.
    func planChangingThePathTemplate(to template: PathTemplate) async throws -> MigrationPlan {
        guard let store else { throw NoJournalIsOpen() }
        if let unsaved = await saveWhatIsOnScreenWhereItBelongsNow() { throw unsaved }

        // A stored template that cannot be read names no Entries at all
        // (ADR 0002), so there is nothing in the folder to move — and
        // changing away from it is exactly what fixes that.
        guard let current = try? PathTemplate(settings.pathTemplate) else {
            return MigrationPlan(moves: [])
        }
        return try await JournalMigration(over: store).plan(changingFrom: current, to: template)
    }

    /// Adopts a Path Template — moving the Entries a plan names, or leaving
    /// them where they are, which is what skipping the migration means.
    ///
    /// The order is the point. The files are moved first and the template is
    /// changed after, so that at no moment is an Entry's path a path Aujour
    /// has not put its file at yet.
    ///
    /// Skipping is a real choice and not a deferral: the old files stay on
    /// disk untouched, where they stop being Entries and stop being surfaced
    /// anywhere in the app. Aujour keeps no list of them and offers no way
    /// back — they are the user's, in their folder, to move or keep or delete
    /// in Files or in Obsidian (ADR 0002).
    ///
    /// Adopting is a write to the settings and nothing more — see
    /// ``adopt(_:)`` — so a caller that gets an outcome back is looking at a
    /// journal that has already reopened onto the new shape.
    ///
    /// - Parameter progress: told how far through the moving is, as each day
    ///   settles. Called here on the main actor, in order, and never after
    ///   this returns — so the screen watching it can set what it draws
    ///   directly. Nothing is reported for a skipped migration: no file moves,
    ///   and there is no length of time to say anything about.
    @discardableResult
    func changeThePathTemplate(
        to template: PathTemplate,
        movingEntriesBy plan: MigrationPlan?,
        reporting progress: (MigrationProgress) -> Void = { _ in }
    ) async -> MigrationOutcome? {
        var outcome: MigrationOutcome?
        if let plan, !plan.isEmpty, let store {
            outcome = await JournalMigration(over: store).carryOut(plan, reporting: progress)
        }

        await adopt { $0.pathTemplate = template.format }
        return outcome
    }

    /// Writes a journal-shaping settings change, and waits for the journal to
    /// have reopened around it.
    ///
    /// Adopting a setting is a write to the settings and nothing more; what
    /// makes the journal reshape itself is the same observation that reshapes
    /// it when the iPad changes one. That observation runs while `update` is
    /// still on the stack, which is what leaves `reopening` holding a task to
    /// wait on here — so a caller that gets control back is looking at a
    /// journal that has already reopened. Cleared first, so that a change the
    /// settings did not actually make waits on nothing.
    private func adopt(_ change: (inout JournalSettings) -> Void) async {
        reopening = nil
        settingsStore.update(change)
        await reopening?.value
    }

    // MARK: - How embeds are written

    /// The embed syntax in force — which of the two spellings a photograph
    /// added to a day is written in.
    var embedSyntax: EmbedSyntax { settings.embedSyntax }

    /// What an embed written into today's Entry would look like, under the
    /// templates in force.
    ///
    /// The setting made concrete on the day the user is actually in, the way
    /// the entry path is: two spellings described in words are two spellings
    /// somebody has to imagine, and this is the line that would go in the file.
    ///
    /// `nil` for templates that cannot be read, which is a sentence the entry
    /// path field is already showing.
    var exampleEmbed: String? {
        guard let entries = try? PathTemplate(settings.pathTemplate),
            let folders = try? AttachmentPathTemplate(settings.attachmentPathTemplate),
            let example = try? Attachment(
                .jpeg,
                writtenOn: dayOnScreen,
                under: folders,
                embeddedIn: entries.render(dayOnScreen),
                as: settings.embedSyntax,
                beside: []
            )
        else { return nil }
        return example.embed
    }

    /// Changes which spelling Aujour writes. Nothing already in the folder
    /// moves or is rewritten: both spellings are drawn as the picture they
    /// name whichever wrote them, and this decides only what goes in next.
    func changeTheEmbedSyntax(to syntax: EmbedSyntax) async {
        await change { $0.embedSyntax = syntax }
    }

    /// Writes what is on screen to the file it belongs to right now, before
    /// the ground under it moves — and answers what stopped it, if anything
    /// did.
    ///
    /// Two things move that ground, and both come through here: pointing
    /// Aujour at another folder, and changing the Path Template. Either way
    /// this is the last moment today's words can be written where they
    /// currently belong — afterwards the editor holding them is replaced, and
    /// in the migration's case the file they belong to has been moved. So a
    /// save that will not go stops what was about to happen, exactly as it
    /// stops the day turning under the editor: no words are ever silently
    /// discarded (`v1-decisions.md`).
    private func saveWhatIsOnScreenWhereItBelongsNow() async -> (any Error)? {
        guard let today else { return nil }
        await today.save()
        return today.saveProblem
    }

    // MARK: - What a day starts as, when it turns, and where its photos go

    /// What this device spawns new days from, said the way a screen would say
    /// it — the path inside the folder, the name of the file picked outside
    /// it, or `nil` for no template, which is a blank page.
    var contentTemplateName: String? {
        if let picked = templateElsewhere.name { return picked }
        if templateElsewhere.isSet {
            // Bookmarked and unresolvable: renamed, deleted, or on a drive
            // nobody has plugged in. Said as what it is rather than as no
            // template at all, since "there is one and Aujour cannot reach it"
            // is the sentence that explains the blank page.
            return nil
        }
        return settings.contentTemplateFile.isEmpty ? nil : settings.contentTemplateFile
    }

    /// Whether a template was picked that Aujour cannot reach right now —
    /// which is a blank page the user did not ask for, and the one thing about
    /// this setting worth saying out loud.
    var theTemplateIsOutOfReach: Bool {
        templateElsewhere.isSet && templateElsewhere.name == nil
    }

    /// Points new days at the file the user just picked, or at no file at all.
    ///
    /// Nothing is copied and nothing is written: the file stays where they
    /// keep it, and Aujour reads it when it spawns a day (ADR 0005). Where it
    /// sits decides how it is remembered — inside the journal folder it is a
    /// path their other devices can follow, anywhere else it is a bookmark
    /// this device holds alone (ADR 0003) — and picking either way forgets the
    /// other, so there is only ever one template.
    ///
    /// Today's words are written first, as every settings change writes them
    /// first: the journal reopens around the change. Which is also what makes
    /// the day on screen safe — a day that has words has a file by the time
    /// the journal comes back, so it is re-read rather than spawned again, and
    /// a template picked mid-sentence cannot take the sentence with it.
    func useAsTheContentTemplate(_ file: URL?) async {
        folderProblem = nil
        if let unsaved = await saveWhatIsOnScreenWhereItBelongsNow() {
            folderProblem = StorageProblem(unsaved)
            return
        }

        let inTheFolder = file.flatMap(pathInsideTheJournalFolder) ?? ""
        if let file, inTheFolder.isEmpty {
            templateElsewhere.remember(file)
        } else {
            templateElsewhere.forget()
        }

        // A path is a journal-shaping setting, and adopting one reopens the
        // journal by itself. A bookmark is not — nothing about the settings
        // changed — so that reopening is this.
        if inTheFolder != settings.contentTemplateFile {
            await adopt { $0.contentTemplateFile = inTheFolder }
        } else {
            await open()
        }
    }

    /// Where a picked file sits inside the journal folder, or `nil` for one
    /// that sits outside it.
    ///
    /// Compared as standardized paths and on a folder boundary, so that a
    /// `JournalNotes` folder beside `Journal` is outside it rather than a file
    /// with a long name inside it.
    private func pathInsideTheJournalFolder(_ file: URL) -> String? {
        guard case .open(let root, _) = state else { return nil }
        let folder = root.url.standardizedFileURL.path(percentEncoded: false)
        let path = file.standardizedFileURL.path(percentEncoded: false)
        let inside = folder.hasSuffix("/") ? folder : folder + "/"
        guard path.hasPrefix(inside) else { return nil }
        return String(path.dropFirst(inside.count))
    }

    /// When the current Journal Day advances.
    var rolloverHour: RolloverHour { settings.rolloverHour }

    /// Changes when the day turns.
    ///
    /// Today is a different day afterwards for anyone writing between the old
    /// hour and the new one, so the journal reopens onto whichever day it is
    /// now — and the words on screen go to the day they were written in
    /// first, which is the same care the editor takes when a day turns under
    /// it overnight.
    ///
    /// Nothing in the folder moves: every Entry already written is the day
    /// its path names, whatever hour the journal has since started turning at.
    func changeTheRolloverHour(to hour: RolloverHour) async {
        await change { $0.rolloverHour = hour }
    }

    /// The folder each day's Attachments go into, relative to the Journal
    /// Root.
    var attachmentPathTemplate: String { settings.attachmentPathTemplate }

    /// Changes where photographs go from here on.
    ///
    /// Nothing already in the folder moves. The photographs a journal holds
    /// are pointed at from the Entries that embed them, and moving one would
    /// break the day that names it — so unlike the Path Template there is no
    /// migration to offer, and this decides only where the next one lands
    /// (ADR 0002 is about Entries; an Attachment has no such identity).
    func changeTheAttachmentPathTemplate(to template: AttachmentPathTemplate) async {
        await change { $0.attachmentPathTemplate = template.format }
    }

    // MARK: - How the day's own data is written

    /// How one data placeholder writes itself into a spawned Entry: what its
    /// lines start with, what a line the day saw through starts with, the
    /// shape its times take, and what it says on a day that held nothing.
    func howItIsWritten(_ placeholder: DataPlaceholder) -> DataPlaceholderFormat {
        settings.dataPlaceholders[placeholder]
    }

    /// Changes how a data placeholder writes itself from here on.
    ///
    /// Nothing already in the folder is rewritten, and there is nothing to
    /// offer to: a placeholder is resolved once, at spawn, into plain markdown
    /// (ADR 0001) — so the lines in the days already written are the user's
    /// own text now, and this decides only what the next day spawned says.
    ///
    /// All four fields at once, because that is what the screen changing them
    /// has: they are one answer to one question, and writing them one at a
    /// time would reopen the journal four times over a single edit.
    func changeHowItIsWritten(
        _ placeholder: DataPlaceholder,
        to format: DataPlaceholderFormat
    ) async {
        await change { $0.dataPlaceholders[placeholder] = format }
    }

    /// Writes today's words where they belong now, then adopts a
    /// journal-shaping change — the shape every settings change here has.
    ///
    /// A save that will not go stops the change rather than costing the
    /// sentence being typed: adopting reopens the journal, and the Entry on
    /// screen is replaced when it does.
    private func change(_ edit: (inout JournalSettings) -> Void) async {
        var edited = settings
        edit(&edited)
        guard edited != settings else { return }

        folderProblem = nil
        if let unsaved = await saveWhatIsOnScreenWhereItBelongsNow() {
            folderProblem = StorageProblem(unsaved)
            return
        }
        await adopt(edit)
    }

    /// Off the main actor deliberately: asking for the iCloud container blocks,
    /// and so does reading the folder.
    private nonisolated static func openJournal(
        using locator: JournalRootLocator,
        settings: JournalSettings
    ) async throws -> (
        root: JournalRoot,
        store: FileJournalStore,
        folder: CoordinatedJournalRoot,
        entryCount: Int?
    ) {
        let root = try locator.locate()
        // Presented from the first read on: the store takes its turns with the
        // other apps in the folder on behalf of this, and it is what leaves
        // Aujour's own writes out of what the folder reports back.
        let folder = CoordinatedJournalRoot(root: root.url)
        let store = FileJournalStore(root: root.url, coordinatedBy: folder)
        // Reading the folder once here is what makes "it works" a fact rather
        // than a hope: a root that cannot be listed is not one to journal into.
        let files = try await store.listFiles()
        return (root, store, folder, entryCount(among: files, by: settings))
    }

    /// How many of a folder's files are Entries — which is how much journal
    /// is in it.
    ///
    /// Entries and not files, because the folder may be somebody's Obsidian
    /// vault: "4,312 files" as the size of their journal would be counting
    /// thousands of notes that are none of Aujour's business, on the same
    /// screen that promises it leaves them alone. A file is an Entry exactly
    /// when the current Path Template renders its path for some day
    /// (ADR 0002), and a template that cannot say gets no number rather than
    /// a wrong one.
    private nonisolated static func entryCount(
        among files: [String],
        by settings: JournalSettings
    ) -> Int? {
        guard let template = try? PathTemplate(settings.pathTemplate) else { return nil }
        return files.filter { template.match($0) != nil }.count
    }
}

extension JournalSettingsStore {
    /// Journal-shaping settings that live and die with the object holding
    /// them.
    ///
    /// For previews and for tests, which run on a machine that has an Aujour
    /// of its own: settings read from `UserDefaults` or from iCloud would be
    /// somebody's real Path Template, and a test that changed one would
    /// change theirs.
    static func inMemory() -> JournalSettingsStore {
        JournalSettingsStore(syncedThrough: InMemorySyncedKeyValueStore())
    }
}

extension Journal {
    /// A Journal for a preview: settings, device settings and a notification
    /// centre that all live and die with the canvas.
    ///
    /// All three in one place because a preview reaches all three — opening a
    /// journal reads the settings, spawns today and books the daily reminder —
    /// and the machine drawing the canvas has an Aujour of its own. A preview
    /// that read `UserDefaults` would be showing somebody's real Path Template
    /// and their real reminder, and one that booked a nudge would go on
    /// delivering it after the canvas was closed.
    ///
    /// - Parameter welcomed: whether this device has already been through the
    ///   welcome. Yes by default, because every canvas but the welcome's own is
    ///   drawing a screen from *inside* the app — a preview of today's Entry
    ///   with the first-run cover over it would be a preview of the cover.
    static func inAPreview(
        over locator: JournalRootLocator,
        welcomed: Bool = true
    ) -> Journal {
        let deviceSettings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        deviceSettings.update { $0.hasBeenWelcomed = welcomed }
        return Journal(
            locator: locator,
            settings: .inMemory(),
            deviceSettings: deviceSettings,
            nudges: ADeviceThatIsNeverRung()
        )
    }
}

extension JournalRoot.Location {
    /// Where the user would go looking for their journal in the Files app.
    ///
    /// The device's own name for itself, because "On My iPhone" on an iPad
    /// names a place that is not there — the app runs on both.
    func name(onDevice device: String) -> String {
        switch self {
        case .aujoursOwn(.iCloudDrive): "iCloud Drive › Aujour"
        case .aujoursOwn(.onThisDevice): "On My \(device) › Aujour"
        // Their own name for their own folder, which is what they picked it
        // by and the only part of where it sits that Aujour can be sure of.
        case .customFolder(let name): name
        }
    }

    /// What being in this place means for their words — the part that decides
    /// whether deleting the app costs them anything.
    func promise(onDevice device: String) -> String {
        switch self {
        case .aujoursOwn(.iCloudDrive):
            "Your entries are markdown files here. They sync to your other devices, and they stay in iCloud Drive even if you delete Aujour."
        case .aujoursOwn(.onThisDevice):
            "iCloud Drive is off, so your entries are markdown files on this \(device) only. Turn on iCloud Drive to sync them and keep them if you delete Aujour."
        case .customFolder:
            // The sentence the whole milestone is for: a vault is thousands
            // of files that are none of Aujour's business, and this says
            // which ones are.
            "Your entries are markdown files in the folder you chose, and they sync however that folder does. Aujour only ever reads and writes the files your entry path names — everything else in the folder is left alone."
        }
    }

    func symbolName(onDevice device: String) -> String {
        switch self {
        case .aujoursOwn(.iCloudDrive): "icloud"
        case .aujoursOwn(.onThisDevice): device.lowercased() == "ipad" ? "ipad" : "iphone"
        case .customFolder: "folder"
        }
    }
}
