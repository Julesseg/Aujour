import SwiftUI
import UIKit
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

    /// How the day is to be drawn — read here for the two things on this
    /// screen that are not chrome: the prompt over a day nobody has written,
    /// which is set in the reader's own writing, and the accent handed to the
    /// sheet an unanswered placeholder puts up.
    @Environment(\.editorLook) private var look

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

    /// The day as the screen holds it: the Frontmatter cut off the top for
    /// its section, the body under it for the text view, and the one text the
    /// two join back into — which is what the Entry is handed after every
    /// change to either half.
    ///
    /// Here rather than inside the editor because it is a reading of the
    /// Entry's text and not the text: the editor holds the file, byte for
    /// byte, and this is what the screen makes of its top (ADR 0007).
    @State private var cut = CutEntry("")

    /// The kind of the Property being added, while its name is being typed —
    /// the one row that is on screen and not in the file.
    @State private var pendingProperty: Property.Kind?

    /// This day on its way out of the app, while it is going.
    ///
    /// Here for the same reason the pictures are: a day reached from the
    /// calendar is pushed on top of today and both screens stay alive, so one
    /// of these between them would be a share sheet over the wrong day.
    @State private var shared = SharedEntry()

    /// The day whose sheet asking how to send it is up, and `nil` the rest of
    /// the time.
    ///
    /// Owned by the screen that put the offer on its bar rather than by this
    /// one, because that is where the offer is: on today's page it is a row in
    /// the menu, and in the search sheet it is a button beside the day's name.
    /// What stays here is everything the sending itself needs — the
    /// photographs this day embeds, the file, and the sheet over it — which is
    /// the Entry's and nobody else's.
    @Binding var sending: ADayToSend?

    /// What this screen is actually drawing in, light or dark — never "no
    /// preference", because a sheet has to be told the resolved answer and not
    /// the question (`ContentView` says why at length).
    @Environment(\.colorScheme) private var drawnIn

    /// Where the `{{location}}` widget reads the place from, for whichever
    /// sheet this Entry puts up.
    ///
    /// Held rather than reached for, like the library the photographs come
    /// from: the device's location is the app's to hand over, and a UI test
    /// journals against one that is said rather than found.
    private let places: (any Places)?

    /// The library the suggestions panel reads, held as well as handed to the
    /// panel because the `{{location}}` widget reads the same one: the
    /// positions this day's photographs carry are where it says the day was.
    private let library: (any PhotoLibrary)?

    /// Where the sending sheet rises from — the control that offered it, which
    /// belongs to the screen above. `nil` for a preview, which has no bar and
    /// no namespace to name one in.
    private let risingFrom: Namespace.ID?

    @Environment(\.scenePhase) private var scenePhase

    /// The reader's own text size, for the one number on this screen worked
    /// out from a font rather than drawn in one: how wide the day is set.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Which presentation the day is being read in, which decides whether its
    /// words are set at a measure or run to the width they are given.
    ///
    /// Through the environment rather than handed down, like the face they are
    /// written in and for the same reason: between the window that knows how
    /// wide it is and this view are the screen that pushed it and the search
    /// results that pushed it, neither of which has anything to say about
    /// measures and both of which would have to carry one.
    @Environment(\.journalLayout) private var layout

    /// - Parameter library: where this day's suggested photographs are read
    ///   from, and where a `{{location}}` widget reads the day's own places
    ///   from — the device's, unless a test or a preview says otherwise.
    ///   `nil` is a panel that never appears, which is what a preview and
    ///   every test of something else want.
    ///   - places: where a `{{location}}` widget reads the place from — the
    ///     device's, unless a test or a preview says otherwise. `nil` is a
    ///     widget with nothing on offer, which is a place typed instead.
    ///   - sending: where this screen says a day is on its way out. Set by
    ///     whichever control offered it, which is the bar's and not this
    ///     screen's; what happens next is here.
    ///   - risingFrom: the namespace that control marked itself in, so the
    ///     sheet comes out of it. `nil` is a sheet that comes up the ordinary
    ///     way, which is what a preview wants.
    init(
        editor: EntryEditor,
        photographsFrom library: (any PhotoLibrary)? = nil,
        placesFrom places: (any Places)? = nil,
        sending: Binding<ADayToSend?> = .constant(nil),
        risingFrom: Namespace.ID? = nil
    ) {
        self.editor = editor
        self.places = places
        self.library = library
        _sending = sending
        self.risingFrom = risingFrom
        _suggestions = State(wrappedValue: PhotoSuggestions(from: library))
    }

    /// How wide the day is set: 65 characters of the face it is written in
    /// beside a sidebar, and the whole of the room on a window that is
    /// narrower than a measure anyway.
    ///
    /// How many characters is a Layout decision and lives in Core; how many
    /// points that is lives here, because it is a question about a font and
    /// there is no answering it without a screen to ask on.
    private var measure: CGFloat {
        guard layout == .sidebar else { return .infinity }
        return look.measure(
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.contentSize
            )
        )
    }

    /// The body as the text view types into it: everything under the block,
    /// and every keystroke joined back onto the block for the Entry to save.
    private var bodyText: Binding<String> {
        Binding(
            get: { cut.body },
            set: { typed in
                var reading = cut
                reading.typed(typed)
                cut = reading
                editor.content = reading.content
            }
        )
    }

    /// The reading as the section changes it, every change reaching the
    /// Entry through the same door a keystroke goes through.
    private var cutBinding: Binding<CutEntry> {
        Binding(
            get: { cut },
            set: { reading in
                cut = reading
                editor.content = reading.content
            }
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
            case .opening, .editing:
                // Bound straight to the editor's own text, which is what
                // makes every keystroke an edit it knows to save. What the
                // markdown in it looks like is `MarkdownEditor`'s, and what
                // it means is Core's.
                //
                // Built while the day is still being read, and not only once
                // it has been. The text view is a UIKit view under the page,
                // and a UIKit view that comes into being while the page is
                // sliding in is put where the page will stop rather than
                // where it is — so a day reached by a swipe, which is read
                // behind the turn, arrived in place while the spinner that
                // stood in for it slid. The spinner is over the text view
                // now, and the text view is on the page from its first frame.
                MarkdownEditor(
                    text: bodyText,
                    pictures: pictures,
                    photographs: photographs,
                    asks: { question = $0 },
                    // Drawn quieter until somebody has written this day. A day
                    // with no file is spawned from the Content Template
                    // exactly as today is, so it arrives headings and all,
                    // looking like a day somebody wrote — and the ink is the
                    // one place a page of prose can say otherwise.
                    isUnwritten: editor.isUnwritten,
                    // The block above the text, and every change to it made
                    // through the same reading the body is typed into.
                    section: FrontmatterSection(
                        cut: cutBinding, pending: $pendingProperty, day: editor.day,
                        asks: { question = $0 }, accent: look.accent.color
                    ),
                    sectionIsTucked: cut.frontmatter == nil && pendingProperty == nil,
                    caretSettled: { caret, afterAPaste in
                        var reading = cut
                        reading.caret(at: caret, afterAPaste: afterAPaste)
                        guard reading != cut else { return nil }
                        cut = reading
                        return reading.body
                    },
                    identifier: "entryEditor",
                    label: "Entry for \(editor.day.spelledOut())"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Nothing to type into until there is a day to type into: a
                // keystroke that landed before the file was read would be
                // written over by it.
                .allowsHitTesting(editor.state.isEditing)
                .overlay {
                    if !editor.state.isEditing {
                        ProgressView("Opening \(editor.day.spelledOut())")
                            .accessibilityIdentifier("openingEntry")
                    }
                }
                // A day with nothing in it yet, said as the invitation it is
                // rather than left as a grey rectangle. Only once it has been
                // read: every day is empty for the moment before that.
                .overlay(alignment: .topLeading) {
                    if editor.state.isEditing, editor.content.isEmpty { ABlankPage() }
                }
                // Answering writes plain markdown where the token stood, and
                // cancelling writes nothing at all — so an unanswered
                // placeholder is still literal text in the file, and still a
                // widget the next time the day is opened.
                .sheet(item: $question) {
                    // The day as well as the seams, because a `{{location}}`
                    // widget is about the day being written rather than about
                    // now: it reads this day's photographs for where they were
                    // taken, so a Monday filled in on Friday is offered
                    // Monday's places and not the street outside.
                    PlaceholderAnswerSheet(
                        question: $0,
                        in: look.accent,
                        from: places,
                        photographsFrom: library,
                        for: editor.day
                    )
                }
                // Text that reached the Entry from elsewhere — the day being
                // opened, or its file having moved on underneath it — is read
                // afresh. What the screen wrote itself is already read.
                .onChange(of: editor.content, initial: true) {
                    var reading = cut
                    reading.contentArrived(editor.content)
                    if reading != cut { cut = reading }
                }
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
        // The measure, and then the room it is set in — which is what centres
        // it. Two frames and not one: a page that was simply given less width
        // would sit against the calendar beside it rather than in the middle
        // of what is left.
        .frame(maxWidth: measure, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                //
                // Only over a day that can be written in. The panel keeps what
                // it last found, so a folder that stopped opening under an
                // Entry that was on screen would otherwise leave a strip of
                // photographs beside the notice saying so — an offer the app
                // could not keep, since there is no Entry left to add one to.
                if editor.state.isEditing {
                    PhotoSuggestionsPanel(
                        suggestions: suggestions,
                        insert: { photograph in
                            Task { await photographs.insert(photograph, from: suggestions) }
                        },
                        isAddingOne: photographs.isAddingOne
                    )
                }
            }
        }
        // Declared here rather than beside the button that opens it, like
        // every other sheet in the app: one inside a toolbar item is one that
        // lives and dies with a control on a bar.
        //
        // The system's own sheet, over the file this one has written, is put
        // up from inside it — a sheet cannot present anything while another is
        // covering it.
        .sheet(item: $sending) { day in
            ShareEntrySheet(export: day.export, pictures: pictures, shared: shared)
                // Told the appearance rather than left to inherit it: a sheet
                // is its own presentation, so the scheme the window is drawn
                // in reaches it when it goes up and not afterwards.
                .preferredColorScheme(drawnIn)
                .sheetChrome(risingFrom: Sheets.theBar, in: risingFrom)
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

/// What an Entry that nobody has written a word of shows.
///
/// A journaling app's blank page is the screen it is most often looked at on
/// day one, and an empty grey rectangle is not an invitation to write on it.
///
/// One line, and the only one that is true every time this is on screen: any
/// day can be emptied back out by deleting what is in it, and a prompt that
/// went on to promise the folder was untouched would be saying so over a file
/// that exists. Where that promise *is* true of everything on screen — a
/// journal with no Entries at all — the calendar's empty state makes it.
///
/// Drawn over the text view rather than typed into it. A prompt put *in* the
/// Entry would be Aujour's words in the user's file, and the first thing their
/// journal said would be something they did not write (ADR 0001).
///
/// Nearly always a first day, because a Content Template is words on the page:
/// a journal pointed at one never sees this, and one pointed at nothing sees
/// it every morning until it is typed over.
private struct ABlankPage: View {
    /// The typeface the editor is in, because this prompt is standing in the
    /// editor's own first line: in anything else it would be the right words
    /// in the wrong face, at the wrong height, on the one screen where there
    /// is nothing else to compare it against.
    @Environment(\.editorLook) private var look

    var body: some View {
        Text("Write anything.")
            .font(Font(look.font.uiFont(compatibleWith: nil)))
            // The faint ink, which is the same step a day spawned from a
            // Content Template is drawn in (``MarkdownStyling/forADayNobodyHasWritten``).
            // The two are the same thing seen from either side — what stands
            // in the Entry until somebody writes it — and they are never on
            // screen together, so drawing them in two different shades would
            // be the app having two opinions about one state.
            //
            // Below the sentence floor on purpose, and licensed by the same
            // reading: the faint step is what the identity keeps for a field's
            // placeholder (ADR 0006, and ``Palette/inkFaint``), and this is
            // one. Nothing anybody wrote is ever drawn in it — the first
            // keystroke takes the page to the full ink and takes this away.
            .foregroundStyle(Palette.inkFaintColor)
            // Where the editor puts its first character, asked of the editor:
            // the prompt stands exactly where the typing will start.
            .padding(.leading, MarkdownEditor.whereTheFirstCharacterGoes.x)
            .padding(.top, MarkdownEditor.whereTheFirstCharacterGoes.y)
            // Never in the way of the finger going to the place it describes.
            .allowsHitTesting(false)
            .accessibilityIdentifier("aBlankPage")
    }
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
