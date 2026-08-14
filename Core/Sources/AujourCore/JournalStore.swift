import Foundation

/// The Journal Root, as everything above the file system sees it: a flat set
/// of files addressed by paths relative to the root, which can be enumerated,
/// read, written and moved.
///
/// This is the one seam between the domain and storage. Files are the only
/// source of truth (ADR 0001), so nearly every behavior in Aujour is a
/// question about this set — which days are journaled, what today's Entry
/// says, where a migration would move things — and stating it as a protocol
/// is what lets those behaviors be tested against `InMemoryJournalStore`
/// instead of a real folder.
///
/// Deliberately absent is everything that is a property of *a* file system
/// rather than of a folder of files: `URL`s, security-scoped bookmarks, file
/// coordination, iCloud download state, modification dates, case-folding
/// rules. Those belong to the App layer's implementation over the user's
/// chosen folder. What crosses the seam is paths and bytes.
///
/// There is no delete: nothing in v1 removes a file from the Journal Root.
/// Migration moves, divergence parks, and a journal the user wants smaller is
/// theirs to prune in Files or Obsidian — the folder outlives the app (ADR
/// 0001).
///
/// Operations are `async` because the real store waits: on file coordination,
/// on iCloud materializing a file, on I/O that must stay off the main thread.
/// They are untyped `throws` because a real store fails for reasons this
/// module cannot enumerate; `JournalStoreError` covers the failures every store
/// shares, and implementations throw it for those.
///
/// ## The path contract, which every implementation owes
///
/// Every path an operation takes is relative to the Journal Root and must be
/// one `RelativePath` accepts: not empty, not absolute, no empty component, no
/// `.` or `..` hop. Every operation — `fileExists(at:)` included — rejects
/// anything else with `JournalStoreError.invalidPath` rather than resolving it,
/// because a `..` hop resolved against a folder inside someone's Obsidian vault
/// reads or writes a file the user never pointed Aujour at. An implementation
/// gets this by making a `RelativePath` from each path it is handed, before it
/// touches storage; that is what `InMemoryJournalStore` does, and the guarantee
/// belongs to the seam rather than to the one store that cannot reach a disk.
public protocol JournalStore: Sendable {
    /// Every file anywhere under the Journal Root, as paths relative to it.
    ///
    /// Folders are not listed — only the files in them. This is the whole
    /// folder, not just the Entries: which of these paths is an Entry is a
    /// question for the current Path Template (ADR 0002), and asking it here
    /// would put the rule in two places.
    ///
    /// The order is unspecified. Callers that care sort by Journal Day once
    /// they have matched paths against the template, which is the order the
    /// domain actually means.
    func listFiles() async throws -> [String]

    /// Whether a file is at this path — for a Journal Day's Entry path, the
    /// entire meaning of "that day is journaled" (ADR 0001).
    ///
    /// False for a folder: a folder is not a file.
    func fileExists(at relativePath: String) async throws -> Bool

    /// The bytes of the file at this path.
    ///
    /// Throws `JournalStoreError.fileNotFound` when nothing is there — a
    /// missing Entry is a day not yet written, which callers distinguish with
    /// `fileExists(at:)` rather than by reading and hoping.
    func read(at relativePath: String) async throws -> Data

    /// Writes bytes to this path, replacing whatever was there and creating
    /// any folders the path names along the way.
    ///
    /// Replacing is what autosave needs: the Entry being edited is written
    /// over and over, and the last write is the truth. Moves are the
    /// operation that refuses to clobber.
    func write(_ contents: Data, at relativePath: String) async throws

    /// Writes bytes to a path nothing occupies, creating any folders the path
    /// names along the way — and refusing, rather than replacing, if something
    /// is already there.
    ///
    /// Throws `JournalStoreError.fileAlreadyExists` for an occupied path. This
    /// is what a Parked File is written by: parking exists to keep a version
    /// nobody has merged, and a parked version written over a `_1` left by an
    /// earlier divergence would lose exactly the words it was setting aside.
    /// So the refusal is the seam's, like a move's, rather than a check each
    /// caller remembers to make first — a check made first is a check with a
    /// gap after it.
    ///
    /// Only new files, so there is nothing here for a half-finished write to
    /// damage; `write(_:at:)` is what replaces, and what an autosave uses.
    func create(_ contents: Data, at relativePath: String) async throws

    /// Moves the file at `source` to `destination`, creating any folders the
    /// destination names.
    ///
    /// Throws `JournalStoreError.fileAlreadyExists` if the destination is
    /// occupied: a migration collision and a parked divergence both hinge on
    /// nothing ever being overwritten (ADR 0002), so the refusal is part of
    /// the seam rather than a check each caller remembers to make. Moving a
    /// file to where it already is does nothing.
    func move(from source: String, to destination: String) async throws
}

extension JournalStore {
    /// The file at this path as text. Entries are UTF-8 markdown, which is
    /// what Obsidian writes and what the editor edits.
    ///
    /// Throws `JournalStoreError.contentIsNotText` for bytes that are not
    /// valid UTF-8 — a JPEG someone dropped in the folder under an `.md`
    /// name, say. Replacing them with what UTF-8 decoding salvages would put
    /// mojibake in front of the user as if it were their own words.
    public func readText(at relativePath: String) async throws -> String {
        let contents = try await read(at: relativePath)
        guard let text = String(data: contents, encoding: .utf8) else {
            throw JournalStoreError.contentIsNotText(relativePath)
        }
        return text
    }

    /// Writes text to this path as UTF-8, with the same replace-and-create
    /// semantics as `write(_:at:)`.
    public func writeText(_ text: String, at relativePath: String) async throws {
        try await write(Data(text.utf8), at: relativePath)
    }

    /// Writes text to a path nothing occupies, as UTF-8 — the refusing form,
    /// with the same semantics as `create(_:at:)`.
    public func createText(_ text: String, at relativePath: String) async throws {
        try await create(Data(text.utf8), at: relativePath)
    }
}
