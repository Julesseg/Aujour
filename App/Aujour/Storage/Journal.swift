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

    private let locator: JournalRootLocator

    init(locator: JournalRootLocator = .system) {
        self.locator = locator
    }

    func open() async {
        state = .opening
        do {
            let opened = try await Self.openJournal(using: locator)
            store = opened.store
            state = .open(opened.root, fileCount: opened.fileCount)
        } catch {
            store = nil
            state = .unavailable(StorageProblem(error))
        }
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
