import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// The file a day nobody has written yet is spawned from.
///
/// A file the user points at with the system's picker rather than a page they
/// type into, because that is what a Content Template is: a markdown file they
/// keep and edit, which Obsidian's daily notes name the same way and which
/// they very likely already have. It can be anywhere they keep their writing —
/// beside their entries, in a vault's `Templates` folder, in iCloud Drive —
/// and Aujour reads it where it lies, every time a day is spawned. There is no
/// copy here to go stale (ADR 0005).
///
/// Two rows and, on the day it has gone wrong, one notice. The paragraph this
/// setting used to carry — what the tokens are, that Obsidian edits reach
/// tomorrow's entry, where to keep the file so the other devices find it — is
/// gone: none of it is a thing the reader needs at the moment they are
/// choosing a file, and all of it was between them and the button.
///
/// Under the rows, once a file is chosen and readable, that file itself: its
/// markdown as it is written, in a text area, saved back where it lies. Raw
/// and unstyled on purpose — the `{{tokens}}` are the point of the file, and a
/// page that rendered or tidied them would be showing something other than
/// what the next spawn will read. It is here for the edit that would otherwise
/// mean leaving Aujour, opening Obsidian, and finding the file: a heading
/// added, a token moved. Anything longer is still better done in the editor
/// they keep the file in, and this page is deliberately no rival to it.
struct ContentTemplateView: View {
    let journal: Journal

    /// Whether the Files picker is up.
    @State private var picking = false

    /// What the template file said when it was last read — the text the edits
    /// below are edits *of*, and what tells a change from a file reopened.
    @State private var file: TheFileItself = .unread

    /// The markdown in the text area, which is the file's until somebody
    /// types.
    @State private var edited = ""

    /// The last save that did not land. Shown rather than swallowed: the words
    /// are on screen and nowhere else until one does (ADR 0001).
    @State private var saveProblem: StorageProblem?

    /// The template file, as far as this page has got with it.
    private enum TheFileItself {
        /// Not asked yet, or there is no file to ask.
        case unread
        /// What it says, as it was read.
        case saying(String)
        /// There is a file and Aujour could not read it — which is the one
        /// state the text area must not appear in, because an empty area over
        /// an unread file is a template one save would wipe out.
        case unreadable

        /// Whether there is a file and Aujour could not read it.
        var isUnreadable: Bool {
            if case .unreadable = self { return true }
            return false
        }
    }

    var body: some View {
        Form {
            Section {
                Button { chooseAFile() } label: {
                    LabeledContent("File", value: journal.contentTemplateName ?? "None")
                }
                .accessibilityIdentifier("contentTemplateFile")

                if journal.contentTemplateName != nil || journal.theTemplateIsOutOfReach {
                    Button("Use no template") {
                        Task { await journal.useAsTheContentTemplate(nil) }
                    }
                    .accessibilityIdentifier("noContentTemplate")
                }
            } footer: {
                // The one thing about this setting worth saying out loud: a
                // template that is set and unreachable is a blank page nobody
                // asked for. Said the same way whichever way it is out of
                // reach — a bookmark that will not resolve, or a path in the
                // folder with nothing at the end of it — because to the reader
                // they are the same file not answering.
                if journal.theTemplateIsOutOfReach || file.isUnreadable {
                    Text(
                        """
                        Aujour can't reach this file. New days start blank \
                        until it's back.
                        """
                    )
                    .foregroundStyle(Palette.alarmColor)
                    .accessibilityIdentifier("contentTemplateOutOfReach")
                }
            }
            .settingsRows()

            if case .saying = file {
                theFileItself
            }
        }
        .settingsPage(titled: "Template")
        .toolbar {
            if case .saying = file {
                ToolbarItem(placement: .confirmationAction) {
                    // A tick in the bar, where the entry path and the photo
                    // path put theirs: one thing typed on the page, one way of
                    // saying it is done. Never a save as they type — this is
                    // a file they keep, and it is not Aujour's to rewrite
                    // between keystrokes.
                    Button { save() } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .disabled(!isAChange)
                    .accessibilityIdentifier("saveContentTemplate")
                }
            }
        }
        .task(id: journal.contentTemplateName) { await read() }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.markdownFiles) { result in
            // Only a file that was picked is news: the other outcome is mostly
            // the user tapping Cancel, and a notice for a mind changed is
            // worse than nothing.
            guard case .success(let file) = result else { return }
            Task { await journal.useAsTheContentTemplate(file) }
        }
    }

    /// The markdown itself, exactly as the file has it.
    ///
    /// Monospaced and left alone: no rendering, no prettifying, no closing of
    /// a brace somebody half-typed. What is in this box is what the next day
    /// is spawned from, character for character, and the only way that stays
    /// true is if the app does nothing to it.
    private var theFileItself: some View {
        Section {
            TextEditor(text: $edited)
                .monospaced()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // The card's own paper, rather than the editor's default
                // surface on top of it (`settingsRows()`).
                .scrollContentBackground(.hidden)
                // Tall enough to hold a daily template's worth of headings
                // without becoming a page of its own.
                .frame(minHeight: 240)
                .accessibilityIdentifier("contentTemplateText")
        } footer: {
            if let saveProblem {
                Text("\(saveProblem.message) \(saveProblem.suggestion)")
                    .foregroundStyle(Palette.alarmColor)
                    .accessibilityIdentifier("contentTemplateSaveProblem")
            }
        }
        .settingsRows()
    }

    /// Whether what is in the text area differs from what the file said.
    private var isAChange: Bool {
        guard case .saying(let asItWas) = file else { return false }
        return edited != asItWas
    }

    /// What the picker will let them choose: markdown, and the plain text it
    /// is a kind of — a template written in a plain `.txt` is still a
    /// template, and a picker that greyed it out would be lying about why.
    private static let markdownFiles: [UTType] = [
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        .plainText,
        .text,
    ]

    private func chooseAFile() {
        // The Files picker is another process's screen, and driving it is the
        // one part of choosing a file that a UI test cannot do without
        // becoming a test of that screen. So the UI suite says which file it
        // means at launch, and it goes in through the same door the picker's
        // would — everything after this point is the app's own code.
        if let file = UITestingJournal.templateToPick() {
            Task { await journal.useAsTheContentTemplate(file) }
            return
        }
        picking = true
    }

    /// Reads the file this page is over — on the way in, and again each time
    /// the user points the setting at another one.
    ///
    /// What is on screen is thrown away when it does, because it belonged to
    /// the file that is no longer set: picking a second template mid-edit is
    /// the user saying the first one is not the one they meant.
    private func read() async {
        saveProblem = nil
        guard journal.contentTemplateName != nil else {
            file = .unread
            edited = ""
            return
        }
        if let markdown = await journal.theContentTemplateAsItReads() {
            file = .saying(markdown)
            edited = markdown
        } else {
            file = .unreadable
            edited = ""
        }
    }

    /// Writes what is in the text area back to the file.
    ///
    /// The words stay on screen either way. A save that failed leaves the text
    /// area holding the only copy of what they typed, and the sentence
    /// underneath saying so; one that landed makes what they typed the file's
    /// own text, which is what the tick goes quiet against.
    private func save() {
        let asItWillBe = edited
        Task {
            saveProblem = await journal.rewriteTheContentTemplate(asItWillBe)
            if saveProblem == nil { file = .saying(asItWillBe) }
        }
    }
}

#Preview {
    NavigationStack {
        ContentTemplateView(journal: Journal.inAPreview(over: .system))
    }
}
