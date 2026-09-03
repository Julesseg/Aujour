import Foundation
import Testing

@testable import AujourCore

/// The queries somebody has already searched their journal with, and what an
/// empty search box offers them back.
@Suite("Recent searches")
struct RecentSearchesTests {
    @Test("a query just searched with is the first one offered back")
    func themostRecentQueryIsFirst() {
        var recent = RecentSearches()

        recent.remember("market")
        recent.remember("robin")

        #expect(recent.queries == ["robin", "market"])
    }

    @Test("searching the same thing again moves it up rather than doubling it")
    func aQuerySearchedTwiceIsKeptOnce() {
        var recent = RecentSearches(["robin", "market"])

        recent.remember("market")

        #expect(recent.queries == ["market", "robin"])
    }

    @Test("two spellings of one query are one query, in the spelling just typed")
    func aQueryIsTheWordsInItAndNotItsSpelling() {
        var recent = RecentSearches(["Café de Flore"])

        recent.remember("cafe de flore")

        // The same words folded the same way, so it is the same search — and
        // what is offered back is what they typed this time.
        #expect(recent.queries == ["cafe de flore"])
    }

    @Test("a query with no words in it is not a search anybody made")
    func aQueryOfNothingIsNotRemembered() {
        var recent = RecentSearches(["market"])

        recent.remember("")
        recent.remember("   ")
        recent.remember("…—")

        #expect(recent.queries == ["market"])
    }

    @Test("the space around a query is not part of it")
    func aQueryIsTrimmed() {
        var recent = RecentSearches()

        recent.remember("  market  ")

        #expect(recent.queries == ["market"])
    }

    @Test("only the recent end of them is kept")
    func onlyAHandfulAreKept() {
        var recent = RecentSearches()

        for query in (1...RecentSearches.mostKept + 3).map({ "query \($0)" }) {
            recent.remember(query)
        }

        #expect(recent.queries.count == RecentSearches.mostKept)
        #expect(recent.queries.first == "query \(RecentSearches.mostKept + 3)")
        #expect(!recent.queries.contains("query 1"))
    }

    @Test("what was written down reads back as what was searched with")
    func aRoundTripKeepsTheQueries() {
        var recent = RecentSearches()
        recent.remember("market")
        recent.remember("Café")

        #expect(RecentSearches(decoding: recent.encoded()).queries == ["Café", "market"])
    }

    @Test("something that is not a list of queries is no queries, not a crash")
    func unreadableStorageIsAnEmptyList() {
        #expect(RecentSearches(decoding: "not json at all").queries.isEmpty)
        #expect(RecentSearches(decoding: nil).queries.isEmpty)
    }
}

/// Where those queries are kept between launches: this device, and nowhere
/// else.
@Suite("Recent searches, kept on this device")
@MainActor
struct RecentSearchesStoreTests {
    @Test("a query remembered is there in the next launch")
    func queriesSurviveALaunch() {
        let onThisDevice = InMemoryLocalKeyValueStore()

        RecentSearchesStore(storedOn: onThisDevice).remember("market")

        #expect(RecentSearchesStore(storedOn: onThisDevice).queries == ["market"])
    }

    @Test("nothing is written for a query that changes nothing")
    func rememberingTheSameQueryTwiceWritesOnce() {
        let onThisDevice = InMemoryLocalKeyValueStore()
        let store = RecentSearchesStore(storedOn: onThisDevice)

        store.remember("market")
        store.remember("market")
        store.remember("")

        #expect(onThisDevice.writtenKeys.count == 1)
    }

    @Test("a store over an empty device offers nothing back")
    func aFreshDeviceHasNoRecentSearches() {
        #expect(RecentSearchesStore(storedOn: InMemoryLocalKeyValueStore()).queries.isEmpty)
    }
}
