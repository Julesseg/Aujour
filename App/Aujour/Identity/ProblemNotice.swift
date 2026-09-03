import SwiftUI

/// Something that went wrong, in the two lines it takes to say it: what
/// happened, and what to do about it.
///
/// Shared rather than written out per sheet, for the reason the pieces in
/// `SettingsChrome.swift` are shared: how the app says something has gone
/// wrong is the identity's and not a screen's own idea, and two screens each
/// inventing their own pair of inks is how an identity stops being one.
///
/// Two steps of ink rather than two weights of one, and never the system's
/// warning triangle in the system's orange. A folder that has not answered yet
/// is not an error, and both lines are sentences the reader is meant to read —
/// so both clear the sentence floor (ADR 0006), which is what puts the second
/// on the muted step rather than the faint one.
///
/// This is deliberately not an ``EmptyState``: a Journal that could not be
/// read and a Journal nobody has written in look identical from the outside,
/// and only one of them is the user's to be told about (`CONTEXT.md`, Empty
/// State).
struct ProblemNotice: View {
    /// What happened, in a sentence.
    ///
    /// Handed in rather than taken off the problem, because it is not always
    /// the error's own sentence: a folder that would not answer *a search* is
    /// something the search screen has to say in its own words, since what the
    /// user loses is a day they wrote and not the journal.
    let saying: String

    /// What to do about it.
    let suggestion: String

    /// What a test finds it by — one screen can be saying two of these at
    /// once, about two different failures.
    let identifier: String

    /// The ink the first line takes. The ordinary one, unless this is a thing
    /// that has gone wrong and will stay wrong until somebody acts — which is
    /// what the identity's one alarm colour is for.
    var ink: Color = Palette.inkColor

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(saying)
                .lettering(.rowLabel)
                .foregroundStyle(ink)
            Text(suggestion)
                .lettering(.note)
                .foregroundStyle(Palette.inkMutedColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(identifier)
    }
}
