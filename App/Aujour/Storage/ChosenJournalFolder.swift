import Foundation

/// The folder the user pointed Aujour at with the Files picker, and the right
/// to go on reaching it after the app is relaunched.
///
/// A folder outside Aujour's own container cannot be reached by path. The
/// picker hands over a URL the app may use only while it says it is using it,
/// and the only thing that outlives the launch is a *security-scoped
/// bookmark*: bytes that still name the folder after it has been renamed or
/// moved, and that carry the permission along with the name.
///
/// That makes the chosen folder per-device by nature — a bookmark means
/// nothing on another device — which is why it is kept in local storage and
/// never travels through the synced settings seam (ADR 0003).
///
/// A class rather than a value because the *access* is something held: the
/// right to reach a folder is taken when the bookmark is resolved and given
/// back when the user picks another folder or goes back to Aujour's own, so
/// something has to remember which folder is currently being held. It reaches
/// the world through the two closures that keep the bookmark between
/// launches, so a test relaunches the app by making a second one over the
/// same storage.
///
/// Unchecked because that one piece of state is behind a lock; everything
/// else here is a closure the caller supplied.
final class ChosenJournalFolder: @unchecked Sendable {
    private let storedBookmark: @Sendable () -> Data?
    private let rememberBookmark: @Sendable (Data?) -> Void

    private let lock = NSLock()
    /// The folder the right to reach is currently held on, if one is.
    private var reaching: URL?

    init(
        storedBookmark: @escaping @Sendable () -> Data?,
        rememberBookmark: @escaping @Sendable (Data?) -> Void
    ) {
        self.storedBookmark = storedBookmark
        self.rememberBookmark = rememberBookmark
    }

    /// Whether the user has pointed Aujour at a folder of their own.
    ///
    /// Asked of what is remembered rather than of the folder, so it is still
    /// true when the chosen folder is the reason nothing could be opened —
    /// which is exactly when the way back to Aujour's own folder has to be
    /// offered.
    var hasBeenChosen: Bool { storedBookmark() != nil }

    /// The chosen folder, ready to be journaled into — or `nil` when the user
    /// has never chosen one, which is everybody until they do.
    ///
    /// A bookmark that will not resolve is a failure and never a `nil`. The
    /// folder has been renamed away, deleted, or is in an iCloud Drive that
    /// has not arrived on this device; journaling into Aujour's own folder
    /// instead would split the journal in two exactly the way ADR 0004
    /// refuses to, and without the user being told.
    func resolve() throws -> URL? {
        guard let bookmark = storedBookmark() else { return nil }

        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: bookmark,
                bookmarkDataIsStale: &isStale
            )
        else {
            stopReaching()
            throw JournalRootError.chosenFolderUnavailable
        }

        // Before asking whether the folder is there: without the right to
        // reach it, a folder that is there answers as though it is not.
        beginReaching(url)

        guard isFolder(url) else {
            stopReaching()
            throw JournalRootError.chosenFolderUnavailable
        }

        // A stale bookmark still resolves — it is the warning that it may not
        // next time, once enough has moved — so it is rewritten while it can
        // still be written from.
        if isStale, let refreshed = try? url.bookmarkData() {
            rememberBookmark(refreshed)
        }
        return url.standardizedFileURL
    }

    /// Points the Journal at a folder the user just picked in the Files app,
    /// and remembers it for every launch after this one.
    ///
    /// Nothing is written to the folder and nothing is copied into it: the
    /// journal *becomes* whatever Entries are already there, which for a
    /// folder inside an Obsidian vault is the point of picking it.
    func choose(_ folder: URL) throws {
        // The picker's URL is one the app may reach only while it says it is
        // reaching it — and making the bookmark counts as reaching it.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        guard isFolder(folder) else {
            throw JournalRootError.chosenFolderUnavailable
        }

        let bookmark: Data
        do {
            bookmark = try folder.bookmarkData()
        } catch {
            throw JournalRootError.couldNotRememberFolder(
                folder.lastPathComponent,
                reason: error.localizedDescription
            )
        }
        rememberBookmark(bookmark)
        // Given back here and taken again by `resolve()`, which is the one
        // place the right to reach the journal is held — and holds it on a
        // URL that outlives this one.
        stopReaching()
    }

    /// Back to the folder Aujour finds for itself.
    ///
    /// The chosen folder is only forgotten, never touched: the Entries
    /// written into it stay exactly where the user can still find them, which
    /// is the whole promise (ADR 0001).
    func forget() {
        rememberBookmark(nil)
        stopReaching()
    }

    // MARK: - Holding the right to reach a folder

    private func beginReaching(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }

        guard reaching != url else { return }
        reaching?.stopAccessingSecurityScopedResource()
        // The answer is deliberately unread: it is `false` for a folder that
        // needs no permission at all — the app's own container, or the
        // temporary folder a test journals into — and that is not a refusal.
        _ = url.startAccessingSecurityScopedResource()
        reaching = url
    }

    private func stopReaching() {
        lock.lock()
        defer { lock.unlock() }

        reaching?.stopAccessingSecurityScopedResource()
        reaching = nil
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

extension ChosenJournalFolder {
    static let bookmarkKey = "JournalRootBookmark"

    /// The folder this device's journal was pointed at, kept in local storage
    /// — per-device by nature, so never through the synced settings seam
    /// (ADR 0003).
    ///
    /// - Parameter key: where the bookmark is kept. Spelled out only by the
    ///   UI suite, which gives each of its journals a key of its own so that
    ///   one test's chosen folder is never the next test's.
    static func stored(key: String = ChosenJournalFolder.bookmarkKey) -> ChosenJournalFolder {
        ChosenJournalFolder(
            storedBookmark: { UserDefaults.standard.data(forKey: key) },
            rememberBookmark: { bookmark in
                if let bookmark {
                    UserDefaults.standard.set(bookmark, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        )
    }

    /// A folder nobody has chosen and nothing remembers — for previews, and
    /// for anything that journals somewhere of its own choosing.
    static var unchosen: ChosenJournalFolder {
        ChosenJournalFolder(storedBookmark: { nil }, rememberBookmark: { _ in })
    }
}
