import Foundation
import AujourCore

/// A Journal Store over a folder that is actually on the device: the one the
/// user sees in the Files app, and the only place their journal exists
/// (ADR 0001).
///
/// Its whole job is to answer what `InMemoryJournalStore` answers, from a disk
/// instead of a dictionary — the fake is what every domain test in Core is
/// written against, so the two are only interchangeable if a folder replies
/// the same way. Where the seam already has an answer, this store gives that
/// same one: a folder is not a file, so reading one is reading nothing; a move
/// never overwrites; a path no folder could hold is refused before anything is
/// touched.
///
/// What it adds is what only a real folder can go wrong at, and each of those
/// is a `JournalRootError` with a sentence for the user rather than a
/// silence: the folder can be gone, and iCloud may not have brought a file's
/// content down yet.
///
/// Every file it touches, it touches through file coordination: the folder is
/// shared with Obsidian and with iCloud Drive, and two writers meeting in one
/// file is how a day ends up half of each. What that coordination is *for* on
/// the other side — hearing about somebody else's write — belongs to
/// ``CoordinatedJournalRoot``, which is also what a store is given so that
/// Aujour's own writes are not reported back to Aujour as news.
///
/// Not here yet, and deliberately: *waiting* for iCloud to bring a file down
/// — this store asks for the download and refuses the operation, rather than
/// blocking on it. The other thing only iCloud can produce, two versions of
/// one day, is ``DivergenceParking``'s, which works over this store rather
/// than inside it: a folder of files answers what is in it, and which of two
/// versions of a day belongs at its path is a question about the journal.
struct FileJournalStore: JournalStore {
    /// The folder every path in this store is relative to.
    let root: URL

    /// The folder as Aujour presents it, if it is being presented — what
    /// every coordinator here is made on behalf of.
    ///
    /// Optional because coordination is a property of the folder and watching
    /// it is not: a store made for one question, and the fakes' own tests,
    /// coordinate with nobody to be left out of.
    private let presenter: CoordinatedJournalRoot?

    init(root: URL, coordinatedBy presenter: CoordinatedJournalRoot? = nil) {
        self.root = root.standardizedFileURL
        self.presenter = presenter
    }

    /// A fresh coordinator per operation, as the class is meant to be used —
    /// and on behalf of Aujour's presenter, which is part of what keeps this
    /// store's own writes from coming back to the app as changes somebody else
    /// made. The rest of that is `aujourWrote`, said as each write lands.
    private var coordinator: NSFileCoordinator {
        presenter?.coordinator ?? NSFileCoordinator(filePresenter: nil)
    }

    func listFiles() async throws -> [String] {
        try checkTheRootIsThere()

        // Coordinated, so that the walk happens between other apps' writes
        // rather than during one: this listing is the calendar, and a vault
        // mid-sync is exactly when it would otherwise be read short.
        //
        // Metadata only — a listing asks which files are there and never what
        // is in them, and pulling a year of another device's Entries down from
        // iCloud to answer that would be a download the user did not ask for.
        return try coordinatedRead(of: root, options: .immediatelyAvailableMetadataOnly) { root in
            try self.filesInFolder(at: root)
        }
    }

    /// Every file under a folder, as paths relative to it.
    ///
    /// Takes the folder rather than reading `root`, because coordination hands
    /// back the URL the read is to be made through, and that is the one the
    /// paths have to come out relative to.
    private func filesInFolder(at root: URL) throws -> [String] {
        // A folder that could not be read all the way through gives a *short*
        // listing, which is the same shape as an answer and a different fact:
        // it would show as days the user never journaled. So the first subtree
        // that refuses stops the walk and becomes the error.
        let unreadable = UnreadableFolder()
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: { url, error in
                    unreadable.record(url: url, error: error)
                    return false
                }
            )
        else {
            throw JournalRootError.journalRootUnavailable
        }

