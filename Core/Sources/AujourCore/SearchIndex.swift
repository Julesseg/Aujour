import Foundation

/// One day a query matched, as a list of results draws it.
public struct SearchResult: Hashable, Sendable, Identifiable {
    /// The day whose Entry matched — which is the Entry's identity, and so the
    /// whole of what opening a result needs.
    public let day: JournalDay

    /// A stretch of that day's own text with the match in it, for the row to
    /// show. The characters the user typed, exactly as they typed them: an
    /// excerpt that had been tidied would be a day they could not recognise.
    public let excerpt: String

    /// Where in ``excerpt`` the query's own words are — measured against the
    /// excerpt and never against the day it was cut out of, because a cut line
    /// carries an ellipsis and every index after it would be off by one.
    public let marked: [Range<String.Index>]

    public var id: JournalDay { day }

    public init(day: JournalDay, excerpt: String, marked: [Range<String.Index>] = []) {
        self.day = day
        self.excerpt = excerpt
        self.marked = marked
    }

    /// One stretch of an excerpt, and whether it is one of the words the query
    /// was answered on.
    public struct Run: Hashable, Sendable {
        public let text: String

        /// Whether this is a word the query matched — the run a row draws in
        /// the accent rather than in ink.
        public let isMarked: Bool
    }

    /// The excerpt cut into runs, in the order it reads: the words the query
    /// matched, and everything between them.
    ///
    /// Here rather than in the row that draws it, because it is arithmetic on
    /// string indices and a screen that got it wrong would mark the wrong
    /// characters — the one mistake in this whole feature that looks like the
    /// search itself having found the wrong thing. What is left for the screen
    /// is which of two colours a run is drawn in.
    ///
    /// Always the whole excerpt, so joining the runs back up gives the line
    /// exactly as it was written.
    public var runs: [Run] {
        var runs: [Run] = []
        var at = excerpt.startIndex
        for mark in marked where mark.lowerBound >= at {
            if at < mark.lowerBound {
                runs.append(Run(text: String(excerpt[at..<mark.lowerBound]), isMarked: false))
            }
            runs.append(Run(text: String(excerpt[mark]), isMarked: true))
            at = mark.upperBound
        }
        if at < excerpt.endIndex {
            runs.append(Run(text: String(excerpt[at...]), isMarked: false))
        }
        return runs
    }
}

/// The journal's words, kept where a query can reach them without opening the
/// folder.
///
/// A disposable cache in ADR 0001's sense, and the plainest kind: it holds the
/// text of each day's Entry and nothing that is not already in a file. Delete
/// it and nothing is lost — ``JournalSearch`` builds another by reading the
/// Journal Root, which is the only way one is ever built. There is no state
/// here to fall out of step with the folder, because there is nothing here the
/// folder does not say.
///
/// It keeps the text rather than only the words because an excerpt is most of
/// what a result *is*: finding the line a match sits on needs the characters,
/// not a list of the words in them. What that buys is a query answered between
/// two keystrokes — no file read, no folder listed, nothing to wait for.
///
/// The words are what matching is done on, and they are deliberately blunt:
/// a run of letters or digits, folded so that capitals and accents are not
/// what a search is about. Everything else falls away, which is what makes
/// `**market**` and `market` the same word to look for and the marks around it
/// nobody's query. A query's words all have to be present, each matching from
/// the start of a word, so that a half-typed search narrows as it is typed
/// rather than widening.
public struct SearchIndex: Equatable, Sendable {
    /// What each indexed day says.
    private var entries: [JournalDay: String] = [:]

    /// Which days hold each word. Derived from `entries` — kept beside it
    /// rather than worked out per query, because a query is answered while
    /// somebody is typing and re-reading the whole journal at every keystroke
    /// is the one thing this exists not to do.
    private var days: [String: Set<JournalDay>] = [:]

    public init() {}

    /// An index over days already read — the shape a scan builds one in, and
    /// what a test states a journal as.
    public init(_ entries: [JournalDay: String]) {
        for (day, text) in entries {
            index(text, for: day)
        }
    }

    /// Whether anything has been indexed at all. An empty index is what a
    /// first launch has, and what a deleted cache leaves behind.
    public var isEmpty: Bool { entries.isEmpty }

