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

    /// The day's own photographs, offered under it — read out of the device's
    /// library for the Journal Day on screen.
    ///
    /// Here rather than one per journal, like the pictures and the picker
    /// above and below it: a day reached from the calendar is pushed on top of
    /// today and both screens stay alive, so one panel between them would be
    /// showing the wrong day's photographs the moment the user came back.
    @State private var suggestions: PhotoSuggestions

    /// The pictures this Entry's embeds point at, read out of the same folder
    /// the Entry came from.
    ///
    /// Here rather than inside the editor because it is the screen that knows
    /// which day is on it: a target is relative to the Entry that wrote it, so
    /// `market.jpg` in March's day and `market.jpg` in April's are allowed to
    /// be two different photographs.
    @State private var pictures = EmbeddedPictures()

    /// The way a photograph gets into this day: the system picker, and the
    /// file written into the Journal Root beside the Entry.
    ///
    /// Here for the same reason the pictures are, and pointed at the same
    /// Entry: where a photograph goes is the Attachment Path Template rendered
    /// for *this* day, and what the embed says is a path from *this* Entry.
    @State private var photographs = InsertedPhotographs()

    /// The unanswered placeholder whose widget was tapped, while it is being
    /// answered — and `nil` the rest of the time, which is nearly always.
    ///
    /// Here rather than inside the editor because a sheet needs a view
    /// hierarchy to come up in, and the editor is a text view: what it can do
    /// with a finger on a widget is say which question was asked, and hand
    /// over the way to write the answer back into the Entry.
    @State private var question: PlaceholderQuestion?

    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter library: where this day's suggested photographs are read
    ///   from — the device's, unless a test or a preview says otherwise.
    ///   `nil` is a panel that never appears, which is what a preview and
    ///   every test of something else want.
    init(editor: EntryEditor, photographsFrom library: (any PhotoLibrary)? = nil) {
        self.editor = editor
        _suggestions = State(
            wrappedValue: library.map { PhotoSuggestions(from: $0) } ?? PhotoSuggestions()
        )
    }

    /// The Entry these are all about, as something that can be compared.
    ///
    /// Both the day and the editor holding it, because either one changing is
    /// a different Entry for an embed to be resolved against — and only the
    /// second happens when the journal is reopened onto a setting the user has
    /// just changed, which leaves the same day on screen in a new editor.
    private var entryOnScreen: EntryOnScreen {
        EntryOnScreen(day: editor.day, editor: ObjectIdentifier(editor))
    }

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
                    photographs: photographs,
                    asks: { question = $0 },
                    identifier: "entryEditor",
                    label: "Entry for \(editor.day.spelledOut())"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Answering writes plain markdown where the token stood, and
                // cancelling writes nothing at all — so an unanswered
                // placeholder is still literal text in the file, and still a
                // widget the next time the day is opened.
                .sheet(item: $question) { PlaceholderAnswerSheet(question: $0) }
                // The Entry on screen decides where a relative embed points, so
                // both halves of an embed follow it — including on the morning
                // an app left open overnight moves on to today.
                .onChange(of: entryOnScreen, initial: true) {
                    pictures.look(in: editor)
                    photographs.adds(to: editor)
                    // And the day's own photographs, which are the Journal
                    // Day's and not today's — a Monday filled in on Friday is
                    // offered Monday's.
                    Task { await suggestions.look(for: editor.day) }
                }
                // The folder is shared, so a photo an Entry names can arrive
                // after the Entry did. Coming back to the front is when it is
                // worth looking again for the ones that were not there.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    pictures.lookAgainForWhatWasMissing()
                    // And the library has moved on too: a photograph taken
                    // five minutes ago is exactly the one somebody came back
                    // to write about.
                    Task { await suggestions.look(for: editor.day) }
                }

            case .unavailable(let error):
                StorageProblemNotice(problem: StorageProblem(error)) {
                    await editor.open()
                }
            }
        }
        // Along the bottom rather than over the text: something that could not
        // be written must be impossible to miss, and equally impossible to be
        // stopped by — the words are still on screen and still being typed.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let problem = editor.saveProblem {
                    WritingProblemNotice(
                        problem: StorageProblem(problem),
                        identifier: "unsavedWordsNotice"
                    )
                }
                if let problem = photographs.problem {
                    WritingProblemNotice(
                        problem: problem,
                        identifier: "photoProblemNotice",
                        acknowledge: photographs.acknowledge
                    )
                }
                // Under the notices and nearest the keyboard, which is where
                // the thumbs already are — and above nothing at all on the
                // days it has nothing to offer.
                PhotoSuggestionsPanel(suggestions: suggestions) { photograph in
                    Task { await photographs.insert(photograph, from: suggestions) }
                }
            }
        }
    }
}

/// The Entry a screen is about: which day, and which editor it is open in.
///
/// The second half matters because an editor is replaced without the day
/// changing — reopening the journal after a setting changes does exactly that
/// — and everything aimed at "the Entry on screen" has to be aimed again when
/// it is.
private struct EntryOnScreen: Hashable {
    let day: JournalDay
    let editor: ObjectIdentifier
}

/// Something that could not be written into the folder, said where the user
/// is writing.
///
/// Silence here is the one failure that costs words: the folder is the
/// journal (ADR 0001), so an Entry the app could not write is an Entry that
/// does not exist yet, however full the screen looks — and a photograph that
/// inserted nothing without saying why is the one outcome somebody would sit
/// and repeat.
private struct WritingProblemNotice: View {
    let problem: StorageProblem

    /// What a test finds it by: this screen can be saying two of these at
    /// once, about two different failures.
    let identifier: String

    /// The way to put it away, for a failure that is about something the user
    /// asked for once. A save that will not land has none — it is still true
    /// until the next one lands, and dismissing it would be dismissing the
    /// only sign that the day is not in the folder.
    var acknowledge: (() -> Void)?

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
            if let acknowledge {
                Button("Dismiss", systemImage: "xmark", action: acknowledge)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("dismiss\(identifier)")
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .accessibilityIdentifier(identifier)
    }
}

// Previews journal into memory, so the day on screen is the one the preview
// is named after rather than whatever this Mac's journal folder holds.
#Preview("An unwritten day") {
    let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
    let editor = EntryEditor(
        // The template is a file in the folder now (ADR 0005), so the folder
        // this preview journals into is one that holds it.
        store: InMemoryJournalStore(["templates/Daily.md": "# {{title}}\n\nWoke at {{time}}.\n"]),
        settings: JournalSettings(contentTemplateFile: "templates/Daily.md")
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