        // A set because a file and the placeholder standing in for it can
        // briefly both be there while iCloud is bringing it down, and they are
        // one file.
        var paths: Set<String> = []
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            let isDirectory =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            guard !name.hasPrefix(".") else {
                // A hidden *folder* is somebody else's business — `.obsidian`
                // holds a vault's configuration, `.trash` its deletions — and
                // nothing under it is the user's journal.
                if isDirectory {
                    enumerator.skipDescendants()
                } else if let evicted = Self.fileName(forEvictionPlaceholder: name) {
                    // A day iCloud has not sent down is still a day the user
                    // journaled; leaving it out would put a hole in their
                    // calendar that the file system does not have.
                    paths.insert(
                        relativePath(
                            of: url.deletingLastPathComponent().appending(path: evicted),
                            under: root
                        )
                    )
                }
                continue
            }

            if isDirectory { continue }
            paths.insert(relativePath(of: url, under: root))
        }

        if let failure = unreadable.failure {
            throw JournalRootError.readFailed(
                path: relativePath(of: failure.url, under: root),
                reason: failure.error.localizedDescription
            )
        }
        // Sorted only so that the same folder reads back the same way twice;
        // `JournalStore` promises no order, and callers sort by Journal Day.
        return paths.sorted()
    }

    /// Uncoordinated, alone among the operations here, and deliberately: this
    /// reads no bytes, so there is no half-written file for it to catch. What
    /// it would buy is waiting — for another app's save, or for iCloud — to
    /// answer a question the calendar asks of every day of a month, and whose
    /// answer the presenter reports the moment it changes anyway.
    func fileExists(at relativePath: String) async throws -> Bool {
        let path = try RelativePath(relativePath)
        try checkTheRootIsThere()

        let url = url(for: path)
        return isRegularFile(at: url) || isEvicted(at: url)
    }

    func read(at relativePath: String) async throws -> Data {
        let path = try RelativePath(relativePath)
        try checkTheRootIsThere()

        let url = url(for: path)
        try askICloudFor(url, at: path)
        guard isRegularFile(at: url) else {
            throw JournalStoreError.fileNotFound(path.string)
        }

        do {
            // Behind whatever write is in flight: an Entry read while Obsidian
            // is saving it is a day that is half of one version and half of
            // another, and the user reads it as words they never wrote.
            return try coordinatedRead(of: url) { try Data(contentsOf: $0) }
        } catch {
            throw JournalRootError.readFailed(
                path: path.string,
                reason: error.localizedDescription
            )
        }
    }

    func write(_ contents: Data, at relativePath: String) async throws {
        let path = try RelativePath(relativePath)
        try checkTheRootIsThere()

        let url = url(for: path)
        try checkAFileCanLive(at: path)
        // Replacing a file whose content this device has never seen is how a
        // day gets lost without anyone noticing, so it waits for the download
        // instead.
        try askICloudFor(url, at: path)

        do {
            // Coordinated for replacing, which is what an autosave is: the
            // other side is told the file is about to change and stops reading
            // it, instead of finding it changed underneath.
            try coordinatedWrite(of: url, options: .forReplacing) { writingTo in
                try FileManager.default.createDirectory(
                    at: writingTo.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                // Atomically, so an autosave interrupted mid-write leaves the
                // previous Entry intact rather than half of two.
                try contents.write(to: writingTo, options: .atomic)
                // Said from inside the access, so that it is said before the
                // folder can report the write — otherwise Aujour's own
                // autosave races its way back to Aujour as news.
                presenter?.aujourWrote(url)
            }
        } catch {
            throw JournalRootError.writeFailed(
                path: path.string,
                reason: error.localizedDescription
            )
        }
    }

    func create(_ contents: Data, at relativePath: String) async throws {
        let path = try RelativePath(relativePath)
        try checkTheRootIsThere()

        let url = url(for: path)
        try checkAFileCanLive(at: path)
        // Asked before the write as well as during it, because the two say
        // different things: a file iCloud is holding but has not sent down is
        // not there to be seen by an exclusive write, and creating over it
        // would lose a version this device has never read.
        guard !isRegularFile(at: url), !isEvicted(at: url) else {
            throw JournalStoreError.fileAlreadyExists(path.string)
        }

        do {
            try coordinatedWrite(of: url) { writingTo in
                try FileManager.default.createDirectory(
                    at: writingTo.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                do {
                    // Exclusively rather than atomically, which is the trade
                    // this operation exists to make: the file is a new one, so
                    // there is nothing a half-finished write could damage,
                    // while replacing one would lose a version outright. The
                    // check above is a question, and this is the answer the
                    // file system itself gives — with no gap in between for
                    // another device's file to arrive in.
                    try contents.write(to: writingTo, options: .withoutOverwriting)
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    throw JournalStoreError.fileAlreadyExists(path.string)
                }
                presenter?.aujourWrote(url)
            }
        } catch let refusal as JournalStoreError {
            // The seam's own answer, which the caller acts on: parking asks
            // for another name and tries again.
            throw refusal
        } catch {
            throw JournalRootError.writeFailed(
                path: path.string,
                reason: error.localizedDescription
            )
        }
    }

    func move(from source: String, to destination: String) async throws {
        // The source first, so a call with two unusable paths says so about
        // the one the caller is asking about a file at.
        let from = try RelativePath(source)
        let to = try RelativePath(destination)
        try checkTheRootIsThere()

        let fromURL = url(for: from)
        guard isRegularFile(at: fromURL) || isEvicted(at: fromURL) else {
            throw JournalStoreError.fileNotFound(from.string)
        }
        // Checked before anything about the destination, so that moving a file
        // onto itself is the no-op it is on a real folder rather than a
        // collision with itself — or, for a file iCloud has not sent down, a
        // wait for a download that the move would not have needed.
        guard from != to else { return }
        try askICloudFor(fromURL, at: from)

        let toURL = url(for: to)
        try checkAFileCanLive(at: to)
        guard !isRegularFile(at: toURL), !isEvicted(at: toURL) else {
            throw JournalStoreError.fileAlreadyExists(to.string)
        }

        do {
            // Both ends held at once, which is what a move is: the file leaves
            // one path and arrives at another, and no other app may be reading
            // either of them in between.
            try coordinatedMove(from: fromURL, to: toURL) { movingFrom, movingTo in
                try FileManager.default.createDirectory(
                    at: movingTo.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: movingFrom, to: movingTo)
                // The file at its new path is Aujour's own doing, the same way
                // a write is. The path it left is news in its own right —
                // something that was there is not any more — so that end is
                // left to be reported.
                presenter?.aujourWrote(toURL)
            }
        } catch {
            throw JournalRootError.moveFailed(
                source: from.string,
                destination: to.string,
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - Taking turns with the other apps in the folder

    // Three shapes of the same thing: ask for the access, do the work on the
    // URL that comes back rather than on the one that went in, and end up
    // either with what the work returned or with one error saying why it never
    // happened. The callers wrap that error in the `JournalRootError` for what
    // they were doing, so file coordination adds no vocabulary of its own to
    // the seam.

    private func coordinatedRead<T>(
        of url: URL,
        options: NSFileCoordinator.ReadingOptions = [],
        _ read: @escaping (URL) throws -> T
    ) throws -> T {
        var outcome: Result<T, any Error>?
        var refused: NSError?
        coordinator.coordinate(readingItemAt: url, options: options, error: &refused) { url in
            outcome = Result { try read(url) }
        }
        return try whatHappened(outcome, refused, .fileReadUnknown)
    }

    private func coordinatedWrite(
        of url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        _ write: @escaping (URL) throws -> Void
    ) throws {
        var outcome: Result<Void, any Error>?
        var refused: NSError?
        coordinator.coordinate(writingItemAt: url, options: options, error: &refused) { url in
            outcome = Result { try write(url) }
        }
        try whatHappened(outcome, refused, .fileWriteUnknown)
    }

    private func coordinatedMove(
        from source: URL,
        to destination: URL,
        _ move: @escaping (URL, URL) throws -> Void
    ) throws {
        var outcome: Result<Void, any Error>?
        var refused: NSError?
        // A fresh coordinator, held onto: a move has to be announced to the
        // other presenters, and that is a message to the same coordinator that
        // arranged it.
        let coordinator = self.coordinator
        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            writingItemAt: destination,
            options: .forReplacing,
            error: &refused
        ) { movingFrom, movingTo in
            outcome = Result {
                try move(movingFrom, movingTo)
                // Inside the block, which is the only place it may be said —
                // saying it afterwards raises, and an `NSException` in Swift
                // is the app gone. And only once the file has actually moved:
                // this is what tells everything else presenting the folder
                // that the file at one path is the file now at the other,
                // rather than one deleted and one appeared.
                //
                // With the paths that went in rather than the ones the
                // coordinator handed back, which is the pair it knows the move
                // by.
                coordinator.item(at: source, didMoveTo: destination)
            }
        }
        try whatHappened(outcome, refused, .fileWriteUnknown)
    }

    /// What the work returned, or why it never ran: the coordinator's refusal
    /// if it gave one, and otherwise the bare fact that it did not run — which
    /// is not supposed to be possible, and is still not somewhere to crash
    /// somebody's journal.
    @discardableResult
    private func whatHappened<T>(
        _ outcome: Result<T, any Error>?,
        _ refused: NSError?,
        _ otherwise: CocoaError.Code
    ) throws -> T {
        if let outcome { return try outcome.get() }
        if let refused { throw refused }
        throw CocoaError(otherwise)
    }

    // MARK: - The folder underneath

    private func url(for path: RelativePath) -> URL {
        path.components.reduce(root) { $0.appending(path: $1) }
    }

    private func relativePath(of url: URL, under base: URL) -> String {
        url.standardizedFileURL.pathComponents
            .dropFirst(base.standardizedFileURL.pathComponents.count)
            .joined(separator: "/")
    }

    /// A Journal Root that is not there is the difference between "you have
    /// not written anything" and "your journal is somewhere this app cannot
    /// currently see" — and only one of those is safe to show as an empty
    /// calendar, so every operation asks first.
    private func checkTheRootIsThere() throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw JournalRootError.journalRootUnavailable
        }
    }

    private func isRegularFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// The two ways a real folder refuses a path that is otherwise well-formed:
    /// a folder is already there, or the path goes through a file.
    private func checkAFileCanLive(at path: RelativePath) throws {
        var isDirectory: ObjCBool = false
        let url = url(for: path)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            throw JournalStoreError.pathIsAFolder(path.string)
        }

        var ancestor = root
        for component in path.components.dropLast() {
            ancestor = ancestor.appending(path: component)
            if isRegularFile(at: ancestor) {
                throw JournalStoreError.pathIsNotAFolder(
                    relativePath(of: ancestor, under: root)
                )
            }
        }
    }

    // MARK: - Files iCloud has not sent down

    /// Where iCloud leaves a marker for a file whose content is not on this
    /// device: hidden, beside where the file belongs, named after it.
    private static func evictionPlaceholderName(for fileName: String) -> String {
        ".\(fileName).icloud"
    }

    /// The file a hidden name is standing in for, or `nil` if it is standing
    /// in for nothing — an ordinary hidden file.
    private static func fileName(forEvictionPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let fileName = String(name.dropFirst().dropLast(".icloud".count))
        return fileName.isEmpty ? nil : fileName
    }

    private func evictionPlaceholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appending(path: Self.evictionPlaceholderName(for: url.lastPathComponent))
    }

    /// Whether the file at this URL exists in iCloud but not here: either as a
    /// placeholder standing in for it, or as a real name whose content has
    /// been evicted to make room.
    private func isEvicted(at url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: evictionPlaceholderURL(for: url).path) {
            return true
        }
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return status == .notDownloaded
    }

    /// Asks iCloud to bring a file down, and refuses the operation until it
    /// has. The request is what makes the refusal temporary — without it the
    /// file would stay evicted and the error would be a dead end.
    private func askICloudFor(_ url: URL, at path: RelativePath) throws {
        guard isEvicted(at: url) else { return }

        let placeholder = evictionPlaceholderURL(for: url)
        let toDownload =
            FileManager.default.fileExists(atPath: placeholder.path) ? placeholder : url
        try? FileManager.default.startDownloadingUbiquitousItem(at: toDownload)

        throw JournalRootError.notDownloaded(path.string)
    }
}

/// The first subtree a folder walk could not read, kept so the walk can end
/// as an error instead of a short answer.
///
/// A reference because `FileManager`'s error handler is a closure the
/// enumerator holds; unchecked because the enumeration it belongs to runs on
/// one task, start to finish.
private final class UnreadableFolder: @unchecked Sendable {
    private(set) var failure: (url: URL, error: any Error)?

    func record(url: URL, error: any Error) {
        guard failure == nil else { return }
        failure = (url, error)
    }
}
