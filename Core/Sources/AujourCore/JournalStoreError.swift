import Foundation

/// Why a Journal Store refused an operation.
///
/// These are the failures that belong to the seam itself rather than to any
/// one platform: the file is not there, something already is, the path is not
/// one a folder could hold. A real store also fails for reasons only it knows
/// — iCloud not signed in, a stale bookmark, a full disk — and throws its own
/// errors for those, which is why `JournalStore`'s operations are not typed to
/// this enum.
///
/// Some of these the domain acts on: a collision means park the incoming file
/// (ADR 0002), a missing file means the day is not journaled (ADR 0001). The
/// rest are a folder of files refusing a path that could not name one, and
/// nothing above the seam is expected to handle them — they are here so that a
/// path assembled wrongly fails where it was assembled, loudly, in the same
/// way against every store.
public enum JournalStoreError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Nothing is at this path, so there is nothing to read or move.
    case fileNotFound(String)

    /// A move's destination is occupied. Moves never overwrite: the caller
    /// decides what to do, which for a migration is to park the incoming file
    /// adjacently rather than lose either version.
    case fileAlreadyExists(String)

    /// Not a path relative to the Journal Root that a folder could hold: it
    /// is empty, absolute, has an empty component, or hops through `.`/`..`.
    case invalidPath(String)

    /// A folder is at this path — other files live under it — so no file can.
    case pathIsAFolder(String)

    /// A file is at this path, so nothing can live inside it.
    case pathIsNotAFolder(String)

    /// The file's bytes are not valid UTF-8, so it cannot be read as text.
    /// Entries are text; attachments are not, and are read as bytes.
    case contentIsNotText(String)

    /// Diagnostic rather than user-facing: unlike a rejected Path Template,
    /// none of these are a sentence about something the user just typed. The
    /// App layer decides what, if anything, to say about them.
    public var description: String {
        switch self {
        case .fileNotFound(let path):
            "No file at '\(path)'."
        case .fileAlreadyExists(let path):
            "A file is already at '\(path)'."
        case .invalidPath(let path):
            "'\(path)' is not a valid path relative to the Journal Root."
        case .pathIsAFolder(let path):
            "'\(path)' is a folder, not a file."
        case .pathIsNotAFolder(let path):
            "'\(path)' is a file, so nothing can live inside it."
        case .contentIsNotText(let path):
            "The contents of '\(path)' are not UTF-8 text."
        }
    }
}
