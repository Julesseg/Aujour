import SwiftUI
import AujourCore

/// The Journal by something written in it: a word, and the days that hold it.
///
/// The screen holds no rules. Which days match, in what order, what of each one
/// is worth showing and which of its words the query marked are all
/// ``JournalSearch``'s — including the one this screen exists for, that results
/// come from a reading of the folder and nothing else, so a day written in
/// Obsidian is a day this finds (ADR 0001).
///
/// A sheet rather than a page pushed on top of today's, because that is what
/// this is: a way of reaching back into the journal, held in front of the day
/// somebody is writing rather than in place of it. It wears the chrome every
/// other sheet in the app does — the paper, the corner and the grabber — and
/// rises out of the button that summoned it.
///
/// A day is opened here exactly as it is from the calendar, and comes back the
/// same way: what was typed into it is saved, and that one day is read again,
/// so a word added to a day a search led to is a word the next search finds.
struct JournalSearchSheet: View {
    let search: JournalSearch

    /// The Journal the search is over, for the one thing opening a day needs
    /// that a result does not carry: the editor over that day's file.
    let journal: Journal

    /// The one colour the app spends on itself, handed down rather than read
    /// out of the environment for the reason the date pill's is: the screen
    /// above already has it, and a day opened from here can have as much to
    /// say for itself as today's does. It is also what a matched word is
    /// marked in.
    let accent: Accent

    @State private var query = ""

    /// The day being written in, pushed on top of the results — nil while the
    /// list is what is on screen.
    @State private var opened: OpenedDay?

