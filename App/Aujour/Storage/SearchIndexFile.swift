import CryptoKit
import Foundation
import AujourCore

/// The Search Index between launches: one file in the app's caches folder.
///
/// The caches folder and nowhere else, because that is what this is — the
/// system may reclaim it whenever it likes, and the app is none the worse for
/// it (ADR 0001). Everything in it is a copy of words already in the user's
/// own files, so what losing it costs is the read of the folder that builds
/// another. Deliberately not in Documents, where it would show up in the Files
/// app as something Aujour had left in somebody's vault, and deliberately not
/// in the Journal Root, which holds Entries, Attachments and Parked Files and
/// nothing of Aujour's own (ADR 0003).
///
/// One file per Journal Root. A journal moved into an Obsidian vault is a
/// different journal with different days in it, and a search over the folder
/// just left would put another journal's words on screen for as long as the
/// scan took.
struct SearchIndexFile: SearchIndexCache {
    let file: URL

    /// - Parameters:
    ///   - root: the folder this index is over — what the file is named after,
    ///     so that two journals never share one.
    ///   - caches: where the file goes. The app's own caches folder, unless a
    ///     test says otherwise.
    init(forJournalAt root: URL, in caches: URL = .cachesDirectory) {
        // Named after a digest of the path rather than the path itself: a
        // Journal Root is a path of somebody's own making, and one with a
        // slash, a colon or two hundred characters in it is not a file name.
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        file =
            caches
            .appending(path: "SearchIndex", directoryHint: .isDirectory)
            .appending(path: "\(digest).json")
    }

    func load() async -> Data? {
        try? Data(contentsOf: file)
    }

    func save(_ index: Data) async {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomically, so that a write cut short by the app going away leaves
        // the last whole index rather than half of one. A half-read index is
        // no index at all, which costs a scan — but only if it is ever read as
        // one, and this is what makes sure it is not.
        try? index.write(to: file, options: .atomic)
    }
}
