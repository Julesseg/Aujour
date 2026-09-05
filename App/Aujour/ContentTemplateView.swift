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
struct ContentTemplateView: View {
    let journal: Journal

    /// Whether the Files picker is up.
    @State private var picking = false

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
                // asked for.
                if journal.theTemplateIsOutOfReach {
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
        }
        .settingsPage(titled: "Template")
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.markdownFiles) { result in
            // Only a file that was picked is news: the other outcome is mostly
            // the user tapping Cancel, and a notice for a mind changed is
            // worse than nothing.
            guard case .success(let file) = result else { return }
            Task { await journal.useAsTheContentTemplate(file) }
        }
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
}

#Preview {
    NavigationStack {
        ContentTemplateView(journal: Journal.inAPreview(over: .system))
    }
}
