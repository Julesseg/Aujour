import Foundation

/// Why the real folder behind the Journal Root refused, in words the user can
/// be shown.
///
/// `JournalStoreError` covers the refusals every Journal Store shares, and
/// says so diagnostically: they are paths that could not name a file, which
/// is a bug rather than a sentence anyone wants to read. These are the other
/// half — the ways a folder *on a device* fails, none of which the user
/// caused and all of which they have to be told about, because the
/// alternative to saying "iCloud has not sent this day down yet" is showing
/// an empty page where their words should be (ADR 0001: the files are the
/// journal, so a folder Aujour cannot reach is a journal it must not pretend
/// to have read).
enum JournalRootError: Error, Equatable, LocalizedError {
    /// The Journal Root is not there: iCloud Drive is signed out or still
    /// arriving, or the folder was moved or deleted from under the app.
    case journalRootUnavailable

    /// The folder the user pointed Aujour at cannot be reached: renamed,
    /// deleted, or in an iCloud Drive folder that has not arrived on this
    /// device. Never a reason to journal into Aujour's own folder instead —
    /// their Entries are in the vault, and a journal that quietly moved would
    /// look to them like a journal that emptied (ADR 0004).
    case chosenFolderUnavailable

    /// A folder was picked, but the right to reach it again could not be
    /// kept. Nothing changed: the journal is still where it was.
    case couldNotRememberFolder(String, reason: String)

    /// iCloud knows about this file but has not brought its content to this
    /// device yet. Reading it would hand back a placeholder, and writing it
    /// would replace a version of the day this device has never seen.
    case notDownloaded(String)

    case readFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case moveFailed(source: String, destination: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .journalRootUnavailable:
            "Aujour can't reach your journal folder."
        case .chosenFolderUnavailable:
            "Aujour can't reach the folder you chose."
        case .couldNotRememberFolder(let name, _):
            "Aujour couldn't keep access to \(name)."
        case .notDownloaded(let path):
            "iCloud hasn't finished downloading \(path)."
        case .readFailed(let path, _):
            "Aujour couldn't read \(path)."
        case .writeFailed(let path, _):
            "Aujour couldn't save \(path)."
        case .moveFailed(let source, _, _):
            "Aujour couldn't move \(source)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .journalRootUnavailable:
            "Check that you're signed in to iCloud and that iCloud Drive is on, then try again. Your entries are safe in the folder."
        case .chosenFolderUnavailable:
            "It may have been renamed, moved, or deleted — or it's in iCloud Drive and hasn't arrived on this device yet. Pick it again, or go back to Aujour's own folder. Your entries are still in the folder, wherever it is."
        case .couldNotRememberFolder:
            "Nothing has changed — your journal is still where it was. Try picking the folder again."
        case .notDownloaded:
            "Aujour has asked iCloud for it — this usually takes a moment. Nothing has been changed."
        case .readFailed, .writeFailed, .moveFailed:
            "Nothing has been changed. Try again in a moment; if it keeps happening, check that the folder is still where you left it."
        }
    }
}
