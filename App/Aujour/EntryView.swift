import SwiftUI
import AujourCore

/// One day's Entry, written in markdown that is styled where it is typed.
///
/// The same screen for today's Entry and for a day filled in from the
/// calendar, because they are the same thing: an Entry is its date, and
/// nothing about writing in one changes with which date that is.
///
/// The view holds no rules. Which day this is, what an unwritten day starts
/// as, whether a keystroke belongs on disk yet and when it goes there are all
/// ``EntryEditor``'s, which is why they are unit-tested on Linux rather than
/// in a simulator.
struct EntryView: View {
    @Bindable var editor: EntryEditor

    /// The pictures this Entry's embeds point at, read out of the same folder
    /// the Entry came from.
    ///
    /// Here rather than inside the editor because it is the screen that knows
    /// which day is on it: a target is relative to the Entry that wrote it, so
    /// `market.jpg` in March's day and `market.jpg` in April's are allowed to
    /// be two different photographs.
    @State private var pictures = EmbeddedPictures()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch editor.state {
            case .opening:
                ProgressView("Opening \(editor.day.spelledOut())")
                    .accessibilityIdentifier("openingEntry")

            case .editing:
                // Bound straight to the editor's own text, which is what
                // makes every keystroke an edit it knows to save. What the
                // markdown in it looks like is `MarkdownEditor`'s, and what
                // it means is Core's.
                MarkdownEditor(
                    text: $editor.content,
                    pictures: pictures,
                    identifier: "entryEditor",
                    label: "Entry for \(editor.day.spelledOut())"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The Entry on screen decides where a relative embed points, so
                // the pictures follow it — including on the morning an app
                // left open overnight moves on to today.
                .onChange(of: editor.day, initial: true) { pictures.look(in: editor) }
                // The folder is shared, so a photo an Entry names can arrive
                // after the Entry did. Coming back to the front is when it is
                // worth looking again for the ones that were not there.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { pictures.lookAgainForWhatWasMissing() }
                }

            case .unavailable(let error):
                StorageProblemNotice(problem: StorageProblem(error)) {
                    await editor.open()
                }
            }
        }
        // Along the bottom rather than over the text: a save that failed must
        // be impossible to miss, and equally impossible to be stopped by —
        // the words are still on screen and still being typed.
        .safeAreaInset(edge: .bottom) {
            if let problem = editor.saveProblem {
                UnsavedWordsNotice(problem: StorageProblem(problem))
            }
        }
    }
}

/// A save that did not land, said where the user is writing.
///
/// Silence here is the one failure that costs words: the folder is the
/// journal (ADR 0001), so an Entry the app could not write is an Entry that
/// does not exist yet, however full the screen looks.
private struct UnsavedWordsNotice: View {
    let problem: StorageProblem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.message)
                    .font(.footnote.weight(.semibold))
                Text(problem.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial)
        .accessibilityIdentifier("unsavedWordsNotice")
    }
}

// Previews journal into memory, so the day on screen is the one the preview
// is named after rather than whatever this Mac's journal folder holds.
#Preview("An unwritten day") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let editor = EntryEditor(
        store: InMemoryJournalStore(),
        settings: JournalSettings(contentTemplate: "# {{title}}\n\nWoke at {{time}}.\n")
    )

    NavigationStack {
        EntryView(editor: editor)
            .navigationTitle(today.spelledOut())
            .navigationBarTitleDisplayMode(.inline)
    }
    .task { await editor.open() }
}

#Preview("A day already written") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let editor = EntryEditor(
        store: InMemoryJournalStore([
            PathTemplate.default.render(today): """
                # \(today.spelledOut())

                Walked to [the market](https://example.com), and back the *long* way.

                ## Bought
                - [x] milk
                - [ ] **bread**, still warm
                1. and a paper, in the end

                ![the market](attachments/2026/03/market.jpg)

                > Someone at the stall said something worth keeping.

                ---
                Ran `swift test` on the bus. ~~Nothing~~ everything passed.
                """
        ])
    )

    NavigationStack {
        EntryView(editor: editor)
            .navigationTitle(today.spelledOut())
            .navigationBarTitleDisplayMode(.inline)
    }
    .task { await editor.open() }
}
