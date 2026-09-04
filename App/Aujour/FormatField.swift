import SwiftUI

/// A settings field whose value is a format string nobody can evaluate in
/// their head: a section holding what is typed, with the line it would write
/// as the section's footer.
///
/// The shape the entry path found first and every format setting since has
/// wanted — where photos go, and each of the four fields deciding how a data
/// placeholder writes itself out. A template described in tokens is a template
/// somebody has to imagine; the same template shown as one real line is one
/// they can check at a glance.
///
/// A `Section` rather than a stack, because the worked example belongs where a
/// list puts the thing it says about the rows above it. That is also what
/// makes the example the *only* line under the field: a footer is one voice,
/// and the guidance paragraph these fields used to carry — which tokens exist,
/// what to leave empty, what Obsidian does — was three lines of explaining
/// arriving before the example that answered it.
///
/// The example stands where the refusal does, because they are the same line
/// answering the same question: a format that cannot be read has no example to
/// give, and the sentence saying why is what the user needs in its place.
struct FormatField: View {
    /// What the field is called, in the words somebody looking for it would
    /// use rather than the model's.
    let title: String

    /// What stands in the field while it is empty.
    let prompt: String

    let text: Binding<String>

    /// What the format being typed would write — or why it cannot say.
    let saying: Saying

    /// What the field and its line underneath are found by in a UI test:
    /// `<identifier>Field`, and `<identifier>Example` or `<identifier>Problem`.
    let identifier: String

    enum Saying {
        /// What a day would read like under what is typed.
        case example(String)
        /// Why what is typed says nothing at all.
        case problem(String)
    }

    var body: some View {
        Section {
            TextField(prompt, text: text)
                .monospaced()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("\(identifier)Field")
        } header: {
            Text(title)
        } footer: {
            switch saying {
            case .example(let example):
                Text(example)
                    .monospaced()
                    .accessibilityIdentifier("\(identifier)Example")
            case .problem(let problem):
                // **No error colour**, which is the entry path's rule and is
                // the same rule here: a format halfway to being typed is
                // refused a dozen times on the way to one that is not, and
                // colouring that like a fault would be the app telling
                // somebody off for typing. It stands out by being full ink
                // where this line is otherwise the muted example — a step up
                // rather than a change of meaning. Held to the entry path's
                // own token so there is one decision and one test of it
                // (``EntryPathView/rejectionInk``).
                Text(problem)
                    .foregroundStyle(Color(EntryPathView.rejectionInk))
                    .accessibilityIdentifier("\(identifier)Problem")
            }
        }
    }
}
