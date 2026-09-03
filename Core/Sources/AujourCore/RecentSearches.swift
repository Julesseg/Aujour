import Foundation

/// The queries somebody has already searched their journal with, most recent
/// first.
///
/// What an empty search box has to offer. A journal is searched for the same
/// handful of things — a person, a place, a project — and typing one of them
/// again is the commonest thing anybody does in this screen.
///
/// Two of them are the same search when they are the same *words*, folded the
/// way matching folds them (``SearchWords``): `Café de Flore` and
/// `cafe de flore` find exactly the same days, so offering both back would be
/// offering one query twice. What is kept is the spelling just typed, because
/// that is the one they last chose to write.
///
/// A query with no words in it is not remembered at all — an empty box, a
/// stray space, a piece of punctuation. Those find nothing, and a list of
/// things that find nothing is not a list worth tapping.
public struct RecentSearches: Equatable, Sendable {
    /// The queries, most recent first — exactly as they were typed.
    public private(set) var queries: [String]

    /// How many are kept. A handful, because this is a shortcut and not a
    /// history: a list long enough to scroll is one to read rather than one to
    /// tap, and the query somebody wants back is nearly always the last one.
    public static let mostKept = 6

    public init(_ queries: [String] = []) {
        self.queries = Array(queries.prefix(Self.mostKept))
    }

    /// Takes in a query somebody searched with.
    public mutating func remember(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = Self.words(of: query)
        guard !words.isEmpty else { return }

        queries.removeAll { Self.words(of: $0) == words }
        queries.insert(query, at: 0)
        queries = Array(queries.prefix(Self.mostKept))
    }

    /// What makes two queries one search: the words they would be matched on.
    private static func words(of query: String) -> [String] {
        SearchWords.words(in: query).map(\.word)
    }
}

// MARK: - Written down and read back

extension RecentSearches {
    /// The queries as one string, for the bag of strings this device keeps its
    /// own settings in.
    ///
    /// The format is decided here rather than by the caller, so that the thing
    /// that writes it and the thing that reads it cannot drift apart.
    public func encoded() -> String {
        guard let written = try? JSONEncoder().encode(queries) else { return "[]" }
        return String(decoding: written, as: UTF8.self)
    }

    /// The queries read back, or none at all for something that is not a list
    /// of them.
    ///
    /// None rather than a throw: what is lost is a shortcut, and an empty
    /// search box that offers nothing is exactly what a fresh device has.
    public init(decoding written: String?) {
        guard let written,
            let read = try? JSONDecoder().decode([String].self, from: Data(written.utf8))
        else {
            self.init()
            return
        }
        self.init(read)
    }
}

/// Keeps those queries on this device.
///
/// A `LocalKeyValueStore` and deliberately not the synced one (ADR 0003):
/// what somebody looked for on their phone is not a fact about the journal,
/// nothing here shapes a file in the folder, and a search made on the iPad is
/// not one this device made.
///
/// Not a disposable cache either, which is why it is not kept beside the
/// Search Index: the index is a reading of the folder and rebuilding it costs
/// only time, while a query nobody wrote down is a query gone.
@MainActor
public final class RecentSearchesStore {
    private let store: any LocalKeyValueStore
    private var kept: RecentSearches

    /// - Parameter store: on-device storage — `UserDefaults` in the app, a
    ///   fake in tests. Never the synced seam.
    public init(storedOn store: any LocalKeyValueStore) {
        self.store = store
        self.kept = RecentSearches(decoding: store.string(forKey: Self.key))
    }

    /// What to offer an empty search box, most recent first.
    public var queries: [String] { kept.queries }

    /// Takes in a query somebody searched with, and writes it down.
    ///
    /// Written only when something changed, so that searching twice with the
    /// query already at the front costs nothing.
    public func remember(_ query: String) {
        let before = kept
        kept.remember(query)
        guard kept != before else { return }
        store.setString(kept.encoded(), forKey: Self.key)
    }

    private static let key = "aujour.device.recentSearches"
}
