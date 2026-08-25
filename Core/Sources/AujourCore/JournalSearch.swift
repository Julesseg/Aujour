import Foundation
import Observation

/// Where the Search Index is kept between launches.
///
/// App-private storage, and the one kind ADR 0001 allows besides settings: a
/// disposable cache. What is in it is a copy of words that are already in the
/// user's own files, so the whole of what losing it costs is the time it takes
/// to read the folder again.
///
/// Neither half can fail, which is the shape of it. A cache that would not be
/// read is a cache that is not there, and a cache that would not be written is
/// a search that reads the folder next launch too — neither is anything to put
/// in front of somebody, and neither is a journal that would not open.
public protocol SearchIndexCache: Sendable {
    /// What was written down last, or `nil` for a cache that is empty, gone,
    /// or unreadable.
    func load() async -> Data?

    /// Keeps the index for the next launch, best-effort.
    func save(_ index: Data) async
}

/// Finding a day by something written in it.
///
/// The whole of search, and it is a scan of the Journal Root and a cache of
/// what that scan read (ADR 0001). There is no store of days and words that
/// the folder has to be kept in step with: the index *is* the last reading of
/// the folder, so a day written in Obsidian, arriving from another device, or
/// pruned out of the vault is a day the next reindex agrees about — and one
/// deleted index costs a read of the folder and nothing else.
///
/// The cache is only ever a head start. ``open()`` puts what was written down
/// last launch in front of the search box straight away, so a query typed in
/// the first second is answered, and then reads the folder underneath it —
/// which is what makes stale results a flicker rather than a state anybody
/// stays in.
///
/// Querying is pure and does not touch the folder at all, which is what lets a
/// result list follow somebody typing. Reading the folder is where the time
/// goes, so it happens off the main actor: a journal of a thousand days is a
/// thousand files to read, and doing that where the screen is drawn would be a
/// search box that stutters while it fills.
@MainActor
@Observable
public final class JournalSearch {
    /// The journal's words as of the last reading — the disposable cache
    /// every result is drawn from.
    private var index = SearchIndex()

    /// What went wrong with the last reading of the folder, if it did.
    ///
    /// Surfaced rather than swallowed, for the calendar's reason: a folder
    /// that could not be read gives a search that finds nothing, which is
    /// exactly what a journal nobody has written in looks like. Only one of
    /// those is true, and the screen has to be able to say which (ADR 0001).
    public private(set) var problem: (any Error)?

    /// Whether the folder is being read right now — for a screen that has
    /// nothing to show yet and would otherwise look like a journal with
    /// nothing in it.
    public private(set) var isReading = false

    /// Whether anything has been indexed at all: a first launch, mid-scan, and
    /// a journal with no Entries in it.
    public var hasNothingIndexed: Bool { index.isEmpty }

    /// Whether the folder has been read through and found to hold no Entries
    /// at all — a journal at its beginning, and not one of the two other
    /// things an empty result list can be.
    ///
    /// The distinction the whole screen is arranged around (ADR 0001). A
    /// folder nothing has looked in yet and a folder that would not answer
    /// both find nothing, and neither is somebody who has not written
    /// anything: a decade of days that has not come down from iCloud must
    /// never be told it is a journal with nothing in it. So this is true only
    /// after a reading of the folder that worked.
    public var isAJournalNobodyHasWrittenIn: Bool {
        hasBeenRead && problem == nil && index.isEmpty
    }

    /// Whether the folder has ever answered a whole-journal reading.
    ///
    /// Observed rather than ignored, like `problem` beside it: it is half of
    /// what the screen draws when there is nothing to show, and a screen that
    /// did not redraw when the folder finally answered would be stuck saying
    /// it had not.
    private var hasBeenRead = false

    @ObservationIgnored private let store: any JournalStore
    @ObservationIgnored private let settings: JournalSettings
    @ObservationIgnored private let cache: (any SearchIndexCache)?

    /// The reading of the folder that is going on right now, if one is — what
    /// the next one queues behind.
    ///
    /// One at a time, because every one of them ends by putting an index in
    /// place of the one before: a whole-folder scan finishing after the day
    /// somebody has just written was read on its own would put the index back
    /// to before they wrote it.
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// - Parameters:
    ///   - store: the folder this Journal lives in.
    ///   - settings: the Path Template that says which of its files are
    ///     Entries, and so which of them are searched.
    ///   - cache: where the index is kept between launches. Nowhere by
    ///     default, which is a search that reads the folder every time it is
    ///     opened — slower, and no less correct.
    public init(
        store: any JournalStore,
        settings: JournalSettings = .default,
        cache: (any SearchIndexCache)? = nil
    ) {
        self.store = store
        self.settings = settings
        self.cache = cache
    }

