import SwiftUI
import AujourCore

/// Today's Entry, in the plainest editor that could possibly work.
///
/// Deliberately a bare `TextEditor`: the live-preview editor is M3's whole
/// milestone, and putting a real one here first would mean writing it twice.
/// What this proves is the loop underneath — a day opens, what is typed is
/// written, and it is still there next launch.
///
/// The view holds no rules. Which day this is, what an unwritten day starts
/// as, whether a keystroke belongs on disk yet and when it goes there are all
/// ``EntryEditor``'s, which is why they are unit-tested on Linux rather than
/// in a simulator.
struct TodayEntryView: View {
    @Bindable var editor: EntryEditor

    var body: some View {
        Group {
            switch editor.state {
            case .opening:
                ProgressView("Opening today's entry")
                    .accessibilityIdentifier("openingEntry")

            case .editing:
                // Bound straight to the editor's own text, which is what
                // makes every keystroke an edit it knows to save.
                TextEditor(text: $editor.content)
                    .font(.body)
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("entryEditor")
                    .accessibilityLabel("Today's entry")

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
        TodayEntryView(editor: editor)
            .navigationTitle(today.spelledOut())
            .navigationBarTitleDisplayMode(.inline)
    }
    .task { await editor.open() }
}

#Preview("A day already written") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let editor = EntryEditor(
        store: InMemoryJournalStore([
            PathTemplate.default.render(today): "Walked to the market, and back the long way.\n"
        ])
    )

    NavigationStack {
        TodayEntryView(editor: editor)
            .navigationTitle(today.spelledOut())
            .navigationBarTitleDisplayMode(.inline)
    }
    .task { await editor.open() }
}
