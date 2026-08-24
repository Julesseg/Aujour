import Foundation
import Testing
import AujourCore

@testable import Aujour

private let firstOfMarch = JournalDay(year: 2026, month: 3, day: 1)

// The Search Index between launches, over a real caches folder. Everything
// about what a search *finds* is Core's and tested there against an in-memory
// folder; what is left here is the file itself — that it is written where a
// disposable cache belongs, read back as what was written, and that losing it
// is nothing more than a cache that is not there (ADR 0001).
@Suite("The search index kept between launches")
struct SearchIndexFileTests {
    @Test("an index written down is the index read back")
    func anIndexRoundTripsThroughAFile() async throws {
        try await withTemporaryFolder { caches in
            let cache = SearchIndexFile(forJournalAt: journalRoot, in: caches)
            let index = SearchIndex([firstOfMarch: "Walked to the market."])

            await cache.save(index.encoded())

            let written = try #require(await cache.load())
            #expect(SearchIndex(decoding: written) == index)
        }
    }

    @Test("a cache nothing has been written to yet is simply not there")
    func anEmptyCacheLoadsAsNothing() async throws {
        try await withTemporaryFolder { caches in
            #expect(await SearchIndexFile(forJournalAt: journalRoot, in: caches).load() == nil)
        }
    }

    @Test("a cache thrown away is a cache that is not there, and nothing worse")
    func aDeletedCacheIsNotThere() async throws {
        try await withTemporaryFolder { caches in
            let cache = SearchIndexFile(forJournalAt: journalRoot, in: caches)
            await cache.save(SearchIndex([firstOfMarch: "Walked to the market."]).encoded())

            // What the system does when it reclaims a caches folder, and what
            // deleting and reinstalling the app does.
            try FileManager.default.removeItem(at: cache.file)

            #expect(await cache.load() == nil)
        }
    }

    @Test("bytes that are not an index at all are no index, not a crash")
    func rubbishInTheCacheIsNoIndex() async throws {
        try await withTemporaryFolder { caches in
            let cache = SearchIndexFile(forJournalAt: journalRoot, in: caches)
            await cache.save(Data("half a file, and then the app went away".utf8))

            let written = try #require(await cache.load())
            #expect(SearchIndex(decoding: written) == nil)
        }
    }

    @Test("the index is written where a disposable cache belongs")
    func theIndexIsWrittenIntoTheCachesFolder() async throws {
        try await withTemporaryFolder { caches in
            let cache = SearchIndexFile(forJournalAt: journalRoot, in: caches)

            await cache.save(SearchIndex([firstOfMarch: "Walked to the market."]).encoded())

            // Inside the folder it was given — never in the Journal Root,
            // which holds Entries, Attachments and Parked Files and nothing of
            // Aujour's own (ADR 0003).
            #expect(cache.file.path.hasPrefix(caches.path))
            #expect(FileManager.default.fileExists(atPath: cache.file.path))
        }
    }

    @Test("two journals do not share one index")
    func eachJournalRootHasItsOwnFile() async throws {
        try await withTemporaryFolder { caches in
            let vault = SearchIndexFile(
                forJournalAt: URL(filePath: "/Users/somebody/Vault/Journal"),
                in: caches
            )
            let aujours = SearchIndexFile(forJournalAt: journalRoot, in: caches)
            #expect(vault.file != aujours.file)

            await vault.save(SearchIndex([firstOfMarch: "Walked to the market."]).encoded())

            // A journal moved into an Obsidian vault is a different journal
            // with different days in it, and the folder just left must not be
            // what a search over this one answers from.
            #expect(await aujours.load() == nil)
        }
    }

    @Test("the same journal is the same file, launch after launch")
    func oneJournalRootIsAlwaysTheSameFile() {
        let caches = URL(filePath: "/tmp/caches")
        #expect(
            SearchIndexFile(forJournalAt: journalRoot, in: caches).file
                == SearchIndexFile(forJournalAt: journalRoot, in: caches).file
        )
        // The same folder said two ways is the same folder: a path with a
        // trailing slash or a `.` hop in it is one the user could not tell
        // apart, and two indexes over one journal would be one of them going
        // stale unnoticed.
        #expect(
            SearchIndexFile(forJournalAt: URL(filePath: "/Users/somebody/Journal/"), in: caches).file
                == SearchIndexFile(
                    forJournalAt: URL(filePath: "/Users/somebody/./Journal"), in: caches
                ).file
        )
    }

    private var journalRoot: URL { URL(filePath: "/Users/somebody/Journal") }
}