    /// The days matching a query, most recent first — answered from what has
    /// been read, without touching the folder.
    public func results(for query: String) -> [SearchResult] {
        index.results(for: query)
    }

    // MARK: - Reading the folder

    /// Puts last launch's index in front of the search box, and then brings it
    /// up to date by reading the folder.
    ///
    /// The cache is read only when there is nothing indexed yet: an index this
    /// object has already built is this launch's reading of the folder, and
    /// what was written down is at best the same and at worst older.
    public func open() async {
        if index.isEmpty, let cache, let restored = await Self.read(from: cache) {
            index = restored
        }
        await reindex()
    }

    /// Rebuilds the index by reading every Entry in the Journal Root.
    ///
    /// This is the only way one is ever built, which is what makes an Entry
    /// edited outside Aujour — in Obsidian, on another device — a day this
    /// agrees about the moment it is next read. Nothing is asked of the folder
    /// beyond the files themselves: no modification dates, no change feed, and
    /// so nothing that could be wrong about which days need re-reading.
    public func reindex() async {
        await inTurn {
            self.isReading = true
            defer { self.isReading = false }

            switch await Self.readTheJournal(from: self.store, settings: self.settings) {
            case .success(let read):
                self.index = read
                self.hasBeenRead = true
                self.problem = nil
                await Self.write(read, to: self.cache)
            case .failure(let error):
                // What was read last time is kept: it is the last true reading
                // of the folder, and dropping it would turn a folder that
                // failed to answer into a journal with nothing in it.
                // `problem` is what says the reading may be behind.
                self.problem = error
            }
        }
    }

    /// Brings one day up to date, for the day just written in.
    ///
    /// What coming back from an Entry costs, instead of the whole folder: one
    /// file read, so that a word typed a moment ago is findable without the
    /// journal being read from end to end every time somebody leaves a day.
    public func reindex(_ day: JournalDay) async {
        await inTurn {
            guard let template = try? PathTemplate(self.settings.pathTemplate) else { return }
            let path = template.render(day)

            do {
                self.index.index(try await self.store.readText(at: path), for: day)
            } catch JournalStoreError.fileNotFound {
                // A day with no file is a day nobody has written — either it
                // was opened and left blank, or the folder has been pruned.
                // Either way it is not a day any search should find.
                self.index.forget(day)
            } catch {
                // Anything else is the folder not answering, which says nothing
                // about what that day holds. What was indexed stays indexed.
                return
            }
            await Self.write(self.index, to: self.cache)
        }
    }

    /// Runs a reading of the folder after whichever one is already going.
    ///
    /// Queued rather than refused, so that a day just written in is still read
    /// when it happens during a whole-folder scan — and still read *after* it,
    /// which is the only order in which both readings end up true.
    private func inTurn(_ read: @escaping @MainActor () async -> Void) async {
        let inFront = reading
        let turn = Task { @MainActor in
            await inFront?.value
            await read()
        }
        reading = turn
        await turn.value
    }

    /// The index the cache is holding, if it is holding one.
    ///
    /// `nonisolated` for the reason the scan is: decoding is a pass over every
    /// word the last scan read, and the screen it is filling is already up.
    private nonisolated static func read(from cache: any SearchIndexCache) async -> SearchIndex? {
        guard let written = await cache.load() else { return nil }
        return SearchIndex(decoding: written)
    }

    /// Keeps the index for the next launch, off the main actor — encoding it
    /// is the same pass over the same words, and it happens after every
    /// reading of the folder.
    private nonisolated static func write(
        _ index: SearchIndex,
        to cache: (any SearchIndexCache)?
    ) async {
        guard let cache else { return }
        await cache.save(index.encoded())
    }

    /// Every Entry in the folder, read and indexed.
    ///
    /// `nonisolated` so that it runs off the main actor: this is a file read
    /// per day and a pass over every word in the journal, and the search box it
    /// fills is on screen while it happens.
    private nonisolated static func readTheJournal(
        from store: any JournalStore,
        settings: JournalSettings
    ) async -> Result<SearchIndex, any Error> {
        do {
            // A Path Template that cannot name a day cannot say which files
            // are Entries either, so there is nothing to search — that is a
            // sentence for the user rather than an empty result list (ADR
            // 0002).
            let template = try PathTemplate(settings.pathTemplate)
            var read = SearchIndex()
            for path in try await store.listFiles() {
                guard let day = template.match(path) else { continue }
                // A file that will not come back as text — a photograph under
                // an `.md` name, a file iCloud has not brought down — is a day
                // that cannot be searched, and nothing more than that. One of
                // them must not cost the whole journal its search.
                guard let text = try? await store.readText(at: path) else { continue }
                read.index(text, for: day)
            }
            return .success(read)
        } catch {
            return .failure(error)
        }
    }
}
