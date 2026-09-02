import Foundation
import Testing

@testable import AujourCore

private let firstOfMarch = JournalDay(year: 2026, month: 3, day: 1)
private let secondOfMarch = JournalDay(year: 2026, month: 3, day: 2)
private let fourteenthOfMarch = JournalDay(year: 2026, month: 3, day: 14)

/// The words of a journal, and what a query finds in them.
///
/// Everything here is over a Search Index built by hand: what a folder holds
/// and how it is read are ``JournalSearch``'s, and none of that is in the way
/// of stating what "this query matches that day" means.
@Suite("A query over the journal's words")
struct SearchIndexTests {
    @Test("a word somebody wrote finds the day they wrote it")
    func aWordFindsItsDay() {
        let index = SearchIndex([firstOfMarch: "Walked to the market."])

        #expect(index.results(for: "market").map(\.day) == [firstOfMarch])
    }

    @Test("a day nobody used that word on is not a result")
    func aWordNobodyWroteFindsNothing() {
        let index = SearchIndex([firstOfMarch: "Walked to the market."])

        #expect(index.results(for: "mountain").isEmpty)
    }

    @Test("capitals and accents are not what a search is about")
    func matchingIgnoresCaseAndDiacritics() {
        let index = SearchIndex([firstOfMarch: "Coffee at the Café de Flore."])

        #expect(index.results(for: "cafe").map(\.day) == [firstOfMarch])
        #expect(index.results(for: "CAFÉ").map(\.day) == [firstOfMarch])
        #expect(index.results(for: "flore").map(\.day) == [firstOfMarch])
    }

    @Test("a half-typed word finds the words that start with it")
    func aWordIsFoundByItsPrefix() {
        let index = SearchIndex([firstOfMarch: "Walked to the market."])

        #expect(index.results(for: "mark").map(\.day) == [firstOfMarch])
        #expect(index.results(for: "m").map(\.day) == [firstOfMarch])
        // The other way round is not a prefix: a query longer than the word is
        // somebody who meant a different word.
        #expect(index.results(for: "marketplace").isEmpty)
    }

    @Test("two words narrow the search rather than widening it")
    func everyWordOfAQueryMustBePresent() {
        let index = SearchIndex([
            firstOfMarch: "Walked to the market with Robin.",
            secondOfMarch: "Robin came over.",
        ])

        #expect(index.results(for: "market robin").map(\.day) == [firstOfMarch])
        #expect(index.results(for: "robin").map(\.day) == [secondOfMarch, firstOfMarch])
    }

    @Test("the words of a query need not be next to each other")
    func wordsMatchAnywhereInTheDay() {
        let index = SearchIndex([
            firstOfMarch: "Walked to the market.\n\nRobin came over in the evening."
        ])

        #expect(index.results(for: "robin market").map(\.day) == [firstOfMarch])
    }

    @Test("a query with no words in it finds nothing at all")
    func anEmptyQueryFindsNothing() {
        let index = SearchIndex([firstOfMarch: "Walked to the market."])

        #expect(index.results(for: "").isEmpty)
        #expect(index.results(for: "   ").isEmpty)
        // Punctuation is not a word, so this is an empty query too — and a
        // search box holding one must not answer with the whole journal.
        #expect(index.results(for: "**").isEmpty)
    }

