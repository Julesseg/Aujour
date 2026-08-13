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
/// Not here yet, and deliberately: file coordination, external-change
/// notification, version-based divergence handling, and *waiting* for iCloud
/// to bring a file down — this store asks for the download and refuses the
/// operation, rather than blocking on it. That is right while Aujour owns the
/// folder it writes to, and wrong the moment Obsidian is editing the same
/// file: the seam is where M2 adds all four, without the domain above
/// noticing.
struct FileJournalStore: JournalStore {
    /// The folder every path in this store is relative to.
    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func listFiles() async throws -> [String] {
        try checkTheRootIsThere()

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
                            of: url.deletingLastPathComponent().appending(path: evicted)
                        )
                    )
                }
                continue
            }

            if isDirectory { continue }
            paths.insert(relativePath(of: url))
        }

        if let failure = unreadable.failure {
            throw JournalRootError.readFailed(
                path: relativePath(of: failure.url),
                reason: failure.error.localizedDescription
            )
        }
        // Sorted only so that the same folder reads back the same way twice;
        // `JournalStore` promises no order, and callers sort by Journal Day.
        return paths.sorted()
    }

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
            return try Data(contentsOf: url)
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
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomically, so an autosave interrupted mid-write leaves the
            // previous Entry intact rather than half of two.
            try contents.write(to: url, options: .atomic)
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
            try FileManager.default.createDirectory(
                at: toURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: fromURL, to: toURL)
        } catch {
            throw JournalRootError.moveFailed(
                source: from.string,
                destination: to.string,
                reason: error.localizedDescription
            )
        }
    }

    // MARK: - The folder underneath

    private func url(for path: RelativePath) -> URL {
        path.components.reduce(root) { $0.appending(path: $1) }
    }

    private func relativePath(of url: URL) -> String {
        url.standardizedFileURL.pathComponents
            .dropFirst(root.pathComponents.count)
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
                    relativePath(of: ancestor)
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
