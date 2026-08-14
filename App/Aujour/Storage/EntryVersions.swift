import Foundation

/// The other versions of a file the system is holding on to: what iCloud is
/// left with when two devices wrote the same day and neither knew about the
/// other.
///
/// A seam because there is no way to make one on purpose. An unresolved
/// conflict version takes two devices, a sync and a moment of bad luck, and
/// none of that happens in a simulator or on a build machine — so the one
/// implementation over `NSFileVersion` is as thin as it can be made, and
/// everything decided about a divergence is tested against versions a test
/// hands over.
protocol EntryVersions: Sendable {
    /// The versions of the file at this URL that conflict with the one at its
    /// path and have not been settled yet.
    ///
    /// Empty for a file nobody else wrote, which is nearly every file nearly
    /// always — so this is asked before anything else is done, and answering
    /// it is most of what this ever does.
    func unresolved(at url: URL) -> [any EntryVersion]
}

/// One version of a file: when it was written, what it says, and a way to tell
/// the system it has been dealt with.
protocol EntryVersion: Sendable {
    /// When this version was last written, or `nil` where the system will not
    /// say — which is not the same as "long ago", and never makes a version
    /// the newest.
    var writtenAt: Date? { get }

    /// What this version says. Read rather than moved into place, because a
    /// parked version is written through the Journal Store like everything
    /// else Aujour puts in the folder — coordinated, and not reported back to
    /// Aujour as somebody else's change.
    func contents() throws -> Data

    /// Says this version has been taken care of, so that the system stops
    /// holding it as an open conflict.
    ///
    /// Said only once both versions are files in the folder. Said too early,
    /// a version would be released before it had been kept; not said at all,
    /// the same divergence comes back at every change in the folder and leaves
    /// a `_2`, a `_3`, and a journal full of copies.
    func settle()
}

/// The versions iCloud is holding — the only implementation the app ever runs.
struct ICloudVersions: EntryVersions {
    func unresolved(at url: URL) -> [any EntryVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map(ICloudVersion.init)
    }
}

/// One version, as iCloud has it: a file of its own, off in the version store,
/// with the modification date of the device that wrote it.
///
/// Unchecked because `NSFileVersion` is not `Sendable` and this is a value
/// wrapped around one. It is only ever touched from the parking that asked for
/// it, one version at a time.
private struct ICloudVersion: EntryVersion, @unchecked Sendable {
    let version: NSFileVersion

    var writtenAt: Date? { version.modificationDate }

    func contents() throws -> Data {
        var read: Result<Data, any Error>?
        var refused: NSError?
        // Coordinated like every other read of the folder: the version's own
        // file is one iCloud may still be writing.
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: version.url,
            options: [],
            error: &refused
        ) { url in
            read = Result { try Data(contentsOf: url) }
        }

        if let read { return try read.get() }
        throw refused ?? NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue)
    }

    func settle() {
        version.isResolved = true
    }
}