    @Test("results are the most recent day first")
    func resultsAreNewestFirst() {
        let index = SearchIndex([
            firstOfMarch: "Rain.",
            fourteenthOfMarch: "Rain again.",
            secondOfMarch: "Rain still.",
        ])

        #expect(
            index.results(for: "rain").map(\.day)
                == [fourteenthOfMarch, secondOfMarch, firstOfMarch]
        )
    }

    @Test("the marks markdown is written with are not words")
    func markdownMarksAreNotIndexed() {
        let index = SearchIndex([
            firstOfMarch: "# Monday\n\n- [x] Walked to the **market**\n- [[2026-03-02]]\n"
        ])

        // The word inside the marks is the word that was written.
        #expect(index.results(for: "market").map(\.day) == [firstOfMarch])
        #expect(index.results(for: "monday").map(\.day) == [firstOfMarch])
        // And the marks themselves are nobody's search.
        #expect(index.results(for: "#").isEmpty)
        #expect(index.results(for: "[[").isEmpty)
    }

    @Test("a query matching the whole journal answers with the recent end of it")
    func aQueryMatchingEverythingIsBounded() {
        let everyDay = (1...400).map { JournalDay(year: 2026, month: 1, day: 1).adding(days: $0) }
        let index = SearchIndex(
            Dictionary(uniqueKeysWithValues: everyDay.map { ($0, "Rain.") })
        )

        let results = index.results(for: "rain")

        #expect(results.count == SearchIndex.mostResults)
        // The recent end of it, which is the end somebody is looking in.
        #expect(results.first?.day == everyDay.last)
    }

    // MARK: - What a result shows

    @Test("a result carries the line the word was written on")
    func theExcerptIsTheLineTheMatchIsOn() {
        let index = SearchIndex([
            firstOfMarch: "# Monday\n\nWalked to the market.\n\nRained later.\n"
        ])

        #expect(index.results(for: "market").first?.excerpt == "Walked to the market.")
    }

    @Test("a long line is shown around the word rather than from its start")
    func aLongLineIsWindowedAroundTheMatch() throws {
        let padding = String(repeating: "a walk in the rain, ", count: 30)
        let index = SearchIndex([firstOfMarch: padding + "and then the market."])

        let excerpt = try #require(index.results(for: "market").first?.excerpt)
        #expect(excerpt.contains("market"))
        #expect(excerpt.count <= 200)
        // Cut at the front, so the words around the match are the ones shown.
        #expect(excerpt.hasPrefix("…"))
    }

    @Test("an excerpt is the day's own characters, not a rewriting of them")
    func theExcerptKeepsWhatWasTyped() {
        let index = SearchIndex([firstOfMarch: "  Café **au lait** at 8am.  \n"])

        // Trimmed at the ends, because leading spaces in a list of results are
        // a ragged list — and untouched everywhere else, marks included.
        #expect(index.results(for: "lait").first?.excerpt == "Café **au lait** at 8am.")
    }

    // MARK: - The words the query matched

    @Test("a result says which of the excerpt's words the query matched")
    func aResultMarksTheWordItWasFoundBy() throws {
        let index = SearchIndex([firstOfMarch: "Walked to the market with Robin."])

        #expect(try marked(in: index.results(for: "market")) == ["market"])
    }

    @Test("a half-typed query marks the whole word it found")
    func aPrefixMarksTheWordItStarts() throws {
        let index = SearchIndex([firstOfMarch: "Walked to the market."])

        #expect(try marked(in: index.results(for: "mark")) == ["market"])
    }

    @Test("every word of the query is marked, wherever on the line it landed")
    func eachWordOfAQueryIsMarked() throws {
        let index = SearchIndex([firstOfMarch: "Robin walked to the market."])

        #expect(try marked(in: index.results(for: "market robin")) == ["Robin", "market"])
    }

    @Test("a word written twice on the line is marked both times")
    func aWordIsMarkedEveryTimeItAppears() throws {
        let index = SearchIndex([firstOfMarch: "To the market, and back from the market."])

        #expect(try marked(in: index.results(for: "market")) == ["market", "market"])
    }

    @Test("a word is marked as it was written, not as it was searched for")
    func markingKeepsTheDaysOwnSpelling() throws {
        let index = SearchIndex([firstOfMarch: "Coffee at the Café de Flore."])

        #expect(try marked(in: index.results(for: "CAFE")) == ["Café"])
    }

    @Test("what was not searched for is left alone, and the line still reads")
    func theRunsAreTheWholeExcerptInOrder() throws {
        let index = SearchIndex([firstOfMarch: "Walked to the market."])

        let result = try #require(index.results(for: "market").first)
        #expect(result.runs.map(\.text) == ["Walked to the ", "market", "."])
        #expect(result.runs.map(\.isMarked) == [false, true, false])
    }

    @Test("a mark lands on the excerpt, not on the line it was cut out of")
    func marksAreInTheExcerptsOwnCharacters() throws {
        let padding = String(repeating: "a walk in the rain, ", count: 30)
        let index = SearchIndex([firstOfMarch: padding + "and then the market."])

        let result = try #require(index.results(for: "market").first)
        // The excerpt is cut at the front and carries an ellipsis, so a range
        // measured against the whole day would name the wrong characters.
        #expect(result.excerpt.hasPrefix("…"))
        #expect(result.runs.filter(\.isMarked).map(\.text) == ["market"])
        #expect(result.runs.map(\.text).joined() == result.excerpt)
    }

    @Test("an excerpt with nothing marked in it is one run of its own words")
    func anUnmarkedExcerptIsOneRun() {
        let result = SearchResult(day: firstOfMarch, excerpt: "Walked to the market.")

        #expect(result.runs.map(\.text) == ["Walked to the market."])
        #expect(result.runs.allSatisfy { !$0.isMarked })
    }

    /// The words a query marked in the first result, in the order they are
    /// written — what a row draws in the accent.
    private func marked(in results: [SearchResult]) throws -> [String] {
        try #require(results.first).runs.filter(\.isMarked).map(\.text)
    }

    // MARK: - Keeping up with the folder

    @Test("indexing a day again is what that day says now")
    func indexingADayAgainReplacesIt() {
        var index = SearchIndex([firstOfMarch: "Walked to the market."])

        index.index("Stayed in.", for: firstOfMarch)

        #expect(index.results(for: "market").isEmpty)
        #expect(index.results(for: "stayed").map(\.day) == [firstOfMarch])
    }

    @Test("a day forgotten is a day no query finds")
    func aForgottenDayIsGone() {
        var index = SearchIndex([
            firstOfMarch: "Walked to the market.",
            secondOfMarch: "Back to the market.",
        ])

        index.forget(firstOfMarch)

        #expect(index.results(for: "market").map(\.day) == [secondOfMarch])
        #expect(index.results(for: "walked").isEmpty)
    }

    // MARK: - Written down and read back

    @Test("an index written down and read back finds what it found before")
    func theIndexSurvivesBeingWrittenDown() throws {
        let index = SearchIndex([
            firstOfMarch: "# Monday\n\nWalked to the Café de Flore.",
            fourteenthOfMarch: "Rained all day.",
        ])

        let read = try #require(SearchIndex(decoding: index.encoded()))

        #expect(read == index)
        #expect(read.results(for: "cafe").map(\.day) == [firstOfMarch])
        #expect(read.results(for: "cafe").first?.excerpt == "Walked to the Café de Flore.")
        #expect(read.results(for: "rain").map(\.day) == [fourteenthOfMarch])
    }

    @Test("bytes that are not an index at all are no index, not a crash")
    func rubbishDecodesToNothing() {
        #expect(SearchIndex(decoding: Data("not an index".utf8)) == nil)
        #expect(SearchIndex(decoding: Data()) == nil)
    }

    @Test("an index of nothing is empty, and stays empty through a round trip")
    func anEmptyIndexRoundTrips() throws {
        let index = SearchIndex()

        #expect(index.isEmpty)
        #expect(try #require(SearchIndex(decoding: index.encoded())).isEmpty)
    }
}
