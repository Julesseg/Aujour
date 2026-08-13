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
}
