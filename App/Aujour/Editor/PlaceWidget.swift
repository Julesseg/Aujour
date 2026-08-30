import AujourCore
import SwiftUI

/// Answering `{{location}}`: the places the day's own photographs were taken,
/// where the device says you are now, and the rest to take instead.
///
/// The whole sheet is one field with a list under it, and the list is an
/// offer rather than a requirement — because the field alone is a complete
/// answer, and on a device that will say neither, the field alone is the whole
/// sheet. That is what "degrades gracefully" is made of here: not a notice
/// about a permission in front of somebody mid-sentence, but a question they
/// can always answer, with the device's help where there is any.
///
/// The places arrive under two headings — "Near you" and "From photos" —
/// because where a suggestion came from is worth seeing: one is a claim about
/// this minute and the other about the day being written, and which to trust
/// is the user's to judge.
///
/// What lands in the Entry is plain place text and nothing around it — the
/// name, the way ``AujourCore/Place/written`` says it, whichever heading it
/// came from. A day that answered this widget and a day that typed the place
/// are the same file (ADR 0001).
struct PlaceholderAnsweredWithAPlace: View {
    let question: PlaceholderQuestion

    /// Where the day was, read once with the sheet on screen.
    ///
    /// Made here rather than handed in because a question is one sheet: the
    /// widget is tapped, the places are looked for, the answer is written and
    /// it is all over. Nothing about it outlives the sheet, and nothing else
    /// in the app has any use for where the phone was a minute ago.
    @State private var suggestions: PlaceSuggestions

    /// What "Add" would write. The offered place to begin with, and whatever
    /// has been tapped or typed after that.
    @State private var answer = ""

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - places: where the surrounding places are read from, and what puts
    ///     names to the positions the day's photographs carry — the device's
    ///     own, unless a test or a preview says otherwise. `nil` is a sheet
    ///     with nothing on offer, which is the sheet a refusal gets too.
    ///   - library: where the day's photographs are read from.
    ///   - day: the Journal Day being written about, whose photographs are the
    ///     ones read — so a Monday filled in on Friday is offered Monday's.
    init(
        question: PlaceholderQuestion,
        from places: (any Places)?,
        photographsFrom library: (any PhotoLibrary)?,
        for day: JournalDay?
    ) {
        self.question = question
        _suggestions = State(
            wrappedValue: PlaceSuggestions(from: places, photographsFrom: library, for: day)
        )
    }

