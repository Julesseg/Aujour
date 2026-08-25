import Foundation
import Testing

@testable import AujourCore

private let firstOfMarch = JournalDay(year: 2026, month: 3, day: 1)
private let secondOfMarch = JournalDay(year: 2026, month: 3, day: 2)

/// A folder as a user would have it: two Entries under the default Path
/// Template, and a vault's worth of everything else around them.
private let vault: [String: String] = [
    "2026/03/2026-03-01.md": "# Sunday\n\nWalked to the market with Robin.\n",
    "2026/03/2026-03-02.md": "Rained all day. Stayed in and read.\n",
    "Inbox/Market research.md": "Somebody else's note about the market.\n",
    ".obsidian/app.json": "{ \"promptDelete\": false }\n",
]

/// A Journal Store that can be made to refuse a listing, as a folder in iCloud
/// that has not come down would.
private final class FolderThatCanRefuse: JournalStore, @unchecked Sendable {
    private let folder: InMemoryJournalStore

    var refuseListing: (any Error)?

    /// Files another app has taken out of the folder. Kept here rather than
    /// in the store because nothing in Aujour deletes a file — the seam has no
    /// way to say it, and pruning a folder is done in Files or Obsidian.
    private let deletions = NSLock()
    private var deleted: Set<String> = []

    init(_ files: [String: String] = [:]) {
        folder = InMemoryJournalStore(files)
    }

    /// Writes a file as another app would, with the app none the wiser.
    func somebodyElseWrites(_ text: String, at path: String) async throws {
        try await folder.write(Data(text.utf8), at: path)
    }

    func somebodyElseWrites(_ bytes: Data, at path: String) async throws {
        try await folder.write(bytes, at: path)
    }

    /// Takes a file out of the folder, as somebody pruning their vault would.
    func somebodyElseDeletes(_ path: String) {
        deletions.withLock { _ = deleted.insert(path) }
    }

    private func isDeleted(_ path: String) -> Bool {
        deletions.withLock { deleted.contains(path) }
    }

    func listFiles() async throws -> [String] {
        if let refuseListing { throw refuseListing }
        return await folder.listFiles().filter { !isDeleted($0) }
    }

    func fileExists(at relativePath: String) async throws -> Bool {
        if isDeleted(relativePath) { return false }
        return try await folder.fileExists(at: relativePath)
    }

    func read(at relativePath: String) async throws -> Data {
        if isDeleted(relativePath) { throw JournalStoreError.fileNotFound(relativePath) }
        return try await folder.read(at: relativePath)
    }

    func write(_ contents: Data, at relativePath: String) async throws {
        try await folder.write(contents, at: relativePath)
    }

    func create(_ contents: Data, at relativePath: String) async throws {
        try await folder.create(contents, at: relativePath)
    }

    func move(from source: String, to destination: String) async throws {
        try await folder.move(from: source, to: destination)
    }
}

/// Somewhere to keep the index between launches, as the app's own caches
/// folder is — and which a test can empty, which is the point of it.
private final class ACacheOfItsOwn: SearchIndexCache, @unchecked Sendable {
    private let lock = NSLock()
    private var written: Data?

    init(holding index: SearchIndex? = nil) {
        written = index?.encoded()
    }

    /// What the last scan wrote down, if anything did.
    var contents: Data? { lock.withLock { written } }

    /// The user, or the system, throwing the cache away.
    func empty() { lock.withLock { written = nil } }

    func load() async -> Data? { lock.withLock { written } }

    func save(_ index: Data) async { lock.withLock { written = index } }
}

/// A folder that nothing can be read from — a device that has run out of the
/// answers a store gives.
private struct AFolderThatWillNotBeRead: Error {}

@MainActor
@Suite("Searching the journal by reading the folder")
struct JournalSearchTests {
    @Test("a word finds the day whose Entry says it")
    func aQueryFindsTheDayThatSaysIt() async {
        let search = JournalSearch(store: InMemoryJournalStore(vault))

        await search.open()

        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
        #expect(search.problem == nil)
    }

