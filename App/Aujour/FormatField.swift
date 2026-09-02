import SwiftUI

/// A settings field whose value is a format string nobody can evaluate in
/// their head: what is typed, the line it would write underneath, and the one
/// thing worth saying about it that the line cannot.
///
/// The shape the entry path found first and every format setting since has
/// wanted — where photos go, and each of the four fields deciding how a data
/// placeholder writes itself out. A template described in tokens is a template
/// somebody has to imagine; the same template shown as one real line is one
/// they can check at a glance.
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

    /// The one thing about this field the worked example cannot show.
    let guidance: String

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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("\(identifier)Field")

            switch saying {
            case .example(let example):
                Text(example)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(identifier)Example")
            case .problem(let problem):
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("\(identifier)Problem")
            }

            Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
