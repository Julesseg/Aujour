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

    /// What went wrong the last time the user pointed Aujour at a folder, if
    /// it did.
    ///
    /// Beside the journal rather than in place of it: a folder that could not
    /// be taken on is a request that did not happen, and the journal the user
    /// already had is still open and still theirs to write in.
    private(set) var folderProblem: StorageProblem?

    private let locator: JournalRootLocator
    private let settings: JournalSettings

    /// The open folder, presented: what Aujour's reads and writes take their
    /// turn through, and what says when somebody else has had theirs.
    ///
    /// Kept because presenting a folder is something held rather than done —
    /// letting go of it is what stops it, and a journal that has moved to
    /// another folder must not still be listening to the one it left.
    private var folder: CoordinatedJournalRoot?

    /// The reading of `folder.changes` that is currently running.
    private var keepingUpWithTheFolder: Task<Void, Never>?

    /// - Parameter settings: the journal-shaping settings today's Entry is
    ///   spawned and saved by. The defaults until the settings screen lands;
    ///   they arrive through iCloud key-value storage then (ADR 0003).
    init(locator: JournalRootLocator = .system, settings: JournalSettings = .default) {
        self.locator = locator
        self.settings = settings
    }

    func open() async {
        state = .opening
        today = nil
        calendar = nil
        // Before anything is opened, whatever folder was open stops being
        // presented: a change arriving from the folder being left would be
        // answered by re-reading a file in a journal that is no longer this
        // one.
        stopKeepingUpWithTheFolder()
        do {
            let opened = try await Self.openJournal(using: locator, settings: settings)
            let editor = EntryEditor(store: opened.store, settings: settings)
            store = opened.store
            today = editor
            calendar = JournalCalendar(store: opened.store, settings: settings)
            folder = opened.folder
            state = .open(opened.root, entryCount: opened.entryCount)
            await editor.open()
            keepUpWith(opened.folder.changes)
        } catch {
            store = nil
            calendar = nil
            state = .unavailable(StorageProblem(error))
        }
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
    /// folder here would be holding a presenter registered for a journal
    /// nobody has open any more. This way, letting go of the Journal ends the
    /// presenting, which ends the stream, which ends this.
    private func keepUpWith(_ changes: AsyncStream<Void>) {
        keepingUpWithTheFolder = Task { [weak self] in
            for await _ in changes {
                await self?.catchUpWithTheFolder()
            }
        }
    }

    /// Shows what the folder says now, where nothing is waiting to be written
    /// to it.
    ///
    /// Also the app's way back in from the background, where nothing was
    /// listening: a day written on the iPad over lunch is on screen when the
    /// iPhone comes back to the front, without the user asking.
    func catchUpWithTheFolder() async {
        await today?.reloadIfClean()
    }

    private func stopKeepingUpWithTheFolder() {
        keepingUpWithTheFolder?.cancel()
        keepingUpWithTheFolder = nil
        folder?.stopWatching()
        folder = nil
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
        guard await saveWhatBelongsToTheFolderBeingLeft() else { return }
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
        guard await saveWhatBelongsToTheFolderBeingLeft() else { return }
        locator.customRoot.forget()
        await open()
    }

    /// Writes what is on screen to the folder it belongs to, before that
    /// folder stops being the journal — and answers whether the move may go
    /// ahead.
    ///
    /// Today's Entry belongs to the folder being left, and this is the last
    /// moment it can be written there: after the switch its file is not one
    /// Aujour is looking at any more, and the editor holding those words is
    /// replaced. So a save that will not go stops the move, exactly as it
    /// stops the day turning under the editor — no words are ever silently
    /// discarded (`v1-decisions.md`).
    private func saveWhatBelongsToTheFolderBeingLeft() async -> Bool {
        guard let today else { return true }
        await today.save()
        guard let unsaved = today.saveProblem else { return true }
        folderProblem = StorageProblem(unsaved)
        return false
    }

    /// Counts the Entries in the folder again.
    ///
    /// The count comes from a single listing at launch, which stops being
    /// true the moment today's first edit creates a file — so whatever shows
    /// it asks again rather than repeating what the app was told once. A
    /// folder that will not answer keeps the old count: this is a number
    /// beside the journal, not the journal.
    func recount() async {
        guard case .open(let root, _) = state, let store else { return }
        guard let files = try? await store.listFiles() else { return }
        state = .open(root, entryCount: Self.entryCount(among: files, by: settings))
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