    /// Takes in what a day says, replacing whatever it said before.
    ///
    /// Replacing rather than adding, because an Entry rewritten in Obsidian is
    /// not the old one plus the new: a word taken out of a day has to stop
    /// being found there, or the index would only ever grow away from the
    /// folder.
    public mutating func index(_ text: String, for day: JournalDay) {
        forget(day)
        entries[day] = text
        for word in SearchWords.words(in: text) {
            days[word.word, default: []].insert(day)
        }
    }

    /// Drops a day, for one whose file is no longer there.
    public mutating func forget(_ day: JournalDay) {
        guard let text = entries.removeValue(forKey: day) else { return }
        for word in SearchWords.words(in: text) {
            days[word.word]?.remove(day)
            // A word no day holds is a word gone, not a word with nothing
            // under it: what is left has to be exactly what a fresh scan of
            // the same folder would build, or two equal journals would give
            // two unequal indexes.
            if days[word.word]?.isEmpty == true {
                days[word.word] = nil
            }
        }
    }

    /// The days matching a query, most recent first.
    ///
    /// Most recent first because a journal is read backwards: the day somebody
    /// is looking for is far more often last month's than the one five years
    /// ago that happens to sort first.
    ///
    /// A query with no words in it — empty, spaces, punctuation somebody typed
    /// by accident — matches nothing rather than everything. An empty search
    /// box is not a request to see the whole journal.
    ///
    /// The most recent ``mostResults`` of them, because a query is answered
    /// between two keystrokes and finding the line each match sits on costs a
    /// pass over that day. A query matching a decade — `the`, or a single
    /// letter — is one to narrow rather than a list to read, and reading every
    /// day of a journal to build results nobody scrolls to is the one way this
    /// stops being instant.
    public func results(for query: String) -> [SearchResult] {
        let wanted = SearchWords.words(in: query).map(\.word)
        guard !wanted.isEmpty else { return [] }

        var matched: Set<JournalDay>?
        for word in wanted {
            var holdingThisWord: Set<JournalDay> = []
            for (indexed, holders) in days where indexed.hasPrefix(word) {
                holdingThisWord.formUnion(holders)
            }
            // Narrowed word by word: every word of the query has to be
            // somewhere in the day, though nowhere near the others.
            matched = matched?.intersection(holdingThisWord) ?? holdingThisWord
            if matched?.isEmpty ?? true { return [] }
        }

        return (matched ?? []).sorted(by: >).prefix(Self.mostResults).compactMap { day in
            guard let text = entries[day],
                let firstMatch = Self.firstMatch(in: text, of: wanted)
            else { return nil }
            let excerpt = Self.excerpt(from: text, around: firstMatch)
            return SearchResult(
                day: day,
                excerpt: excerpt,
                // Found again in the excerpt rather than carried over from the
                // day: the excerpt is a cut of that line with an ellipsis on
                // the front of it, and a range measured against the whole text
                // would name characters this row is not showing.
                marked: SearchWords.marks(in: excerpt, of: wanted)
            )
        }
    }

    /// How many days one query answers with.
    public static let mostResults = 200

    /// Where in a day's text the first of the query's words was written —
    /// which is the piece of the day a result shows.
    private static func firstMatch(
        in text: String,
        of wanted: [String]
    ) -> Range<String.Index>? {
        SearchWords.words(in: text)
            .first { word in wanted.contains { word.word.hasPrefix($0) } }?
            .range
    }

    /// How much of a day one result shows.
    private static let excerptLength = 160

    /// Roughly how much of the line before the match is worth keeping, for a
    /// match far enough into a paragraph that the line has to be cut.
    private static let excerptLeadIn = 40

    /// The stretch of a day a result shows: the line the match is on, cut down
    /// around the match if that line is a paragraph.
    ///
    /// A line, because a line is what somebody wrote as one thought — a heading,
    /// a bullet, a sentence. Cut around the match rather than from the start,
    /// because the words either side of the one searched for are the whole
    /// reason for showing any.
    private static func excerpt(
        from text: String,
        around match: Range<String.Index>
    ) -> String {
        var start =
            text[..<match.lowerBound].lastIndex(where: \.isNewline)
            .map(text.index(after:)) ?? text.startIndex
        var end = text[match.upperBound...].firstIndex(where: \.isNewline) ?? text.endIndex

        // Ragged ends make a ragged list, and the space before a line is not
        // part of what it says.
        while start < match.lowerBound, text[start].isWhitespace {
            start = text.index(after: start)
        }
        while end > match.upperBound, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }

