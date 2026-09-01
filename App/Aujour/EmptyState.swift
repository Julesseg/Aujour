import SwiftUI

/// What a screen says where the Journal has nothing to show on it: a mark, the
/// line that names the state, and the sentence that says what to do about it.
///
/// A sentence rather than a blank, which is the whole of why this exists
/// (`CONTEXT.md`, Empty State). A journal is a thing somebody has *not* used
/// yet more often than a mail app is empty, and a grey rectangle on day one is
/// an app that looks broken to the only reader who cannot tell whether it is.
///
/// Shared rather than written out per screen, because the three of them are one
/// idea said three times — a first day, a Calendar month, a Search over a
/// Journal nobody has written in — and three screens each inventing their own
/// mark size and their own two shades of ink is how an identity stops being
/// one. `ContentUnavailableView` is the shape this replaces: it says the same
/// three things in the platform's own voice, which is the one voice a
/// paper-and-ink identity cannot borrow.
///
/// The two lines are the identity's prose voice and its aside — the app
/// addressing the reader, and then turning aside to say what to do — in the
/// ink and the muted step under it, both held to the sentence floor
/// (ADR 0006). The mark is the accent, which is a shape rather than a word and
/// clears the floor either way.
///
/// **Only ever a Journal that has been read and found empty.** One still being
/// read is a spinner and one that would not answer is a problem notice, and
/// both of them look exactly like this from the outside (ADR 0001) — which is
/// why neither is drawn with this.
struct EmptyState: View {
    /// The mark over it.
    let symbol: String

    /// The line that names the state — what is empty, and not why.
    let line: String

    /// What to do about it, or what it means. One sentence.
    let sentence: String

    /// What a test finds this state by, on the line: which of the three a
    /// screen is showing is the whole of what a running app has to be able to
    /// say about an empty one.
    let identifier: String

    /// The mark grows with the reader's text size like everything else, and
    /// stops. It is the one thing here carrying no words, so a page whose
    /// first screenful had become an icon would have lost the sentence to keep
    /// a decoration.
    @ScaledMetric(relativeTo: .title2) private var markSize: CGFloat = 40

    var body: some View {
        VStack(spacing: Spacing.comfortable) {
            Image(systemName: symbol)
                .font(.system(size: min(markSize, 72)))
                .foregroundStyle(.tint)
                // The line underneath says everything this does. Read out, it
                // would be the state named twice.
                .accessibilityHidden(true)

            VStack(spacing: Spacing.close) {
                Text(line)
                    .lettering(.pageVoice)
                    .foregroundStyle(Palette.inkColor)
                    .accessibilityIdentifier(identifier)

                Text(sentence)
                    .lettering(.aside)
                    .foregroundStyle(Palette.inkMutedColor)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.apart)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("A journal with nothing to search") {
    EmptyState(
        symbol: "magnifyingglass",
        line: "Nothing to search yet",
        sentence: """
            Write a day or two and this is how you find them again — by a word, \
            a name, anything you wrote.
            """,
        identifier: "nothingToSearchYet"
    )
    .background(Palette.backgroundColor)
}
