import Foundation
import Testing
import AujourCore
@testable import Aujour

// What the app does before it shows anybody anything: find the folder, open a
// store over it, and end up in one of exactly two states — journaling, or
// saying why not.
@MainActor
@Suite("Opening the journal on launch")
struct JournalStorageTests {
    @Test("a fresh install opens onto a real folder, with no configuration anywhere")
    func aFreshInstallOpensOntoARealFolder() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let storage = JournalStorage(locator: .test(iCloudDocuments: iCloud, folders: folders))

            await storage.open()

            #expect(storage.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .iCloudDrive), fileCount: 0))
            #expect(storage.store != nil)

            // And it is a folder the app can actually journal into.
            try await #require(storage.store).writeText("First words.\n", at: "2026/03/2026-03-01.md")
            let onDisk = try String(
                contentsOf: iCloud.appending(path: "2026/03/2026-03-01.md"),
                encoding: .utf8
            )
            #expect(onDisk == "First words.\n")
        }
    }

    @Test("a folder that already holds a journal opens with it, not over it")
    func anExistingJournalIsFoundWhereItWasLeft() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try iCloud.seed("February's last day.\n", at: "2026/02/2026-02-28.md")
            let storage = JournalStorage(locator: .test(iCloudDocuments: iCloud, folders: folders))

            await storage.open()

            #expect(storage.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .iCloudDrive), fileCount: 2))
        }
    }

    @Test("a folder Aujour cannot reach becomes something to say, not an empty page")
    func anUnreachableFolderIsPresented() async throws {
        try await withTemporaryFolder { folders in
            try folders.seed("in the way", at: "Device")
            let storage = JournalStorage(
                locator: JournalRootLocator(
                    iCloudDocuments: { nil },
                    onThisDeviceDocuments: { folders.appending(path: "Device/Documents") },
                    lastUsedLocation: { nil },
                    rememberLocation: { _ in }
                )
            )

            await storage.open()

            guard case .unavailable(let problem) = storage.state else {
                Issue.record("expected an unavailable journal, got \(storage.state)")
                return
            }
            #expect(problem.message.isEmpty == false)
            #expect(problem.suggestion.isEmpty == false)
            // Nothing to journal through: better than a store that silently
            // writes somewhere the rest of the journal is not.
            #expect(storage.store == nil)
        }
    }

    @Test("both places the journal can live are described to the user")
    func everyLocationSaysWhatItMeansForTheirWords() {
        for location in [JournalRoot.Location.iCloudDrive, .onThisDevice] {
            #expect(location.name.isEmpty == false)
            #expect(location.promise.isEmpty == false)
        }
        // The one thing the on-device story has to be honest about.
        #expect(JournalRoot.Location.onThisDevice.promise.contains("iCloud Drive"))
    }
}

extension JournalRootLocator {
    /// A locator over folders a test owns, starting from nothing remembered.
    static func test(iCloudDocuments: URL, folders: URL) -> JournalRootLocator {
        JournalRootLocator(
            iCloudDocuments: { iCloudDocuments },
            onThisDeviceDocuments: { folders.appending(path: "Device/Documents") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in }
        )
    }
}
