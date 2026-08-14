import Foundation
import Testing
import AujourCore
@testable import Aujour

// The claims here are the ones `InMemoryJournalStoreTests` makes about the
// fake, re-asked of a real folder: the two stores are only interchangeable if
// a disk answers them the same way, and every domain test in Core is written
// against the fake on the strength of that.
@Suite("File Journal Store")
struct FileJournalStoreTests {
    @Test("a listing shows the files in the folder, and their content round-trips")
    func seededFilesAreListedAndReadable() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try root.seed("- a thought", at: "Inbox/Ideas.md")
            let store: any JournalStore = FileJournalStore(root: root)

            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md", "Inbox/Ideas.md"])
            #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "Walked to the market.\n")
            #expect(try await store.readText(at: "Inbox/Ideas.md") == "- a thought")
        }
    }

    @Test("a written file appears in the listing, folders and all")
    func writesShowUpInListings() async throws {
        try await withTemporaryFolder { root in
            let store: any JournalStore = FileJournalStore(root: root)

            try await store.writeText("Today.", at: "2026/03/2026-03-01.md")

            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
            #expect(try await store.fileExists(at: "2026/03/2026-03-01.md"))
            #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "Today.")
            // The folders the path named were created on the way.
            #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026/03").path))
        }
    }

    @Test("writing again replaces the content, as autosave needs it to")
    func writingOverAnExistingFileReplacesIt() async throws {
        try await withTemporaryFolder { root in
            try root.seed("first", at: "day.md")
            let store: any JournalStore = FileJournalStore(root: root)

            try await store.writeText("second", at: "day.md")

            #expect(try await store.readText(at: "day.md") == "second")
            #expect(try await store.listFiles() == ["day.md"])
        }
    }

    @Test("only files are listed — the folders they sit in are not files")
    func foldersAreNotFiles() async throws {
        try await withTemporaryFolder { root in
            try root.seed("", at: "2026/03/2026-03-01.md")
            // An empty folder holds no Entry, so it is nothing the domain
            // can see — unlike the fake, a disk really does keep one around.
            try FileManager.default.createDirectory(
                at: root.appending(path: "2025/12"),
                withIntermediateDirectories: true
            )
            let store: any JournalStore = FileJournalStore(root: root)

            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
            #expect(try await store.fileExists(at: "2026") == false)
            #expect(try await store.fileExists(at: "2026/03") == false)
            #expect(try await store.fileExists(at: "2025/12") == false)
        }
    }

    @Test("reading a file that is not there fails, rather than reading empty")
    func readingAMissingFileFails() async throws {
        try await withTemporaryFolder { root in
            try root.seed("text", at: "day.md")
            try root.seed("text", at: "2026/03/2026-03-01.md")
            let store: any JournalStore = FileJournalStore(root: root)

            #expect(try await store.fileExists(at: "missing.md") == false)
            await #expect(throws: JournalStoreError.fileNotFound("missing.md")) {
                try await store.read(at: "missing.md")
            }
            // A folder is not a file, so reading one is reading nothing.
            await #expect(throws: JournalStoreError.fileNotFound("2026")) {
                try await store.read(at: "2026")
            }
        }
    }

    @Test("a move takes the content with it and leaves nothing behind")
    func moveRelocatesTheFile() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026-03-01.md")
            let store: any JournalStore = FileJournalStore(root: root)

            try await store.move(from: "2026-03-01.md", to: "2026/03/2026-03-01.md")

            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
            #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "Walked to the market.\n")
            #expect(try await store.fileExists(at: "2026-03-01.md") == false)
        }
    }

    @Test("creating a file where one already is refuses, and keeps both versions")
    func creatingNeverOverwrites() async throws {
        try await withTemporaryFolder { root in
            try root.seed("the iPad's", at: "2026/03/2026-03-01_1.md")
            let store: any JournalStore = FileJournalStore(root: root)

            await #expect(throws: JournalStoreError.fileAlreadyExists("2026/03/2026-03-01_1.md")) {
                try await store.createText("this iPhone's", at: "2026/03/2026-03-01_1.md")
            }

            #expect(try await store.readText(at: "2026/03/2026-03-01_1.md") == "the iPad's")
        }
    }

    @Test("a created file appears in the listing, folders and all")
    func creatingMakesTheFoldersOnTheWay() async throws {
        try await withTemporaryFolder { root in
            let store: any JournalStore = FileJournalStore(root: root)

            try await store.createText("the iPad's", at: "2026/03/2026-03-01_1.md")

            #expect(try await store.listFiles() == ["2026/03/2026-03-01_1.md"])
            #expect(try await store.readText(at: "2026/03/2026-03-01_1.md") == "the iPad's")
        }
    }

    @Test("a move onto an occupied path is refused, and loses neither version")
    func moveNeverOverwrites() async throws {
        try await withTemporaryFolder { root in
            try root.seed("incoming", at: "2026-03-01.md")
            try root.seed("already there", at: "2026/03/2026-03-01.md")
            let store: any JournalStore = FileJournalStore(root: root)

            await #expect(throws: JournalStoreError.fileAlreadyExists("2026/03/2026-03-01.md")) {
                try await store.move(from: "2026-03-01.md", to: "2026/03/2026-03-01.md")
            }

            #expect(try await store.readText(at: "2026-03-01.md") == "incoming")
            #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "already there")
        }
    }

    @Test("moving a file that is not there fails")
    func movingAMissingFileFails() async throws {
        try await withTemporaryFolder { root in
            let store: any JournalStore = FileJournalStore(root: root)

            await #expect(throws: JournalStoreError.fileNotFound("missing.md")) {
                try await store.move(from: "missing.md", to: "day.md")
            }
        }
    }

    @Test("a move to where the file already is changes nothing")
    func movingAFileOntoItselfIsANoOp() async throws {
        try await withTemporaryFolder { root in
            try root.seed("text", at: "day.md")
            let store: any JournalStore = FileJournalStore(root: root)

            try await store.move(from: "day.md", to: "day.md")

            #expect(try await store.readText(at: "day.md") == "text")
        }
    }

    @Test("a file cannot be where a folder is, or a folder where a file is")
    func filesAndFoldersCannotOccupyTheSamePath() async throws {
        try await withTemporaryFolder { root in
            try root.seed("", at: "2026/03/2026-03-01.md")
            try root.seed("", at: "notes.md")
            let store: any JournalStore = FileJournalStore(root: root)

            await #expect(throws: JournalStoreError.pathIsAFolder("2026/03")) {
                try await store.writeText("", at: "2026/03")
            }
            await #expect(throws: JournalStoreError.pathIsNotAFolder("notes.md")) {
                try await store.writeText("", at: "notes.md/inner.md")
            }
            await #expect(throws: JournalStoreError.pathIsNotAFolder("notes.md")) {
                try await store.move(from: "2026/03/2026-03-01.md", to: "notes.md/inner.md")
            }
            await #expect(throws: JournalStoreError.pathIsAFolder("2026/03")) {
                try await store.move(from: "notes.md", to: "2026/03")
            }
        }
    }

    @Test("attachment bytes survive the round trip untouched")
    func binaryContentRoundTrips() async throws {
        try await withTemporaryFolder { root in
            let store: any JournalStore = FileJournalStore(root: root)
            let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

            try await store.write(jpegBytes, at: "attachments/2026/03/photo.jpg")

            #expect(try await store.read(at: "attachments/2026/03/photo.jpg") == jpegBytes)
        }
    }

    @Test("text is stored as UTF-8, accents and emoji included")
    func textIsStoredAsUTF8() async throws {
        try await withTemporaryFolder { root in
            let store: any JournalStore = FileJournalStore(root: root)

            try await store.writeText("Café ☕️ — déjà vu", at: "day.md")

            #expect(try await store.readText(at: "day.md") == "Café ☕️ — déjà vu")
            // Byte-for-byte what Obsidian would find on disk.
            let onDisk = try Data(contentsOf: root.appending(path: "day.md"))
            #expect(onDisk == Data("Café ☕️ — déjà vu".utf8))
        }
    }

    @Test("paths that no folder could hold are refused, whichever way they arrive")
    func unusablePathsAreRefused() async throws {
        try await withTemporaryFolder { root in
            try root.seed("text", at: "day.md")
            let store: any JournalStore = FileJournalStore(root: root)

            for path in ["", "   ", "/2026/day.md", "2026//day.md", "2026/day.md/", ".", "..", "../day.md", "2026/../day.md", "2026/./day.md"] {
                await #expect(throws: JournalStoreError.invalidPath(path), "writing \(path)") {
                    try await store.writeText("", at: path)
                }
                await #expect(throws: JournalStoreError.invalidPath(path), "reading \(path)") {
                    try await store.read(at: path)
                }
                await #expect(throws: JournalStoreError.invalidPath(path), "asking about \(path)") {
                    try await store.fileExists(at: path)
                }
                await #expect(throws: JournalStoreError.invalidPath(path), "creating \(path)") {
                    try await store.createText("", at: path)
                }
                await #expect(throws: JournalStoreError.invalidPath(path), "moving to \(path)") {
                    try await store.move(from: "day.md", to: path)
                }
                await #expect(throws: JournalStoreError.invalidPath(path), "moving from \(path)") {
                    try await store.move(from: path, to: "elsewhere.md")
                }
            }
        }
    }

    @Test("a path that hops out of the Journal Root never reaches the file system")
    func pathsThatEscapeTheJournalRootTouchNothing() async throws {
        try await withTemporaryFolder { enclosing in
            let root = enclosing.appending(path: "Journal", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try enclosing.seed("someone else's note", at: "Vault/Secret.md")
            let store: any JournalStore = FileJournalStore(root: root)

            await #expect(throws: JournalStoreError.invalidPath("../Vault/Secret.md")) {
                try await store.read(at: "../Vault/Secret.md")
            }
            await #expect(throws: JournalStoreError.invalidPath("../Vault/Secret.md")) {
                try await store.writeText("clobbered", at: "../Vault/Secret.md")
            }
            await #expect(throws: JournalStoreError.invalidPath("../Vault/Secret.md")) {
                try await store.createText("parked here", at: "../Vault/Secret.md")
            }

            let untouched = try String(contentsOf: enclosing.appending(path: "Vault/Secret.md"), encoding: .utf8)
            #expect(untouched == "someone else's note")
        }
    }
}