    /// Whether the query is being typed. Held so that the box is ready the
    /// moment the sheet is up: a search sheet that has to be tapped before it
    /// can be typed into is one tap somebody makes every single time.
    @FocusState private var typing: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.comfortable) {
                SearchField(query: $query, typing: $typing)
                // Asked once and handed down, rather than read again by every
                // piece of the screen that has something to say about it: a
                // query is answered while somebody is typing, and four
                // readings of the journal per keystroke is four times what
                // this costs.
                whatThereIsToShow(search.results(for: query))
            }
            .padding(.horizontal, Spacing.apart)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom) {
                if let problem = search.problem {
                    SearchProblemNotice(problem: StorageProblem(problem))
                        .padding(.horizontal, Spacing.apart)
                }
            }
            // No title, because the box under the bar already says what this
            // is. A sheet naming itself over a field prompting for the same
            // thing is the screen saying it twice.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // The way out, as every other sheet in the app has one.
                    // The grabber above it drags the same sheet away; this is
                    // the one that can be reached without a gesture.
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeSearch")
                }
            }
            .navigationDestination(item: $opened) { opened in
                EntryView(
                    editor: opened.editor,
                    photographsFrom: journal.photoLibrary,
                    placesFrom: journal.places
                )
                .parkedFilesNotice(from: journal, for: opened.day, in: accent)
                // With its year: a day reached from a search can be years back,
                // and every February has a 14th.
                .navigationTitle(opened.day.spelledOut(withYear: true))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        // Full height rather than half, for the settings sheet's reason and
        // one of its own: a list of days is as long as the journal, and the
        // day opened out of one is pushed onto this stack to be written in.
        .presentationDetents([.large])
        // Read on the way in rather than remembered: what a search finds is a
        // reading of the folder, so this is where one happens (ADR 0001). What
        // was written down last time is on screen while it does.
        .task {
            typing = true
            await search.open()
        }
        .onChange(of: opened) { left, arrived in
            // Back from a day: whatever was typed into it has a moment to
            // land, and then that one day is read again — which is what makes
            // a word just written findable, without reading the whole journal
            // every time somebody leaves a day.
            guard arrived == nil, let left else { return }
            settle(left)
        }
        .onDisappear {
            // The other way out of a day opened here, and one a pushed screen
            // did not have: the whole sheet dragged away with the day still on
            // top of it. Nothing sets `opened` back to nil on that path, so
            // without this the words would be left to the autosave alone and
            // the day would not be read again at all.
            guard let opened else { return }
            settle(opened)
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

    /// What is under the box. Six things, because there are five ways to have
    /// nothing to show and only one to have something — and a journal that
    /// looks like it holds nothing is the one thing this screen must never say
    /// when it holds a decade (ADR 0001).
    @ViewBuilder
    private func whatThereIsToShow(_ results: [SearchResult]) -> some View {
        if search.isAJournalNobodyHasWrittenIn {
            // First, and whatever has been typed: there is no query a journal
            // with no days in it could answer, and "no day has that in it"
            // over a folder that has nothing in it at all is the app answering
            // a question nobody could have meant to ask. Only ever said about
            // a folder that *has been read* and found empty — which is
            // `JournalSearch`'s to decide, not this screen's.
            EmptyState(
                symbol: "magnifyingglass",
                line: "Nothing to search yet",
                sentence: """
                    Write a day or two and this is how you find them again — \
                    by a word, a name, anything you wrote.
                    """,
                identifier: "nothingToSearchYet"
            )
        } else if query.isEmpty, !search.recentQueries.isEmpty {
            // What an empty box is worth more than a sentence: the searches
            // already made. A journal is looked in for the same handful of
            // things, and one of them is a tap rather than a word retyped.
            RecentQueries(queries: search.recentQueries) { query = $0 }
        } else if query.isEmpty {
            // Not an Empty State, and drawn as one on purpose: the journal may
            // be a decade deep and this is only the field waiting to be typed
            // in. They share one slot, and a screen that changed voice between
            // one keystroke and the next would be two screens.
            EmptyState(
                symbol: "magnifyingglass",
                line: "Search your journal",
                sentence: "Find a day by something you wrote in it.",
                identifier: "searchPrompt"
            )
        } else if search.isReading && search.hasNothingIndexed {
            // Nothing indexed *and* still reading: a first search, before the
            // folder has answered. Saying "no results" here would be saying it
            // about a journal nobody has looked in yet.
            //
            // A spinner, and never one of the sentences above. A folder still
            // being read looks exactly like a journal nobody has written in,
            // and the identity is not licence to start drawing the two the
            // same way (ADR 0001) — so this takes the identity's face and none
            // of its empty-state shape.
            ProgressView("Reading your journal")
                .lettering(.note)
                .foregroundStyle(Palette.inkMutedColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("readingTheJournal")
        } else if results.isEmpty {
            EmptyState(
                symbol: "magnifyingglass",
                line: "No entries found",
                sentence: "No day in your journal has “\(query)” in it.",
                identifier: "noSearchResults"
            )
        } else {
            daysThatSayIt(results)
        }
    }

    /// The days the query found, most recent first.
    ///
    /// Rows on the sheet's own paper with a hairline between them, rather than
    /// a `List`: a list would bring the system's grouped ground, its own
    /// separator grey and its own insets onto a sheet cut from paper, which is
    /// three ways of looking like somebody else's app at once.
    private func daysThatSayIt(_ results: [SearchResult]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SectionHeader(results.count == 1 ? "1 entry" : "\(results.count) entries")
                    .padding(.bottom, Spacing.close)
                    .accessibilityIdentifier("searchResultCount")

                ForEach(results) { result in
                    Hairline()
                    SearchResultRow(result: result, accent: accent) { open(result.day) }
                        .padding(.vertical, Spacing.comfortable)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The box stays where it is while the list moves under it, and the
        // keyboard goes when somebody starts reading rather than typing.
        .scrollDismissesKeyboard(.immediately)
    }

    /// Puts a day that has been written in back where the next search can
    /// find it: the words saved, and that one day read again.
    ///
    /// Detached from the view on purpose — one of the two ways this is reached
    /// is the sheet going away, and work that stopped when the screen did
    /// would be a day saved only when somebody left it the tidy way.
    private func settle(_ day: OpenedDay) {
        Task {
            await day.editor.save()
            await search.reindex(day.day)
        }
    }

    private func open(_ day: JournalDay) {
        // A search only ever finds days with a file, so there is nothing to
        // spawn here — this is the editor over words that are already written.
        guard let editor = journal.editor(for: day) else { return }
        // Written down here rather than as the query is typed: a search
        // narrows keystroke by keystroke, and a day opened is the one moment
        // the query is known to be the one somebody meant.
        search.remember(query)
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

/// The box a query is typed into.
///
/// The identity's own rather than `.searchable`, which draws the system's
/// search bar in the navigation bar's drawer: a grey field with a grey
/// magnifier is exactly the piece of somebody else's app this sheet is here
/// to stop looking like. What it keeps is everything about a search box that
/// is behaviour — no autocorrection and no capitals, because a journal is full
/// of names no dictionary has and a query is not a sentence.
private struct SearchField: View {
    @Binding var query: String
    @FocusState.Binding var typing: Bool

    var body: some View {
        HStack(spacing: Spacing.close) {
            // A marker rather than a word, and held to the marker floor it is
            // one of (ADR 0006).
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.inkFaintColor)
                .accessibilityHidden(true)

            TextField("Search your journal", text: $query)
                .lettering(.rowLabel)
                .foregroundStyle(Palette.inkColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($typing)
                .accessibilityIdentifier("searchQuery")

            if !query.isEmpty {
                Button {
                    query = ""
                    typing = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkFaintColor)
                }
                .accessibilityLabel("Clear the search")
                .accessibilityIdentifier("clearSearchQuery")
            }
        }
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.close)
        .background(Palette.fieldColor, in: RoundedRectangle(cornerRadius: Rounding.control))
    }
}

/// One day a search found: which day it was, and the words of it that matched.
private struct SearchResultRow: View {
    let result: SearchResult
    let accent: Accent
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(result.day.spelledOut(withYear: true))
                    // A small label over a piece of prose, which is what the
                    // identity sets a chip's lettering at — and a step of ink
                    // under the words themselves, because the day is what the
                    // line is filed under and not what somebody is reading.
                    .lettering(.chipLabel)
                    .foregroundStyle(Palette.inkMutedColor)

                Text(theLineItIsOn)
                    .lettering(.prose)
                    .foregroundStyle(Palette.inkColor)
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
        // The line as it was written, marks and all: what is read out has to
        // be the day's own words, and a mark is a colour rather than a word.
        .accessibilityValue(result.excerpt)
    }

    /// The line the match sits on, with the query's own words picked out of
    /// it: the accent's ink on a wash of the accent, which is the pair the
    /// identity keeps for a word written on its own colour (ADR 0006).
    ///
    /// An `AttributedString` rather than a run of tinted boxes, because a
    /// result is two lines of prose that wrap: a marked word that fell on a
    /// line break has to break with the line, and a box drawn around it could
    /// not.
    private var theLineItIsOn: AttributedString {
        result.runs.reduce(into: AttributedString()) { line, run in
            var words = AttributedString(run.text)
            if run.isMarked {
                words.foregroundColor = accent.ink
                words.backgroundColor = accent.soft
            }
            line += words
        }
    }
}

/// The searches already made, for a box nobody has typed in yet.
private struct RecentQueries: View {
    let queries: [String]
    let search: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            SectionHeader("Recent")

            WrappingRow {
                ForEach(queries, id: \.self) { query in
                    Button { search(query) } label: {
                        Text(query)
                            .lettering(.chipLabel)
                            .foregroundStyle(Palette.inkMutedColor)
                            .padding(.horizontal, Spacing.comfortable)
                            .padding(.vertical, Spacing.close)
                            .background(Palette.fieldColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recentSearch-\(query)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A folder that could not be read, said under the results.
///
/// Under them rather than in place of them: what was read last time is still
/// on screen and still worth searching, and this is what says it may be behind
/// (ADR 0001).
///
/// On a card, because it is the one thing on this sheet that is not a result
/// and sits over a list that scrolls under it.
private struct SearchProblemNotice: View {
    let problem: StorageProblem

    var body: some View {
        ProblemNotice(
            saying: """
                Aujour couldn't read your journal folder, so a day you've \
                written recently may not be found.
                """,
            suggestion: problem.suggestion,
            identifier: "searchProblem"
        )
        .padding(Spacing.comfortable)
        .background(Palette.cardColor, in: RoundedRectangle(cornerRadius: Rounding.card))
        .elevated(.floating)
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

    Color.clear.sheet(isPresented: .constant(true)) {
        JournalSearchSheet(
            search: JournalSearch(
                store: InMemoryJournalStore(
                    Dictionary(
                        uniqueKeysWithValues: written.map {
                            (PathTemplate.default.render($0.key), $0.value)
                        }
                    )
                )
            ),
            journal: Journal.inAPreview(over: .preview(.onThisDevice)),
            accent: DeviceSettings.default.accent
        )
        .sheetChrome()
    }
}

#Preview("A journal nobody has written in") {
    Color.clear.sheet(isPresented: .constant(true)) {
        JournalSearchSheet(
            search: JournalSearch(store: InMemoryJournalStore()),
            journal: Journal.inAPreview(over: .preview(.onThisDevice)),
            accent: DeviceSettings.default.accent
        )
        .sheetChrome()
    }
}
