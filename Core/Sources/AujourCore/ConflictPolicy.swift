import Foundation

/// What to do when one Journal Day has been written twice.
///
/// It happens the way sharing a folder does: the iPad and the iPhone were both
/// written in while one of them was offline, and iCloud comes back holding two
/// versions of the same Entry and no opinion about them. Aujour has no opinion
/// about their *contents* either — merging somebody's journal by machine is
/// how a sentence they meant goes missing — so the only decisions are which
/// version the user finds at the day's own path, and where the others go.
///
/// - **The newest keeps the Entry path.** It is the likeliest to be what they
///   were last writing, and it is the version the calendar, the editor and
///   Obsidian's `[[links]]` all go on pointing at.
/// - **Every other version is parked beside it**, as `{filename}_1.md`, `_2`,
///   and so on to the first suffix the folder does not already hold. Adjacent
///   precisely so that it is noticed in Obsidian or in the Files app, and
///   never overwriting whatever is there — a `_1` from an earlier divergence,
///   or from a migration collision (ADR 0002), is somebody's words too.
///
/// Nothing is merged and nothing is discarded, which is the whole of it: every
/// version that goes in comes back out, at a path of its own.
///
/// Pure, and deliberately: divergence is the hardest thing in the app to
/// reproduce — it takes two devices, a sync and a moment of bad luck — so the
/// decision is arithmetic on dates and names, tested exhaustively here, and
/// the App layer is left with the folder work over versions only iCloud can
/// make.
public struct ConflictPolicy: Sendable {
    public init() {}

    /// One of the versions a divergence is between.
    ///
    /// The two are not alike, and the difference is what a caller has: the
    /// file at the Entry path is one it can read, and the rest are versions
    /// the system is holding on to, which it knows only by the order it was
    /// given them in.
    public enum Version: Hashable, Sendable, CustomStringConvertible {
        /// The version the Entry path holds right now.
        case theFileThere

        /// One of the other versions, by its place among those given.
        case another(Int)

        public var description: String {
            switch self {
            case .theFileThere: "the file at the Entry path"
            case .another(let index): "the version at index \(index)"
            }
        }
    }

    /// A version that lost the Entry path, and the Parked File it becomes.
    public struct Parked: Hashable, Sendable {
        public let version: Version

        /// Where it goes: beside the Entry, relative to the Journal Root.
        public let path: String

        public init(version: Version, path: String) {
            self.version = version
            self.path = path
        }
    }

    /// What is to happen to a day that was written twice: one version keeps
    /// the Entry path, and each of the others gets a Parked File of its own.
    public struct Resolution: Hashable, Sendable {
        public let keepsTheEntryPath: Version

        /// The rest, in the order they were given, with the file that was at
        /// the Entry path first if it is among them.
        public let parked: [Parked]
    }

    /// Decides a divergence: which version stays at the Entry path, and where
    /// the others are set aside.
    ///
    /// - Parameters:
    ///   - entryPath: the day's Entry path, relative to the Journal Root.
    ///   - whenTheFileThereWasWritten: the modification date of the file at
    ///     that path, or `nil` where the file system will not say.
    ///   - otherVersions: when each of the other versions was written, in
    ///     whatever order the caller holds them — that order is how the
    ///     resolution refers to them back.
    ///   - filesInTheFolder: everything the Journal Root holds, so that no
    ///     Parked File is named over a file that already exists. A listing
    ///     taken a moment ago is enough: this decides the *first* free name,
    ///     and a caller that finds one taken anyway asks again with it added.
    /// - Throws: `JournalStoreError.invalidPath` for a path no folder could
    ///   hold — the same refusal a Journal Store makes, said here because
    ///   this is where a name is derived from it.
    public func resolve(
        _ entryPath: String,
        writtenAt whenTheFileThereWasWritten: Date?,
        against otherVersions: [Date?],
        beside filesInTheFolder: Set<String>
    ) throws(JournalStoreError) -> Resolution {
        let keeps = Self.newest(
            theFileThere: whenTheFileThereWasWritten,
            against: otherVersions
        )

        // Each name is taken out of circulation as it is chosen, so that two
        // versions of one day are never sent to one path.
        var taken = filesInTheFolder
        var parked: [Parked] = []
        for version in Self.every(otherVersions.count) where version != keeps {
            let path = try parkedPath(for: entryPath, avoiding: taken)
            taken.insert(path)
            parked.append(Parked(version: version, path: path))
        }

        return Resolution(keepsTheEntryPath: keeps, parked: parked)
    }

    /// Where a version of this Entry is parked: the Entry's own name with the
    /// first free `_1`, `_2`, … suffix, in the folder the Entry is in.
    ///
    /// The suffix goes before the extension, so a parked Entry is still a
    /// markdown file — the user is meant to open it, read both versions side
    /// by side, and merge them by hand.
    public func parkedPath(
        for entryPath: String,
        avoiding taken: Set<String>
    ) throws(JournalStoreError) -> String {
        let path = try RelativePath(entryPath)

        // Terminates because each turn rules out one more path, and a folder
        // holds finitely many.
        var suffix = 1
        while true {
            let candidate = Self.path(path, suffixed: suffix)
            if !taken.contains(candidate) { return candidate }
            suffix += 1
        }
    }

    // MARK: - Which version that is

    /// The version written last — or, where nothing is newer than the file
    /// already at the Entry path, that file.
    ///
    /// A tie leaves the file where it is, deliberately: nothing is newer, so
    /// nothing has to move, and moving anyway would rewrite an Entry to say
    /// what it already says. A version the system will not date never wins;
    /// it is kept like every other, just not put in front of the user.
    private static func newest(theFileThere: Date?, against otherVersions: [Date?]) -> Version {
        var newest: Version = .theFileThere
        var writtenAt = theFileThere

        for (index, other) in otherVersions.enumerated() {
            guard let other else { continue }
            if let writtenAt, other <= writtenAt { continue }
            newest = .another(index)
            writtenAt = other
        }

        return newest
    }

    /// Every version a divergence is between, the file at the Entry path
    /// first — which is the order they are parked in.
    private static func every(_ otherVersions: Int) -> [Version] {
        [.theFileThere] + (0..<otherVersions).map(Version.another)
    }

    // MARK: - What a Parked File is called

    private static func path(_ path: RelativePath, suffixed suffix: Int) -> String {
        var components = path.components
        let name = components.removeLast()
        components.append(self.name(name, suffixed: suffix))
        return components.joined(separator: "/")
    }

    /// `2026-03-01.md` and 1 → `2026-03-01_1.md`.
    private static func name(_ name: String, suffixed suffix: Int) -> String {
        // The last dot, and not a leading one: `.gitignore` is a name with no
        // extension, and `_1` belongs after it rather than inside it.
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return "\(name)_\(suffix)"
        }
        return "\(name[..<dot])_\(suffix)\(name[dot...])"
    }
}