// What a folder on a device has that the in-memory fake does not: it can be
// gone, it holds files Aujour did not put there, and iCloud may not have
// brought a file's content down yet.
@Suite("File Journal Store over a real folder")
struct FileJournalStoreRealFolderTests {
    @Test("a Journal Root that is not there fails loudly, rather than reading as an empty journal")
    func aMissingRootIsAnErrorAndNotAnEmptyJournal() async throws {
        try await withTemporaryFolder { enclosing in
            let root = enclosing.appending(path: "Gone", directoryHint: .isDirectory)
            let store: any JournalStore = FileJournalStore(root: root)

            // An empty listing would tell the calendar the user never wrote
            // anything — the one answer that must never be a guess.
            await #expect(throws: JournalRootError.journalRootUnavailable) {
                try await store.listFiles()
            }
            await #expect(throws: JournalRootError.journalRootUnavailable) {
                try await store.writeText("Today.", at: "day.md")
            }
        }
    }

    @Test("the folder's own hidden files are not part of the journal")
    func hiddenFilesAreNotJournalFiles() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try root.seed("", at: ".DS_Store")
            // An Obsidian vault keeps its configuration in a hidden folder;
            // none of it is the user's journal.
            try root.seed("{}", at: ".obsidian/app.json")
            try root.seed("{}", at: ".obsidian/plugins/daily-notes/data.json")
            let store: any JournalStore = FileJournalStore(root: root)

            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        }
    }

    @Test("a file iCloud has not brought down is journaled, and reading it says so")
    func anEvictedFileIsListedButNotReadableYet() async throws {
        try await withTemporaryFolder { root in
            // How iCloud represents a file whose content is not on this
            // device: a hidden placeholder beside where the file belongs.
            try root.seed("", at: "2026/03/.2026-03-01.md.icloud")
            let store: any JournalStore = FileJournalStore(root: root)

            // The day *is* journaled — the calendar must not show a hole.
            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
            #expect(try await store.fileExists(at: "2026/03/2026-03-01.md"))

            // But its words are not here yet, and the placeholder's own bytes
            // are not the user's Entry.
            await #expect(throws: JournalRootError.notDownloaded("2026/03/2026-03-01.md")) {
                try await store.readText(at: "2026/03/2026-03-01.md")
            }
            // Writing would replace a version of the day this device has
            // never seen.
            await #expect(throws: JournalRootError.notDownloaded("2026/03/2026-03-01.md")) {
                try await store.writeText("clobbered", at: "2026/03/2026-03-01.md")
            }
        }
    }

    @Test("a folder that cannot be read through is an error, not a shorter journal")
    func aFolderThatCannotBeReadThroughFailsRatherThanListingLess() async throws {
        try await withTemporaryFolder { root in
            try root.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try root.seed("February's last day.\n", at: "2026/02/2026-02-28.md")
            let closed = root.appending(path: "2026/02")
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: closed.path
                )
            }
            let store: any JournalStore = FileJournalStore(root: root)

            // Returning just March would say February was never written.
            let failure = await #expect(throws: JournalRootError.self) {
                try await store.listFiles()
            }
            guard case .readFailed(let path, _) = failure else {
                Issue.record("expected the unreadable folder to be named, got \(String(describing: failure))")
                return
            }
            #expect(path == "2026/02")
        }
    }

    @Test("every storage failure has a sentence to show the user")
    func storageFailuresArePresentable() {
        let failures: [JournalRootError] = [
            .journalRootUnavailable,
            .notDownloaded("2026/03/2026-03-01.md"),
            .readFailed(path: "day.md", reason: "permission denied"),
            .writeFailed(path: "day.md", reason: "disk full"),
            .moveFailed(source: "a.md", destination: "b.md", reason: "permission denied"),
        ]

        for failure in failures {
            #expect(failure.errorDescription?.isEmpty == false, "\(failure) has nothing to say")
            #expect(failure.recoverySuggestion?.isEmpty == false, "\(failure) offers no way out")
        }
    }
}
