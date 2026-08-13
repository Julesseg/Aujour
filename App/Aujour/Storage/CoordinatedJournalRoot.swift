import Foundation

/// The Journal Root as a folder Aujour shares with other apps: everything it
/// reads and writes goes through file coordination, and it hears about what
/// anybody else writes.
///
/// The folder is not Aujour's. It is a folder in the Files app, very often one
/// inside an Obsidian vault, and iCloud Drive is writing into it from the
/// user's other devices. Two writers and no coordination is how a file ends up
/// half of each — so every read waits for whatever write is in flight, and
/// every write happens where the other side is waiting for it.
///
/// It is also what turns somebody else's write into something Aujour can act
/// on. A registered file presenter is told when the folder it presents
/// changes; each of those callbacks becomes an element of ``changes``, and
/// what to do about one is for whoever is reading that — the folder does not
/// know what is on screen.
///
/// Aujour's own writes are deliberately *not* among them: the coordinators
/// this hands out are made on behalf of this presenter, and a presenter is
/// never told about the writes it made itself. Without that, every autosave
/// would come back as news and the editor would re-read the file it had just
/// written, forever.
///
/// Registration is global and outlives the object, so a Journal that stops
/// being the open one has to say so — `stopWatching()`, or by letting go of it.
///
/// Unchecked because the only mutable state is behind a lock: the callbacks
/// arrive on the presenter's own queue, and the stream is read from wherever
/// the screen lives.
final class CoordinatedJournalRoot: NSObject, NSFilePresenter, @unchecked Sendable {
    /// The folder being presented — the Journal Root itself, so that a change
    /// to any file under it is a change this hears about.
    let presentedItemURL: URL?

    /// The queue the system delivers presenter callbacks on. Serial, and
    /// Aujour's own: the callbacks must not land on the main actor, where the
    /// coordinated read they are about to cause would be waiting.
    let presentedItemOperationQueue: OperationQueue

    /// Somebody else has written in the folder — a save in Obsidian, or a file
    /// iCloud has just brought down.
    ///
    /// One stream with one reader, which is the `Journal`: it is the only
    /// thing that knows which Entry is on screen and therefore what a change
    /// means. Nothing says *what* changed, deliberately — an Entry's file is
    /// one path, and whoever holds it can ask about it far more cheaply than
    /// this can guess.
    ///
    /// The newest element only. A folder in a vault changes in bursts (iCloud
    /// arriving with an evening's worth of another device's notes), and
    /// catching up once with the folder as it now is answers all of them.
    let changes: AsyncStream<Void>

    private let announce: AsyncStream<Void>.Continuation

    private let registration = NSLock()
    private var registered = false

    init(root: URL) {
        presentedItemURL = root.standardizedFileURL

        let queue = OperationQueue()
        queue.name = "Aujour.JournalRootPresenter"
        // Serially, so that a burst of changes is a sequence rather than a
        // scramble — and because all any of them do is wake the same reader.
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue

        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        changes = stream
        announce = continuation

        super.init()

        NSFileCoordinator.addFilePresenter(self)
        registered = true
    }

    deinit {
        stopWatching()
    }

    /// Stops presenting the folder: no more changes, and nothing left
    /// registered against a journal that is no longer open.
    ///
    /// Idempotent, because it is called both when a Journal moves to another
    /// folder and when the last reference to this one goes away.
    func stopWatching() {
        registration.lock()
        let wasRegistered = registered
        registered = false
        registration.unlock()

        guard wasRegistered else { return }
        NSFileCoordinator.removeFilePresenter(self)
        announce.finish()
    }

    /// A coordinator for Aujour's own reads and writes of this folder.
    ///
    /// Made on behalf of this presenter, which is what keeps Aujour's own
    /// writes from coming back to it as somebody else's changes.
    var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: self)
    }

    // MARK: - What the system tells a presenter

    /// The folder itself changed — a file added or removed directly under it.
    func presentedItemDidChange() {
        announce.yield(())
    }

    /// A file somewhere under the folder was written to.
    func presentedSubitemDidChange(at url: URL) {
        announce.yield(())
    }

    /// A file appeared under the folder: another device's day, arriving.
    func presentedSubitemDidAppear(at url: URL) {
        announce.yield(())
    }

    /// A file under the folder was renamed or moved — which, for an Entry's
    /// path, is a day appearing or disappearing.
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        announce.yield(())
    }

    /// Somebody is about to delete a file under the folder. Aujour holds
    /// nothing open that a deletion has to wait for — the words are in files,
    /// and this is a file going away — so it agrees at once and then looks
    /// again at what is left.
    func accommodatePresentedSubitemDeletion(
        at url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        completionHandler(nil)
        announce.yield(())
    }

    /// Somebody is about to delete the Journal Root itself. Agreed to for the
    /// same reason, and reported for a better one: everything Aujour is
    /// showing came out of a folder that is about to stop existing.
    func accommodatePresentedItemDeletion(
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        completionHandler(nil)
        announce.yield(())
    }
}