        guard text.distance(from: start, to: end) > excerptLength else {
            return String(text[start..<end])
        }

        let from =
            text.index(match.lowerBound, offsetBy: -excerptLeadIn, limitedBy: start) ?? start
        let to = text.index(from, offsetBy: excerptLength, limitedBy: end) ?? end
        // An ellipsis wherever characters were left out, so a cut line reads
        // as one rather than as a day that starts mid-word.
        return (from > start ? "…" : "") + text[from..<to] + (to < end ? "…" : "")
    }
}

// MARK: - Written down and read back

extension SearchIndex: Codable {
    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let written = try container.decode([String: String].self, forKey: .entries)
        self.init()
        for (day, text) in written {
            // A key that names no day is skipped rather than thrown over: this
            // is a cache, and the worst an unreadable line in one can be
            // allowed to cost is the day it was about.
            guard let day = JournalDay(day) else { continue }
            index(text, for: day)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Only the days and their text: the words are worked out again on the
        // way back in, because writing them down would be writing the same
        // journal twice and leaving two things to disagree.
        var written: [String: String] = [:]
        for (day, text) in entries {
            written[day.description] = text
        }
        try container.encode(written, forKey: .entries)
    }

    /// The index as bytes, for whatever the app keeps a disposable cache in.
    ///
    /// The format is decided here rather than by the caller, so that the thing
    /// that writes it and the thing that reads it cannot drift apart. Bytes
    /// this cannot produce would be a cache not written, which costs a scan
    /// and nothing else — so there is nothing here for a caller to handle.
    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// An index read back from bytes, or `nil` for bytes that are not one.
    ///
    /// `nil` rather than a throw for the same reason: a cache that cannot be
    /// read is a cache that is not there, and what happens next is a scan
    /// either way.
    public init?(decoding data: Data) {
        guard let decoded = try? JSONDecoder().decode(SearchIndex.self, from: data) else {
            return nil
        }
        self = decoded
    }
}

// MARK: - Words

/// What the index counts as a word, in the one place that decides it.
///
/// Deliberately blunt: a run of letters or digits, folded so that neither case
/// nor accents are what a search is about. Everything between those runs —
/// markdown's marks, punctuation, whitespace — is a boundary and nothing else,
/// which is what makes the word inside `**market**` the word that was written
/// and the asterisks nobody's query.
///
/// It does mean a script written without spaces indexes a run of it as one
/// word. Prefix matching is what makes that usable rather than useless, and a
/// tokenizer that knew better would be a language's rules in Core.
enum SearchWords {
    /// One word of a text, and where it was written.
    struct Word {
        /// The word as the index matches it: folded, and never shown to
        /// anybody.
        let word: String

        /// Where it sits in the text it came from — what an excerpt is built
        /// around, and why folding happens per word rather than over the whole
        /// text, which would move every index in it.
        let range: Range<String.Index>
    }

    /// Where in a text the words of a query are — every run of it that one of
    /// them starts, in the order they are written.
    ///
    /// The same match a query is answered by, asked of a line rather than of a
    /// journal: a word is marked when one of the query's words is a prefix of
    /// it, folded the same way, so the mark falls on `Café` for `CAFE` and on
    /// the whole of `market` for `mark`.
    static func marks(in text: String, of wanted: [String]) -> [Range<String.Index>] {
        words(in: text)
            .filter { word in wanted.contains { word.word.hasPrefix($0) } }
            .map(\.range)
    }

    static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        var at = text.startIndex

        while at < text.endIndex {
            if text[at].isLetter || text[at].isNumber {
                if start == nil { start = at }
            } else if let from = start {
                words.append(Word(word: folded(text[from..<at]), range: from..<at))
                start = nil
            }
            at = text.index(after: at)
        }
        if let from = start {
            words.append(Word(word: folded(text[from...]), range: from..<text.endIndex))
        }
        return words
    }

    /// A word as it is matched: `Café` and `CAFE` and `cafe` are one word, in
    /// a journal where the accent is a keyboard away and a search is not a
    /// spelling test.
    private static func folded(_ word: Substring) -> String {
        word.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }
}