    var body: some View {
        Form {
            Section {
                // Deliberately not focused on the way in, unlike a placeholder
                // answered in words: the keyboard would come up over the very
                // list this sheet exists to show. A tap on the field is one
                // tap, and it is the second way to answer rather than the
                // first.
                TextField("Place", text: $answer)
                    .submitLabel(.done)
                    .onSubmit(answerIt)
                    .accessibilityIdentifier("placeholderAnswerField")
            }
            around
        }
        // The sheet's own paper rather than the system's grouped grey, so that
        // the two questions this sheet asks are asked on one ground
        // (`PlaceholderAnswerSheet`). The rows keep a surface of their own —
        // a list on bare paper is a list that has stopped grouping — and it is
        // the identity's card, which is what a *thing on the page* is.
        .scrollContentBackground(.hidden)
        .listRowBackground(Palette.cardColor)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: answerIt)
                    .disabled(nothingChosen)
                    .accessibilityIdentifier("answerPlaceholder")
            }
        }
        .task { await suggestions.look() }
        // Filled in for them, once: the offer is what the widget is for. Only
        // into an empty field, so a place somebody has already tapped or typed
        // is never overwritten by an answer arriving behind it.
        .onChange(of: suggestions.offered, initial: true) {
            guard answer.isEmpty, let offered = suggestions.offered else { return }
            answer = offered.written
        }
    }

    /// The places found, and the offer to go and look further — and nothing at
    /// all where there is neither, which leaves the field standing on its own.
    ///
    /// The offer to look further is drawn outside the `switch` rather than as
    /// a case of it, because it is an independent fact: there are two
    /// permissions behind this sheet, and one of them can have been answered
    /// while the other is still worth offering. Somebody who allowed the
    /// device's location back when that was all the widget knew how to ask for
    /// sees their street *and* the offer to look at the day's photographs,
    /// which is the whole point of the second one.
    @ViewBuilder private var around: some View {
        switch suggestions.state {
        case .nothingToOffer:
            EmptyView()

        case .looking:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding where you were…").foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("findingMyPlace")
            }

        case .offering(let runs):
            // The picker, and the whole of it: the offer is the first row of
            // the first section and a different place is a tap on another.
            // Every one of them writes into the field rather than answering
            // outright, so the last word is the user's either way.
            //
            // A section apiece, because where a place came from is worth
            // seeing: "the café your photos say you were in" and "a café near
            // this phone right now" are different claims, and which of them
            // to trust is the user's to judge rather than the app's to bury.
            // A run with nothing in it never arrives, so a day with no
            // photographs is simply one section.
            ForEach(runs) { run in
                Section(run.from.heading) {
                    ForEach(run.places) { place in
                        Button { answer = place.written } label: { row(place) }
                            .accessibilityIdentifier("nearbyPlace.\(place.name)")
                    }
                }
            }
        }

        if let further = suggestions.couldLookFurther {
            Section {
                Button(further.offer, systemImage: further.symbol) {
                    Task { await suggestions.askToLook() }
                }
                .accessibilityIdentifier("findMyPlace")
            } footer: {
                // Said before the alert rather than after it. A finger landed
                // on a word about *where*, and an alert about photographs
                // arriving with no warning is an ambush however good the
                // reason for it — so the reason goes here, where it is read
                // first and the tap is still the user's to withhold.
                Text(further.promise)
            }
        }
    }

    private func row(_ place: Place) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .foregroundStyle(.primary)
                // What tells this Starbucks from the one two streets over.
                // Read here and written nowhere: it is not what somebody puts
                // in the middle of their own sentence.
                if let region = place.region {
                    Text(region)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if place.written == answer {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
    }

    private var nothingChosen: Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func answerIt() {
        guard !nothingChosen else { return }
        question.answered(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// What a run of places is called on screen.
///
/// Where a suggestion came from, in the user's terms rather than the system's:
/// not "reverse-geocoded photo metadata" but the day's photos, which is the
/// thing they actually took.
extension SuggestedPlaces.Source {
    var heading: String {
        switch self {
        case .nearby: "Near you"
        case .theDaysPhotographs: "From photos"
        }
    }
}

/// What the sheet says it is about to ask for, and what it promises about it.
///
/// One sentence per permission rather than one that covers both, because they
/// are two different claims and the larger one has to read like it. Being
/// asked where you are is a question about now; being asked to read the
/// positions your photographs carry is a question about everywhere you have
/// been, and the sentence that goes with it says so rather than borrowing the
/// one Photo Suggestions asks with.
extension PlaceSuggestions.ToLookFurther {
    /// What the button says. Named after what comes back rather than after the
    /// permission, because the permission is the system's word for it and the
    /// place is the user's.
    var offer: String {
        switch self {
        case .theDevicesLocation: "Use my location"
        case .theDaysPhotographs: "Use this day's photos"
        case .both: "Find where I was"
        }
    }

    var symbol: String {
        switch self {
        case .theDevicesLocation: "location"
        case .theDaysPhotographs: "photo.on.rectangle.angled"
        case .both: "mappin.and.ellipse"
        }
    }

    /// What is read before the system's alert, and what it promises.
    var promise: String {
        switch self {
        case .theDevicesLocation:
            "Aujour looks once, to offer the place you're in. It never asks where you are in the background, and the place goes nowhere but this entry."

        case .theDaysPhotographs:
            "Aujour reads where this day's photos were taken, to offer the places you went. It looks at no other day, keeps no map of them, and the place goes nowhere but this entry."

        case .both:
            "Aujour offers the places this day's photos were taken, and where you are now. It reads no other day, never asks where you are in the background, and what it finds goes nowhere but this entry."
        }
    }
}

#Preview("Somewhere with places around it") {
    Color.clear.sheet(
        item: .constant(PlaceholderQuestion(placeholder: .location, answered: { _ in }))
    ) { question in
        PlaceholderAnswerSheet(question: question, from: SomewhereInParis())
    }
}

#Preview("A day written up later") {
    Color.clear.sheet(
        item: .constant(PlaceholderQuestion(placeholder: .location, answered: { _ in }))
    ) { question in
        PlaceholderAnswerSheet(
            question: question,
            from: SomewhereInParis(),
            photographsFrom: ADayInParis(),
            for: JournalDay(year: 2026, month: 3, day: 9)
        )
    }
}

/// A few places, for a preview — there is no device behind a canvas, and a
/// sheet with nothing on offer is the one thing this preview is not about.
private struct SomewhereInParis: Places {
    let access = PlaceAccess.allowed

    func ask() async -> PlaceAccess { .allowed }

    func around() async -> Surroundings {
        Surroundings(
            named: [
                NearbyPlace(
                    place: Place(
                        id: "flore",
                        name: "Café de Flore",
                        region: "Boulevard Saint-Germain"
                    ),
                    metresAway: 12
                ),
                NearbyPlace(
                    place: Place(
                        id: "magots",
                        name: "Les Deux Magots",
                        region: "Place Saint-Germain-des-Prés"
                    ),
                    metresAway: 90
                ),
            ],
            area: Place(id: "quarter", name: "Saint-Germain-des-Prés", region: "Paris")
        )
    }

    func place(at position: Coordinate) async -> Place? {
        Place(id: "at:\(position.latitude)", name: "Musée d'Orsay", region: "Rue de Lille")
    }
}

/// A day photographed in one place, for a preview — a canvas has no library,
/// and a sheet with nothing from the day is the one thing this preview is not
/// about.
private struct ADayInParis: PhotoLibrary {
    let access = PhotoLibraryAccess.allowed

    func ask() async -> PhotoLibraryAccess { .allowed }

    func photographs(during span: DateInterval) async -> [DayPhotograph] {
        [
            DayPhotograph(
                id: "lunch",
                takenAt: span.start.addingTimeInterval(11 * 3600 + 4 * 60),
                position: Coordinate(latitude: 48.85995, longitude: 2.32660)
            )
        ]
    }

    func thumbnail(of photograph: DayPhotograph) async -> Data? { nil }

    func contents(of photograph: DayPhotograph) async -> Data? { nil }
}
