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

/// The user's Journal, as this installation has it: the folder found on
/// launch, a Journal Store over it, and whichever of the two answers came
/// back for the screen to render.
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
        case open(JournalRoot, fileCount: Int)
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

    /// The Journal's history, over the same folder: which days were written
    /// on, and the way back into any of them.
    ///
    /// Made once and kept, so that a month browsed to is still the month on
    /// screen the next time the calendar is opened. What it holds is only a
    /// scan of the folder, and throwing it away costs nothing (ADR 0001).
    private(set) var history: JournalCalendar?

    private let locator: JournalRootLocator
    private let settings: JournalSettings

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
        history = nil
        do {
            let opened = try await Self.openJournal(using: locator)
            let editor = EntryEditor(store: opened.store, settings: settings)
            store = opened.store
            today = editor
            history = JournalCalendar(store: opened.store, settings: settings)
            state = .open(opened.root, fileCount: opened.fileCount)
            await editor.open()
        } catch {
            store = nil
            history = nil
            state = .unavailable(StorageProblem(error))
        }
    }

    /// Re-reads how much is in the folder.
    ///
    /// The count comes from a single listing at launch, which stops being
    /// true the moment today's first edit creates a file — so whatever shows
    /// it asks again rather than repeating what the app was told once. A
    /// folder that will not answer keeps the old count: this is a number
    /// beside the journal, not the journal.
    func recount() async {
        guard case .open(let root, _) = state, let store else { return }
        guard let files = try? await store.listFiles() else { return }
        state = .open(root, fileCount: files.count)
    }

    /// Off the main actor deliberately: asking for the iCloud container blocks,
    /// and so does reading the folder.
    private nonisolated static func openJournal(
        using locator: JournalRootLocator
    ) async throws -> (root: JournalRoot, store: FileJournalStore, fileCount: Int) {
        let root = try locator.locate()
        let store = FileJournalStore(root: root.url)
        // Reading the folder once here is what makes "it works" a fact rather
        // than a hope: a root that cannot be listed is not one to journal into.
        let files = try await store.listFiles()
        return (root, store, files.count)
    }
}

extension JournalRoot.Location {
    /// Where the user would go looking for their journal in the Files app.
    ///
    /// The device's own name for itself, because "On My iPhone" on an iPad
    /// names a place that is not there — the app runs on both.
    func name(onDevice device: String) -> String {
        switch self {
        case .iCloudDrive: "iCloud Drive › Aujour"
        case .onThisDevice: "On My \(device) › Aujour"
        }
    }

    /// What being in this place means for their words — the part that decides
    /// whether deleting the app costs them anything.
    func promise(onDevice device: String) -> String {
        switch self {
        case .iCloudDrive:
            "Your entries are markdown files here. They sync to your other devices, and they stay in iCloud Drive even if you delete Aujour."
        case .onThisDevice:
            "iCloud Drive is off, so your entries are markdown files on this \(device) only. Turn on iCloud Drive to sync them and keep them if you delete Aujour."
        }
    }

    func symbolName(onDevice device: String) -> String {
        switch self {
        case .iCloudDrive: "icloud"
        case .onThisDevice: device.lowercased() == "ipad" ? "ipad" : "iphone"
        }
    }
}
