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
/// Aujour's own writes are deliberately *not* among them. Without that, every
/// autosave would come back as news: the editor would re-read the file it had
/// just written, and the calendar would walk the whole folder, once per pause
/// in the typing. It takes two things, because the obvious one is not enough —
/// the coordinators this hands out are made on behalf of this presenter, which
/// leaves it out of what its own writes report, but only as the presenter *of
/// the file written*. This one presents the folder that file is in, so the
/// change comes back anyway, as a change to something inside what it presents.
/// What settles it is the file itself: one still exactly as Aujour left it is
/// Aujour's own write coming back.
///
/// Neither is what the folder already was when Aujour first looked at it.
/// Presenting a folder does not begin at the instant it is asked for — the
/// system notices uncoordinated writes by watching the file system, and that
/// watch reaches a little way into the past, so a write that had already
/// finished can arrive a second later looking exactly like one somebody has
/// just made. The file settles this one too: nothing has happened to a file
/// whose attributes have not been touched since presenting began, so a report
/// about it is about a write from before Aujour was there.
///
/// Registration is global: a presenter goes on being one until it says
/// otherwise, wherever the object holding it has got to. So `stopWatching()`
/// is what ends it, and whoever opened a folder is who calls it when that
/// folder stops being the journal. `deinit` says it too, for the case where
/// the last reference goes without anybody having said it — a backstop, and
/// not something to rely on, since a registered presenter may well be held by
/// the registration itself.
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
    /// means. What each change *says* is only ever which file it was about,
    /// and only so that a change can be recognised — for deciding what to do
    /// about one, whoever holds the Entry can ask the folder far more cheaply
    /// than this can guess.
    ///
    /// The newest element only. A folder in a vault changes in bursts (iCloud
    /// arriving with an evening's worth of another device's notes), and
    /// catching up once with the folder as it now is answers all of them.
    let changes: AsyncStream<JournalRootChange>

    private let announce: AsyncStream<JournalRootChange>.Continuation

    private let registration = NSLock()
    private var registered = false

    /// The moment Aujour started presenting the folder.
    ///
    /// The line between what Aujour was there for and what it was not. A
    /// presenter is not handed a folder as of the instant it registers: the
    /// system watches the file system to notice uncoordinated writes, and that
    /// watch begins a little way in the past — far enough that a write which
    /// had already finished arrives, a second or so later, as though somebody
    /// had just made it. So the folder is asked about anything reported to it,
    /// and a file nothing has happened to since this moment is a report about
    /// a write Aujour was not yet watching for.
    private let presentingSince: Date

    private let ownWrites = NSLock()
    /// When each file Aujour has written was last modified, as Aujour left it.
    ///
    /// Kept for the whole time a folder is presented, and that is the right
    /// length: it is one date per file Aujour has written this session, and
    /// the day a stale one is asked about is the day that file changed — which
    /// is exactly when the answer stops being "ours" anyway.
    private var asAujourLeftThem: [String: Date] = [:]

    init(root: URL) {
        presentedItemURL = root.standardizedFileURL

        let queue = OperationQueue()
        queue.name = "Aujour.JournalRootPresenter"
        // Serially, so that a burst of changes is a sequence rather than a
        // scramble — and because all any of them do is wake the same reader.
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue

        let (stream, continuation) = AsyncStream<JournalRootChange>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        changes = stream
        announce = continuation

        // Dated before registering rather than after, so that the error is
        // always the safe one: a write landing in between is one Aujour is
        // there for and reports, where a moment taken afterwards would have it
        // fall on the side of things that happened before anybody was looking.
        presentingSince = Date()

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
    /// Idempotent, because it is said from both ends — by the Journal that has
    /// moved to another folder, and by `deinit` for the one nobody said it
    /// for.
    func stopWatching() {
        registration.lock()
        let wasRegistered = registered
        registered = false
        registration.unlock()

        guard wasRegistered else { return }
        NSFileCoordinator.removeFilePresenter(self)
        announce.finish()
    }

    /// Told by the store when a write of Aujour's own has landed, from inside
    /// the coordinated access that made it — before the folder can report it,
    /// which is the only ordering that makes the answer below reliable.
    func aujourWrote(_ url: URL) {
        let path = url.standardizedFileURL.path
        let modified = modificationDate(of: url)
        ownWrites.lock()
        asAujourLeftThem[path] = modified
        ownWrites.unlock()
    }

    /// Whether this file is still exactly as Aujour left it — which makes a
    /// change reported for it Aujour's own, coming back.
    private func isAsAujourLeftIt(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        ownWrites.lock()
        let asWeLeftIt = asAujourLeftThem[path]
        ownWrites.unlock()

        guard let asWeLeftIt else { return false }
        return modificationDate(of: url) == asWeLeftIt
    }

    /// Asked of the file system every time rather than of the `URL`, which
    /// keeps the answer it was first given.
    private func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// A coordinator for Aujour's own reads and writes of this folder.
    ///
    /// Made on behalf of this presenter, which is half of what keeps Aujour's
    /// own writes from coming back to it as somebody else's — `aujourWrote` is
    /// the other half, and the half that actually settles it.
    var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: self)
    }

    // MARK: - What the system tells a presenter

    /// The folder itself changed — a file added or removed directly under it.
    func presentedItemDidChange() {
        announce.yield(.theFolder)
    }

    /// A file somewhere under the folder was written to.
    func presentedSubitemDidChange(at url: URL) {
        reportIfItHappenedWhileWatching(url)
    }

    /// A file appeared under the folder: another device's day, arriving.
    func presentedSubitemDidAppear(at url: URL) {
        reportIfItHappenedWhileWatching(url)
    }

    /// A file under the folder was renamed or moved — which, for an Entry's
    /// path, is a day appearing or disappearing.
    ///
    /// Either end can be the news, so the one that is not hidden is what this
    /// is about: a note dragged into a folder of its own arrives at a new
    /// path, and one deleted in Obsidian leaves its own for the vault's
    /// hidden `.trash`.
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        reportIfItHappenedWhileWatching(isHidden(newURL) ? oldURL : newURL)
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
        // Reported without asking the file when it last changed, alone among
        // these: a deletion is news that nothing about the file as it stands
        // can bear out. It is still there, with the dates it has always had,
        // and what is happening now is that it is about to stop being there.
        report(url)
    }

    /// Somebody is about to delete the Journal Root itself. Agreed to for the
    /// same reason, and reported for a better one: everything Aujour is
    /// showing came out of a folder that is about to stop existing.
    func accommodatePresentedItemDeletion(
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        completionHandler(nil)
        announce.yield(.theFolder)
    }

    /// Reports that somebody wrote a file — unless the file says nobody has,
    /// not since Aujour started presenting the folder.
    ///
    /// The system's account of *when* is the one thing it does not give: a
    /// write that finished a moment before this presenter registered is
    /// delivered, about a second later, in exactly the shape of one made just
    /// now. The file is what tells them apart, and it tells them apart
    /// squarely — a file whose attributes have not been touched since the
    /// moment presenting began is one that nothing has happened to since, so
    /// there is nothing about it to report.
    ///
    /// The attribute date and not the modification date, because that one can
    /// be written to: an app that saves a file with the date it had before
    /// would otherwise go unheard, where the date the system keeps of when the
    /// inode last changed cannot be backdated by anybody.
    ///
    /// A file the folder cannot answer for — one already gone, one iCloud has
    /// not sent down — is reported. Not knowing when something happened is not
    /// the same as knowing it did not.
    private func reportIfItHappenedWhileWatching(_ url: URL) {
        guard somethingHappenedWhileWatching(url) else { return }
        report(url)
    }

    /// Whether anything at all has happened to this file since Aujour started
    /// presenting the folder.
    private func somethingHappenedWhileWatching(_ url: URL) -> Bool {
        let lastTouched = try? url.resourceValues(forKeys: [.attributeModificationDateKey])
            .attributeModificationDate
        guard let lastTouched else { return true }
        return lastTouched >= presentingSince
    }

    /// Announces a change to one file — unless it is to a file that could not
    /// be part of the journal, which is most of what a folder in a vault does
    /// all day.
    ///
    /// Hidden files are none of Aujour's business, exactly as they are none of
    /// its business in a listing: `.obsidian/workspace.json` is rewritten
    /// every time somebody moves a pane, `.DS_Store` every time a folder is
    /// looked at, and — the one that matters here — a `.dat.nosync` beside an
    /// Entry is Aujour's *own* atomic write on its way to being renamed into
    /// place. Answering that would have every autosave come back as news.
    ///
    /// The exception is the same one a listing makes: the placeholder standing
    /// in for a file iCloud has not sent down is hidden, and a day arriving
    /// from another device is the very thing worth hearing about.
    private func report(_ url: URL) {
        guard !isHidden(url), !isAsAujourLeftIt(url) else { return }
        announce.yield(.file(url))
    }

    /// Whether anything between the Journal Root and this file is hidden.
    ///
    /// The whole path below the root, not just the name: a change to
    /// `.obsidian/plugins/daily-notes/data.json` is a change to a file with an
    /// ordinary name, under a folder that is somebody else's business.
    private func isHidden(_ url: URL) -> Bool {
        let root = presentedItemURL?.standardizedFileURL.pathComponents ?? []
        let components = url.standardizedFileURL.pathComponents.dropFirst(root.count)
        return components.contains { component in
            component.hasPrefix(".") && !isAnEvictionPlaceholder(component)
        }
    }

    /// Where iCloud leaves a marker for a file whose content is not on this
    /// device: hidden, beside where the file belongs, named after it.
    private func isAnEvictionPlaceholder(_ name: String) -> Bool {
        name.hasPrefix(".") && name.hasSuffix(".icloud")
    }
}

/// What a folder reported: the file it was about, or — where the system did
/// not say — the folder itself.
///
/// Carried so that a change can be told from another one. Nothing decides
/// what to *do* from this: an Entry is one path, and the editor over it asks
/// the folder rather than reading anything into which file was named.
enum JournalRootChange: Equatable, Sendable, CustomStringConvertible {
    case file(URL)
    case theFolder

    var description: String {
        switch self {
        case .file(let url): "a change to \(url.lastPathComponent)"
        case .theFolder: "a change to the folder itself"
        }
    }
}
