import Foundation

/// A real, empty folder on disk for the duration of one test, deleted after.
///
/// The file-backed store is only worth testing against an actual file system —
/// the in-memory fake already covers what the domain asks of a folder, and
/// what is left to prove here is that a disk answers the same way.
/// Runs on whatever actor called it, so a `@MainActor` test can hand it a
/// `@MainActor` body.
func withTemporaryFolder<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: (URL) async throws -> T
) async throws -> T {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "AujourTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    return try await body(folder)
}

extension URL {
    /// Writes `text` to a path relative to this folder, creating the folders
    /// along the way — how these tests seed a folder without going through the
    /// store under test.
    func seed(_ text: String, at relativePath: String) throws {
        let file = appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: file)
    }

    /// The same, for a file whose age matters: divergence is decided by which
    /// version was written last, so a test that is about that has to say when
    /// each of them was.
    func seed(_ text: String, at relativePath: String, writtenAt: Date) throws {
        try seed(text, at: relativePath)
        try FileManager.default.setAttributes(
            [.modificationDate: writtenAt],
            ofItemAtPath: appending(path: relativePath).path
        )
    }

    /// The same write, made the way another app makes it: coordinated, and on
    /// behalf of nobody Aujour is presenting the folder for.
    ///
    /// This is Obsidian saving the same daily note, or iCloud Drive putting
    /// another device's version down — and it is coordination, not the writing
    /// itself, that is how a file presenter comes to hear about either.
    func somebodyElseWrites(_ text: String, at relativePath: String) throws {
        let file = appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var written: (any Error)?
        var refused: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: file,
            options: .forReplacing,
            error: &refused
        ) { file in
            do {
                try Data(text.utf8).write(to: file, options: .atomic)
            } catch {
                written = error
            }
        }
        if let refused { throw refused }
        if let written { throw written }
    }

    /// The same, for a folder rather than a day: a month another device has
    /// started journaling into, arriving before any of its Entries do.
    func somebodyElseMakesAFolder(at relativePath: String) throws {
        var made: (any Error)?
        var refused: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: appending(path: relativePath, directoryHint: .isDirectory),
            options: .forReplacing,
            error: &refused
        ) { folder in
            do {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )
            } catch {
                made = error
            }
        }
        if let refused { throw refused }
        if let made { throw made }
    }

    /// The same, for a day another app removes — deleted in Obsidian, or
    /// dragged to the bin in the Files app.
    ///
    /// Coordinated for deleting, which is the option that asks a presenter to
    /// make way rather than telling it afterwards, and so the only one that is
    /// how a deletion actually reaches Aujour.
    func somebodyElseDeletes(at relativePath: String) throws {
        var removed: (any Error)?
        var refused: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: appending(path: relativePath),
            options: .forDeleting,
            error: &refused
        ) { file in
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                removed = error
            }
        }
        if let refused { throw refused }
        if let removed { throw removed }
    }
}