    @Test("only Entries are searched — a vault's other notes are nobody's day")
    func onlyEntriesAreSearched() async {
        let search = JournalSearch(store: InMemoryJournalStore(vault))

        await search.open()

        // `Inbox/Market research.md` says "market" too, and is not an Entry
        // under the current Path Template, so it is not a day and cannot be
        // one of these results (ADR 0002).
        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "somebody").isEmpty)
    }

    @Test("which files are Entries is the Path Template's answer and nothing else")
    func theTemplateDecidesWhatIsSearched() async {
        var settings = JournalSettings.default
        settings.pathTemplate = "[Daily]/YYYY-MM-DD"
        let search = JournalSearch(
            store: InMemoryJournalStore([
                "2026/03/2026-03-01.md": "Walked to the market.\n",
                "Daily/2026-03-02.md": "Rained all day.\n",
            ]),
            settings: settings
        )

        await search.open()

        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
        #expect(search.results(for: "market").isEmpty)
    }

    // MARK: - Keeping up with a folder other apps write in

    @Test("a day rewritten in Obsidian says what it says now, after a reindex")
    func anExternalEditIsReflectedAfterAReindex() async throws {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        await search.open()

        try await folder.somebodyElseWrites(
            "Walked to the mountain instead.\n",
            at: "2026/03/2026-03-01.md"
        )
        await search.reindex()

        #expect(search.results(for: "mountain").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "market").isEmpty)
    }

    @Test("a day added in Obsidian is found after a reindex")
    func anExternallyAddedDayIsFoundAfterAReindex() async throws {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        await search.open()
        #expect(search.results(for: "mountain").isEmpty)

        try await folder.somebodyElseWrites(
            "Climbed the mountain.\n",
            at: "2026/03/2026-03-14.md"
        )
        await search.reindex()

        #expect(
            search.results(for: "mountain").map(\.day) == [JournalDay(year: 2026, month: 3, day: 14)]
        )
    }

    @Test("one day brought up to date on its own, for the day just written in")
    func oneDayCanBeReindexedOnItsOwn() async throws {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        await search.open()

        try await folder.somebodyElseWrites(
            "Walked to the mountain instead.\n",
            at: "2026/03/2026-03-01.md"
        )
        await search.reindex(firstOfMarch)

        #expect(search.results(for: "mountain").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "market").isEmpty)
        // And the rest of the journal is exactly where it was.
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
    }

    @Test("a day whose file has gone stops being a result")
    func aDayWithNoFileIsDropped() async {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        await search.open()

        // Nothing in Aujour deletes an Entry, so this is the folder being
        // pruned in Files or Obsidian — the only way a day loses its file.
        folder.somebodyElseDeletes("2026/03/2026-03-01.md")
        await search.reindex(firstOfMarch)

        #expect(search.results(for: "market").isEmpty)
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
    }

    @Test("a day whose file has gone is gone from a full reindex too")
    func aDayWithNoFileIsDroppedByAScan() async {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        await search.open()

        folder.somebodyElseDeletes("2026/03/2026-03-01.md")
        await search.reindex()

        #expect(search.results(for: "market").isEmpty)
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
    }

    @Test("reindexing a day nobody has written changes nothing")
    func reindexingAnUnwrittenDayChangesNothing() async {
        let search = JournalSearch(store: InMemoryJournalStore(vault))
        await search.open()

        // What a day opened from the calendar and left blank comes back as:
        // there is no file, so there is nothing to index and nothing to drop.
        await search.reindex(JournalDay(year: 2026, month: 3, day: 9))

        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
    }

    @Test("a file that is not text does not stop the rest being read")
    func anUnreadableFileDoesNotStopTheScan() async throws {
        let folder = FolderThatCanRefuse(vault)
        // A photograph somebody dropped into the folder under an `.md` name,
        // sitting exactly where an Entry would be.
        try await folder.somebodyElseWrites(
            Data([0xFF, 0xD8, 0xFF, 0xE0]),
            at: "2026/03/2026-03-03.md"
        )
        let search = JournalSearch(store: folder)

        await search.open()

        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
        #expect(search.problem == nil)
    }

    @Test("a journal with no Entries in it says so, once the folder has answered")
    func aJournalNobodyHasWrittenIn() async {
        let search = JournalSearch(store: InMemoryJournalStore())

        // Before the folder has answered, nothing indexed is nothing looked
        // at: a search box that opened by announcing an empty journal would be
        // announcing one it had not read (ADR 0001).
        #expect(!search.isAJournalNobodyHasWrittenIn)

        await search.open()

        #expect(search.isAJournalNobodyHasWrittenIn)
    }

    @Test("a journal with days in it is never called empty")
    func aJournalWithDaysInItIsNotEmpty() async {
        let search = JournalSearch(store: InMemoryJournalStore(vault))

        await search.open()

        #expect(!search.isAJournalNobodyHasWrittenIn)
    }

    @Test("a folder that would not answer is never called an empty journal")
    func anUnreadableFolderIsNeverCalledEmpty() async {
        let folder = FolderThatCanRefuse()
        folder.refuseListing = AFolderThatWillNotBeRead()
        let search = JournalSearch(store: folder)

        await search.open()

        // The confusion the whole screen is arranged around: a decade of days
        // whose folder has not come down from iCloud finds nothing, and that
        // is not the same sentence as "you have not written anything".
        #expect(search.problem is AFolderThatWillNotBeRead)
        #expect(!search.isAJournalNobodyHasWrittenIn)
    }

    @Test("a folder that will not answer keeps what was read and says so")
    func aFolderThatWillNotListKeepsTheLastReading() async {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        await search.open()

        folder.refuseListing = AFolderThatWillNotBeRead()
        await search.reindex()

        // Not an empty search box, which would read as a journal with nothing
        // in it — the last true reading of the folder, and a problem beside it
        // saying it may be behind (ADR 0001).
        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(search.problem is AFolderThatWillNotBeRead)
    }

    @Test("a folder that answers again clears the problem")
    func aFolderThatAnswersAgainIsNoLongerAProblem() async {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)
        folder.refuseListing = AFolderThatWillNotBeRead()
        await search.open()
        #expect(search.problem is AFolderThatWillNotBeRead)

        folder.refuseListing = nil
        await search.reindex()

        #expect(search.problem == nil)
        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
    }

    @Test("readings of the folder asked for at once all land, and land in order")
    func readingsAskedForAtOnceTakeTheirTurns() async throws {
        let folder = FolderThatCanRefuse(vault)
        let search = JournalSearch(store: folder)

        // The search screen appearing while the day just left is being read on
        // its own — which on a journal of any size is a scan that has not
        // finished by the time the next reading is asked for. Every one of
        // them ends by putting an index in place of the one before, so they
        // are made to take turns rather than land on each other.
        async let opening: Void = search.open()
        async let again: Void = search.reindex()
        async let oneDay: Void = search.reindex(secondOfMarch)
        _ = await (opening, again, oneDay)

        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(search.results(for: "rained").map(\.day) == [secondOfMarch])
        // And the queue drained: nothing is left waiting on a turn that never
        // comes.
        #expect(!search.isReading)
    }

    // MARK: - A cache that loses nothing

    @Test("a scan writes the index down")
    func aScanWritesTheIndexDown() async {
        let cache = ACacheOfItsOwn()
        let search = JournalSearch(store: InMemoryJournalStore(vault), cache: cache)

        await search.open()

        let written = SearchIndex(decoding: cache.contents ?? Data())
        #expect(written?.results(for: "market").map(\.day) == [firstOfMarch])
    }

    @Test("deleting the index loses nothing — the folder builds another")
    func aDeletedIndexIsRebuiltByScanning() async {
        let folder = InMemoryJournalStore(vault)
        let cache = ACacheOfItsOwn()
        await JournalSearch(store: folder, cache: cache).open()

        // The system reclaiming a caches folder, or the user reinstalling the
        // app: everything Aujour kept about the journal, gone.
        cache.empty()

        let afterwards = JournalSearch(store: folder, cache: cache)
        await afterwards.open()

        #expect(afterwards.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(afterwards.results(for: "rained").map(\.day) == [secondOfMarch])
    }

    @Test("what was written down answers before the folder has been read")
    func theCacheAnswersBeforeTheScanDoes() async {
        let folder = FolderThatCanRefuse(vault)
        let cache = ACacheOfItsOwn(holding: SearchIndex([firstOfMarch: "Walked to the market."]))
        // A folder that will not answer at all, which is what a scan taking
        // its time looks like from the search box: the results on screen in
        // the meantime are the ones written down last launch.
        folder.refuseListing = AFolderThatWillNotBeRead()
        let search = JournalSearch(store: folder, cache: cache)

        await search.open()

        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
    }

    @Test("a search with nowhere to keep an index still searches")
    func noCacheIsNotAProblem() async {
        let search = JournalSearch(store: InMemoryJournalStore(vault))

        await search.open()

        #expect(search.results(for: "market").map(\.day) == [firstOfMarch])
    }
}
