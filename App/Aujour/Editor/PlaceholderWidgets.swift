import AujourCore
import SwiftUI

/// The half of an interactive placeholder that needs a screen: what its widget
/// says while the question is open, and what answering it asks.
///
/// Which stretches of an Entry are a widget, and what answering one writes, is
/// ``AujourCore/InteractivePlaceholder``'s — decided from the text alone and
/// unit-tested against it. What is left is what no amount of reading the text
/// can say, and it is all here: a name, a symbol, and the thing that comes up
/// when a finger lands on the pill.
///
/// Every one of them is a `switch` over the enum with no `default` in it, so
/// registering a placeholder in Core stops the compiler here until it has been
/// given a face. That is the whole of what adding one costs.
extension InteractivePlaceholder {
    /// What the widget says. A word, because it stands in the middle of a
    /// sentence somebody is writing.
    var title: String {
        switch self {
        case .mood: "Mood"
        case .location: "Location"
        }
    }

    /// The symbol beside it.
    var symbol: String {
        switch self {
        case .mood: "face.smiling"
        case .location: "mappin.and.ellipse"
        }
    }
}

/// A widget the user tapped, and the way back into the Entry it stands in.
///
/// The tap happens in a text view and the answer is asked for in a sheet,
/// which are two different worlds — so what crosses between them is this: the
/// placeholder being asked, and a closure that puts the answer where the token
/// is. Nothing about the Entry, the file or the cursor travels with it, and
/// the closure is the editor's own so that answering goes in through the same
/// door a ticked box does — one edit, one undo step, saved as typing is.
struct PlaceholderQuestion: Identifiable {
    /// New for every tap, so that asking the same question twice puts the
    /// sheet up twice.
    let id = UUID()

    let placeholder: InteractivePlaceholder

    /// Writes the answer into the Entry in place of the token — or leaves the
    /// Entry exactly as it is, for an answer with nothing in it, and for a
    /// token that has stopped being there while the sheet was up.
    let answered: (String) -> Void
}

/// The sheet a tapped widget puts up.
///
/// The chrome is the same for every placeholder — a title, a way out, and a
/// way to answer — and what fills it is the placeholder's own. Cancelling
/// writes nothing at all, which leaves the token where it stands: a question
/// nobody answered is still a question, and it will be a widget again the next
/// time the day is opened.
struct PlaceholderAnswerSheet: View {
    let question: PlaceholderQuestion

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            answering
                .navigationTitle(question.placeholder.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("cancelPlaceholder")
                    }
                }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("placeholderAnswer")
    }

    @ViewBuilder private var answering: some View {
        switch question.placeholder {
        case .mood: MoodAnsweredByRating(question: question)
        // The place picker is #27's. Until it lands {{location}} is answered
        // in words, which is also what any placeholder registered later is
        // answered in until somebody draws it something better — a widget
        // nobody has designed yet is a question that can still be answered,
        // not one that does nothing.
        case .location: PlaceholderAnsweredInWords(question: question)
        }
    }
}

/// Answering {{mood}} by rating the day.
///
/// One tap and the question is gone. The marks are the whole of the form —
/// there is no second field to fill and nothing to check over — so a
/// confirmation button would be a press that could only ever repeat the one
/// before it. That is the same bargain a task's box makes, and it is undone the
/// same way: the answer is an edit in the Entry's own undo stack, so a mark
/// pressed by mistake is taken back the way a line typed by mistake is.
///
/// What each mark writes is ``AujourCore/MoodRating``'s, and it lives in Core
/// rather than here because the sentence outlives the sheet: what a tap leaves
/// behind is a line of the user's journal, read afterwards by everything that
/// has never heard of this screen (ADR 0001).
private struct MoodAnsweredByRating: View {
    let question: PlaceholderQuestion

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("How was the day?")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(MoodRating.all, id: \.value) { rating in
                    Button { answer(rating) } label: {
                        Image(systemName: "\(rating.value).circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    // The marks are numbers on screen and numbers to
                    // VoiceOver, because the sentence they write is one:
                    // nothing here claims to know what a 4 felt like.
                    .accessibilityLabel(
                        "\(rating.value) out of \(MoodRating.scale.upperBound)"
                    )
                    .accessibilityIdentifier("moodRating\(rating.value)")
                }
            }
            .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func answer(_ rating: MoodRating) {
        question.answered(rating.answer)
        dismiss()
    }
}

/// Answering a placeholder by typing the answer.
///
/// What goes in the file is what was typed and nothing around it: the token is
/// replaced by plain markdown, so the line reads afterwards as a line somebody
/// wrote, and every other tool sees exactly that.
private struct PlaceholderAnsweredInWords: View {
    let question: PlaceholderQuestion

    @State private var answer = ""
    @FocusState private var writing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            // One line, not a paragraph: a return in the middle of an answer
            // would break the line the token stands on in two.
            TextField(question.placeholder.title, text: $answer)
                .focused($writing)
                .submitLabel(.done)
                .onSubmit(answerIt)
                .accessibilityIdentifier("placeholderAnswerField")
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: answerIt)
                    .disabled(nothingTyped)
                    .accessibilityIdentifier("answerPlaceholder")
            }
        }
        .onAppear { writing = true }
    }

    private var nothingTyped: Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func answerIt() {
        guard !nothingTyped else { return }
        question.answered(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

#Preview("Answering one") {
    Color.clear.sheet(
        item: .constant(PlaceholderQuestion(placeholder: .mood, answered: { _ in }))
    ) { question in
        PlaceholderAnswerSheet(question: question)
    }
}
