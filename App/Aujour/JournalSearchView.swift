import SwiftUI
import AujourCore

/// The Journal by something written in it: a word, and the days that hold it.
///
/// The screen holds no rules. Which days match, in what order, and what of
/// each one is worth showing are all ``JournalSearch``'s — including the one
/// this screen exists for, that results come from a reading of the folder and
/// nothing else, so a day written in Obsidian is a day this finds (ADR 0001).
///
/// A day is opened here exactly as it is from the calendar, and comes back the
/// same way: what was typed into it is saved, and that one day is read again,
/// so a word added to a day a search led to is a word the next search finds.
struct JournalSearchView: View {
    let search: JournalSearch

    /// The Journal the search is over, for the one thing opening a day needs
    /// that a result does not carry: the editor over that day's file.
    let journal: Journal

    @State private var query = ""

    /// The day being written in, pushed on top of the results — nil while the
    /// list is what is on screen.
    @State private var opened: OpenedDay?

    @Environment(\.scenePhase) private var scenePhase

    private var results: [SearchResult] {
        search.results(for: query)
    }

    var body: some View {
        List(results) { result in
            SearchResultRow(result: result) { open(result.day) }
        }
        .listStyle(.plain)
        .overlay {
            // Over the list rather than in place of it, so that what is on
            // screen while somebody types is the list they are narrowing.
            if results.isEmpty { nothingToShow }
        }
        .safeAreaInset(edge: .bottom) {
            if let problem = search.problem {
                SearchProblemNotice(problem: StorageProblem(problem))
                    .padding(.horizontal, 12)
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search your journal"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { opened in
            EntryView(
                editor: opened.editor,
                photographsFrom: journal.photoLibrary,
                placesFrom: journal.places
            )
            .parkedFilesNotice(from: journal, for: opened.day)
            // With its year: a day reached from a search can be years back,
            // and every February has a 14th.
            .navigationTitle(opened.day.spelledOut(withYear: true))
            .navigationBarTitleDisplayMode(.inline)
        }
        // Read on the way in rather than remembered: what a search finds is a
        // reading of the folder, so this is where one happens (ADR 0001). What
        // was written down last time is on screen while it does.
        .task { await search.open() }
        .onChange(of: opened) { left, arrived in
            // Back from a day: whatever was typed into it has a moment to
            // land, and then that one day is read again — which is what makes
            // a word just written findable, without reading the whole journal
            // every time somebody leaves a day.
            guard arrived == nil, let left else { return }
            Task {
                await left.editor.save()
                await search.reindex(left.day)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive, .background:
                // The same last chance today's Entry gets: a day being written
                // in when the app goes away has no next second to be saved in.
                guard let opened else { return }
                Task { await opened.editor.save() }
            case .active:
                // Coming back to a search box that is still on screen: the
                // folder may have been written in by Obsidian, or by another
                // device, while nothing here was looking. Only when the list
                // is what is on screen — a day being written in is read again
                // on the way back out of it.
                guard opened == nil else { return }
                Task { await search.reindex() }
            @unknown default:
                break
            }
        }
    }

    /// What stands where the results would be. Three different things, because
    /// an empty list means three different things here — and a journal that
    /// looks like it holds nothing is the one thing this screen must never say
    /// when it holds a decade (ADR 0001).
    @ViewBuilder
    private var nothingToShow: some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("Search your journal", systemImage: "magnifyingglass")
                    .accessibilityIdentifier("searchPrompt")
            } description: {
                Text("Find a day by something you wrote in it.")
            }
        } else if search.isReading && search.hasNothingIndexed {
            // Nothing indexed *and* still reading: a first search, before the
            // folder has answered. Saying "no results" here would be saying it
            // about a journal nobody has looked in yet.
            ProgressView("Reading your journal")
                .accessibilityIdentifier("readingTheJournal")
        } else {
            ContentUnavailableView {
                Label("No entries found", systemImage: "magnifyingglass")
                    .accessibilityIdentifier("noSearchResults")
            } description: {
                Text("No day in your journal has “\(query)” in it.")
            }
        }
    }

    private func open(_ day: JournalDay) {
        // A search only ever finds days with a file, so there is nothing to
        // spawn here — this is the editor over words that are already written.
        guard let editor = journal.editor(for: day) else { return }
        opened = OpenedDay(day: day, editor: editor)
        Task {
            // Before it is read, for the same reason today's Entry is: a day
            // reached from a search can have been written on two devices, and
            // the version that loses its path is set aside rather than left in
            // iCloud where nobody would ever see it.
            await journal.settleAnyDivergence(before: editor)
            await editor.open()
        }
    }
}

/// One day a search found: which day it was, and the words of it that matched.
private struct SearchResultRow: View {
    let result: SearchResult
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.day.spelledOut(withYear: true))
                    .font(.subheadline.weight(.semibold))
                Text(result.excerpt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // One element rather than two pieces of text: a result is a day, and
        // the words are what it is being offered for.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("searchResult-\(result.day)")
        .accessibilityLabel(result.day.spelledOut(withYear: true))
        .accessibilityValue(result.excerpt)
    }
}

/// A folder that could not be read, said under the results.
///
/// Under them rather than in place of them: what was read last time is still
/// on screen and still worth searching, and this is what says it may be behind
/// (ADR 0001).
private struct SearchProblemNotice: View {
    let problem: StorageProblem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aujour couldn't read your journal folder, so a day you've written recently may not be found.")
                    .font(.footnote.weight(.semibold))
                Text(problem.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("searchProblem")
    }
}

// Previews search a journal in memory, so what the list shows is the days the
// preview is named after rather than whatever this Mac's journal folder holds.
#Preview("A word found in a few days") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let written = [
        today.adding(days: -1): "# Yesterday\n\nWalked to the market with Robin.\n",
        today.adding(days: -9): "Rained all day, so the market was a washout.\n",
        today.adding(days: -40): "Coffee at the Café de Flore.\n",
    ]

    NavigationStack {
        JournalSearchView(
            search: JournalSearch(
                store: InMemoryJournalStore(
                    Dictionary(
                        uniqueKeysWithValues: written.map {
                            (PathTemplate.default.render($0.key), $0.value)
                        }
                    )
                )
            ),
            journal: Journal.inAPreview(over: .preview(.onThisDevice))
        )
    }
}

#Preview("A journal nobody has written in") {
    NavigationStack {
        JournalSearchView(
            search: JournalSearch(store: InMemoryJournalStore()),
            journal: Journal.inAPreview(over: .preview(.onThisDevice))
        )
    }
}
