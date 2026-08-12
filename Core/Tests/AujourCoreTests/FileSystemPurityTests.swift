import Foundation
import Testing

// ADR 0001 makes the files the only truth, and ADR 0003 keeps app
// configuration out of the Journal Root — the folder holds Entries,
// Attachments and Parked Files and nothing else. Both hold structurally
// because AujourCore cannot touch a file at all: every file-system operation
// lives behind a seam the App layer implements. That guarantee is an absence,
// which no behavioural test can observe, so this is what keeps it true.
@Suite("AujourCore touches no files")
struct FileSystemPurityTests {
    @Test("no Core source reaches for the file system")
    func coreSourcesHaveNoFileSystemAccess() throws {
        let fileSystemAPIs = [
            "FileManager",
            "FileHandle",
            "fileURLWithPath",
            "contentsOfFile",
            "contentsOfDirectory",
            "InputStream",
            "OutputStream",
        ]

        let sources = try swiftSources(in: coreSourcesDirectory)
        #expect(!sources.isEmpty, "found no Core sources to check at \(coreSourcesDirectory.path)")

        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            for api in fileSystemAPIs {
                #expect(
                    !text.contains(api),
                    "\(source.lastPathComponent) reaches for \(api); file access belongs behind a seam the App layer implements"
                )
            }
        }
    }

    /// Every `.swift` file under a directory, however deeply nested — so a
    /// source added later is covered without anyone remembering to list it.
    private func swiftSources(in directory: URL) throws -> [URL] {
        try FileManager.default
            .subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .map { directory.appendingPathComponent($0) }
    }

    /// `Core/Sources/AujourCore`, reached from this file's own location.
    private var coreSourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)  // Core/Tests/AujourCoreTests/<this file>
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AujourCore")
    }
}
