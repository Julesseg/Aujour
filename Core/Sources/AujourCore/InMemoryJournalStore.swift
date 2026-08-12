import Foundation

/// A Journal Store held in memory: the folder the domain's tests journal into.
///
/// This is the repo's primary testing seam. A test seeds the files a user's
/// folder would hold, drives the public API against them, and reads the folder
/// back — no temporary directories, no simulator, and the same behavior on
/// every platform `swift test` runs on.
///
/// It is a fake rather than a stub: the answers come from actually keeping the
/// files, so a listing reflects every write and move, content round-trips
/// byte-for-byte, and the refusals a real folder makes — reading what is not
/// there, moving onto something that is, putting a file where a folder is —
/// are made here too. A test that passes against this store is making a claim
/// about behavior over a folder, not about this class.
///
/// Two things a real folder has are deliberately missing, because the domain
/// does not decide them: modification dates (divergence is decided by the App
/// layer from file versions) and case-insensitive path matching (a property of
/// the volume, not of the journal).
///
/// It ships in the library rather than a test-only target so that the App
/// layer's own tests and SwiftUI previews can journal into it too.
public actor InMemoryJournalStore: JournalStore {
    private var files: FileTable

    /// A store holding these files, keyed by path relative to the Journal
    /// Root, with text content.
    ///
    /// A seed no folder could hold — an absolute path, a `..` hop, a file
    /// inside a file — is a mistake in the test rather than a condition to
    /// handle, and traps saying which path was impossible. Write binary
    /// content, such as an Attachment, with `write(_:at:)`.
    public init(_ files: [String: String] = [:]) {
        var table = FileTable()
        // Sorted so that a self-contradictory seed fails the same way every
        // run, whatever order the dictionary happens to hash into.
        for path in files.keys.sorted() {
            do {
                try table.write(Data(files[path]!.utf8), at: path)
            } catch {
                preconditionFailure("A folder could not hold '\(path)': \(error)")
            }
        }
        self.files = table
    }

    /// Every file in the store, sorted by path.
    ///
    /// Sorted only so that a failing test reads the same way twice; a real
    /// store makes no such promise, and `JournalStore` does not either.
    public func listFiles() -> [String] {
        files.paths
    }

    public func fileExists(at relativePath: String) throws(JournalStoreError) -> Bool {
        try files.containsFile(at: relativePath)
    }

    public func read(at relativePath: String) throws(JournalStoreError) -> Data {
        try files.bytes(at: relativePath)
    }

    public func write(_ contents: Data, at relativePath: String) throws(JournalStoreError) {
        try files.write(contents, at: relativePath)
    }

    public func move(
        from source: String,
        to destination: String
    ) throws(JournalStoreError) {
        try files.move(from: source, to: destination)
    }
}

/// The files themselves, as a value.
///
/// Split out from the actor because an actor cannot be asked questions while
/// it is still initializing, and seeding needs the same rules as writing —
/// and because "what a folder of files does" is a question with no
/// concurrency in it.
private struct FileTable {
    /// Files only. Folders are not stored: a folder exists exactly when some
    /// file is under it, which is also how a folder of files behaves — the
    /// empty folders left behind by a move are invisible to everything the
    /// domain asks.
    private var contents: [String: Data] = [:]

    var paths: [String] {
        contents.keys.sorted()
    }

    func containsFile(at path: String) throws(JournalStoreError) -> Bool {
        _ = try RelativePath.components(of: path)
        return contents[path] != nil
    }

    func bytes(at path: String) throws(JournalStoreError) -> Data {
        _ = try RelativePath.components(of: path)
        guard let data = contents[path] else {
            throw JournalStoreError.fileNotFound(path)
        }
        return data
    }

    mutating func write(_ data: Data, at path: String) throws(JournalStoreError) {
        try checkAFileCanLive(at: path)
        contents[path] = data
    }

    mutating func move(from source: String, to destination: String) throws(JournalStoreError) {
        guard try containsFile(at: source) else {
            throw JournalStoreError.fileNotFound(source)
        }
        // Checked before the destination, so that moving a file onto itself is
        // the no-op it is on a real folder rather than a collision with itself.
        guard source != destination else { return }

        try checkAFileCanLive(at: destination)
        guard contents[destination] == nil else {
            throw JournalStoreError.fileAlreadyExists(destination)
        }

        contents[destination] = contents.removeValue(forKey: source)
    }

    /// Whether this path is one a file could occupy: not a folder, and not
    /// inside a file. The two ways a real folder says no to a path that is
    /// otherwise well-formed.
    private func checkAFileCanLive(at path: String) throws(JournalStoreError) {
        let components = try RelativePath.components(of: path)

        guard !contents.keys.contains(where: { $0.hasPrefix(path + "/") }) else {
            throw JournalStoreError.pathIsAFolder(path)
        }

        var ancestor = ""
        for component in components.dropLast() {
            ancestor = ancestor.isEmpty ? component : "\(ancestor)/\(component)"
            guard contents[ancestor] == nil else {
                throw JournalStoreError.pathIsNotAFolder(ancestor)
            }
        }
    }
}
