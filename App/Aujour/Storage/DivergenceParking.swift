import Foundation
import AujourCore

/// A version of a day that was set aside beside its Entry, because two devices
/// wrote that day and only one version can be at its path.
///
/// It carries a name as well as a path because that is what the user is told:
/// what they will see the file called when they go looking for it in Obsidian
/// or in the Files app, which is the whole reason it was put beside the Entry.
struct ParkedFile: Hashable, Sendable, Identifiable {
    /// Where it is, relative to the Journal Root.
    let path: String

    /// The Journal Day it is a version of — which is the day whose screen has
    /// something to say about it, and no other.
    let day: JournalDay

    var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var id: String { path }
}

/// A day that was written twice, and the folder afterwards holding both
/// versions.
///
/// This is where the divergence half of vault coexistence actually happens.
/// `ConflictPolicy` decides it — the newest version keeps the Entry path, the
/// rest are parked beside it under the first free `_1`, `_2`, … suffix — and
/// this carries the decision out over the folder: reading each version, giving
/// each one a file of its own, and only then telling the system the conflict
/// has been dealt with.
///
/// The order is the whole safety argument, and it is: read everything, write
/// everything, settle last. A version that has not been read is never released,
/// a version that has not been parked is never written over, and if any of it
/// fails partway the conflict is still open — so the next change in the folder
/// tries again, over a folder that has lost nothing.
///
/// Everything it writes goes through the Journal Store, which means through
/// file coordination and out of what the folder reports back to Aujour as
/// somebody else's change. Parked Files land through `create`, which refuses
/// an occupied path rather than replacing it: the one thing a version being
/// set aside must never do is land on another one.
struct DivergenceParking {
    private let store: FileJournalStore
    private let versions: any EntryVersions
    private let policy = ConflictPolicy()

    /// - Parameters:
    ///   - store: the folder the Entry and its Parked Files live in.
    ///   - versions: what the system is holding besides the file at the
    ///     Entry's path. iCloud, unless a test is saying otherwise.
    init(store: FileJournalStore, versions: any EntryVersions = ICloudVersions()) {
        self.store = store
        self.versions = versions
    }

    /// Whether anything has diverged at this Entry's path.
    ///
    /// Asked first and on its own, because the answer is almost always no and
    /// the caller has work to do before the answer is yes — the words on
    /// screen belong in the file before the versions of that file are compared
    /// by their dates.
    func hasDiverged(_ entryPath: String) -> Bool {
        guard let url = try? url(for: entryPath) else { return false }
        return !versions.unresolved(at: url).isEmpty
    }

    /// Parks every version of this day but the newest, and answers the Parked
    /// Files it left behind — empty for a day nobody else wrote, which is the
    /// usual answer.
    ///
    /// - Parameters:
    ///   - entryPath: where the day's Entry lives, relative to the Journal
    ///     Root.
    ///   - day: which Journal Day that is. Carried rather than worked out,
    ///     because reading a path back is the Path Template's job and this is
    ///     not the place to keep a second answer to it — it travels with each
    ///     Parked File so that the day's own screen is where it is mentioned.
    @discardableResult
    func park(_ entryPath: String, of day: JournalDay) async throws -> [ParkedFile] {
        let url = try url(for: entryPath)
        let otherVersions = versions.unresolved(at: url)
        guard !otherVersions.isEmpty else { return [] }

        let filesInTheFolder = Set(try await store.listFiles())
        let resolution = try policy.resolve(
            entryPath,
            writtenAt: store.modificationDate(ofFileAt: entryPath),
            against: otherVersions.map(\.writtenAt),
            beside: filesInTheFolder
        )

        // Every name the resolution chose is out of circulation from the
        // start, so that a version having to take a different one never takes
        // the one meant for the version after it.
        var taken = filesInTheFolder.union(resolution.parked.map(\.path))
        var parkedFiles: [ParkedFile] = []
        for parked in resolution.parked {
            let words = try await contents(of: parked.version, among: otherVersions, at: entryPath)
            let path = try await park(words, at: parked.path, for: entryPath, avoiding: taken)
            taken.insert(path)
            parkedFiles.append(ParkedFile(path: path, day: day))
        }

        // Last of the writing, and only ever onto a path whose previous
        // contents are already a file of their own: the version that was here
        // is among the ones just parked.
        if resolution.keepsTheEntryPath != .theFileThere {
            let survivor = try await contents(
                of: resolution.keepsTheEntryPath,
                among: otherVersions,
                at: entryPath
            )
            try await store.write(survivor, at: entryPath)
        }

        for version in otherVersions { version.settle() }
        return parkedFiles
    }

    /// Where a Parked File actually is on this device, so that it can be
    /// shown to the user where it lies.
    ///
    /// The other half of the whole of what Aujour does with a Parked File:
    /// say it is there, and point at it. Reading the two versions against
    /// each other is the user's work in their own editor, because an opinion
    /// about their contents is exactly the opinion this app does not have
    /// (`CONTEXT.md`, Parked File).
    ///
    /// Here rather than on `ParkedFile` itself, for the reason the path is
    /// relative in the first place: where a folder is on a device is the
    /// store's answer, and a value that carried a URL around would be a
    /// second one going stale beside it.
    func whereItLies(_ file: ParkedFile) -> URL? {
        try? url(for: file.path)
    }

    /// Writes one version to a name of its own, taking the next free one if
    /// something has appeared at the chosen name since the folder was listed.
    ///
    /// The retry terminates: each turn proves one more path occupied and adds
    /// it to what the next name avoids, and a folder holds finitely many
    /// files.
    private func park(
        _ contents: Data,
        at chosenPath: String,
        for entryPath: String,
        avoiding taken: Set<String>
    ) async throws -> String {
        var taken = taken
        var path = chosenPath
        while true {
            do {
                try await store.create(contents, at: path)
                return path
            } catch let refusal as JournalStoreError {
                guard case .fileAlreadyExists = refusal else { throw refusal }
                taken.insert(path)
                path = try policy.parkedPath(for: entryPath, avoiding: taken)
            }
        }
    }

    private func contents(
        of version: ConflictPolicy.Version,
        among otherVersions: [any EntryVersion],
        at entryPath: String
    ) async throws -> Data {
        switch version {
        case .theFileThere: try await store.read(at: entryPath)
        case .another(let index): try otherVersions[index].contents()
        }
    }

    // MARK: - The file underneath

    /// Asked of the store rather than assembled here: where a relative path
    /// actually is on the device is the store's own answer, and two of them is
    /// one too many.
    ///
    /// The only reason a URL is needed at all is that the versions the system
    /// is holding are addressed by one. Everything else — reading the file,
    /// writing beside it, listing the folder — goes back through the seam.
    private func url(for entryPath: String) throws -> URL {
        try store.url(forFileAt: entryPath)
    }
}
