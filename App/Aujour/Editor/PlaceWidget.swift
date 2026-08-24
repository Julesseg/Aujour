import AujourCore
import SwiftUI

/// Answering `{{location}}`: the place the device says you are in, and the
/// ones around it to take instead.
///
/// The whole sheet is one field with a list under it, and the list is an
/// offer rather than a requirement — because the field alone is a complete
/// answer, and on a device that will not say where it is, the field alone is
/// the whole sheet. That is what "degrades gracefully" is made of here: not a
/// notice about a permission in front of somebody mid-sentence, but a question
/// they can always answer, with the device's help where there is any.
///
/// What lands in the Entry is plain place text and nothing around it — the
/// name, the way ``AujourCore/Place/written`` says it. A day that answered
/// this widget and a day that typed the place are the same file (ADR 0001).
struct PlaceholderAnsweredWithAPlace: View {
    let question: PlaceholderQuestion

    /// Where the device says it is, read once with the sheet on screen.
    ///
    /// Made here rather than handed in because a question is one sheet: the
    /// widget is tapped, the place is looked for, the answer is written and it
    /// is all over. Nothing about it outlives the sheet, and nothing else in
    /// the app has any use for where the phone was a minute ago.
    @State private var suggestions: PlaceSuggestions

    /// What "Add" would write. The offered place to begin with, and whatever
    /// has been tapped or typed after that.
    @State private var answer = ""

    @Environment(\.dismiss) private var dismiss

    /// - Parameter places: where the surrounding places are read from — the
    ///   device's own, unless a test or a preview says otherwise. `nil` is a
    ///   sheet with nothing on offer, which is the sheet a refusal gets too.
    init(question: PlaceholderQuestion, from places: (any Places)?) {
        self.question = question
        _suggestions = State(wrappedValue: PlaceSuggestions(from: places))
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

    /// The places around, or the offer to go and find them — and nothing at
    /// all where there are none, which leaves the field standing on its own.
    @ViewBuilder private var around: some View {
        switch suggestions.state {
        case .nothingToOffer:
            EmptyView()

        case .couldLook:
            Section {
                Button("Use my location", systemImage: "location") {
                    Task { await suggestions.askToLook() }
                }
                .accessibilityIdentifier("findMyPlace")
            } footer: {
                Text(
                    "Aujour looks once, to offer the place you're in. It never asks where you are in the background, and the place goes nowhere but this entry."
                )
            }

        case .looking:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding where you are…").foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("findingMyPlace")
            }

        case .offering(let places):
            // The picker, and the whole of it: the offer is the first row and
            // a different place is a tap on another. Every one of them writes
            // into the field rather than answering outright, so the last word
            // is the user's either way.
            Section("Nearby") {
                ForEach(places) { place in
                    Button { answer = place.written } label: { row(place) }
                        .accessibilityIdentifier("nearbyPlace.\(place.name)")
                }
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

#Preview("Somewhere with places around it") {
    Color.clear.sheet(
        item: .constant(PlaceholderQuestion(placeholder: .location, answered: { _ in }))
    ) { question in
        PlaceholderAnswerSheet(question: question, from: SomewhereInParis())
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
}
