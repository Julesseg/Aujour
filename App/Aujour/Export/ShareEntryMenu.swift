import AujourCore
import SwiftUI

/// The way a day leaves the app: one button, and the two things it can leave
/// as.
///
/// A menu rather than a single share button, because the two forms are not
/// interchangeable and the app is not the one who knows which is wanted. A
/// **PDF** is the day to read — mailed to somebody, or printed. **Plain text**
/// is the day to keep working on — pasted into a message, or dropped into
/// another vault. Both go out through the system share sheet, which is where
/// every destination on the device already is.
///
/// ## Why this holds the Entry rather than what is in it
///
/// Whether there is anything to send is a fact about the words, and the words
/// change on every keystroke. Reading them here rather than on the screen
/// above is what keeps that read where it costs nothing: a toolbar button
/// redrawn as somebody types is a toolbar button redrawn, and the same read
/// one level up would be the whole Entry screen — editor, panel and all —
/// invalidated by every letter.
struct ShareEntryMenu: View {
    /// The day this is about, and the words in it.
    let editor: EntryEditor

    /// The photographs the day on screen has already found, so that the page
    /// carries the pictures the screen does.
    let pictures: EmbeddedPictures

    /// This day on its way out — asked to write the file, and holding it
    /// while the sheet is up.
    ///
    /// The sheet itself is put up by the screen rather than from here, like
    /// every other sheet in the app: one declared inside a toolbar item is
    /// one that lives and dies with a control on a bar.
    let shared: SharedEntry

    /// This day as the thing it would be sent as: the words on screen rather
    /// than the ones in the folder, because the last second of typing has not
    /// reached it yet and a share sheet is a strange place to find that out.
    private var export: EntryExport {
        EntryExport(editor.day, markdown: editor.content)
    }

    var body: some View {
        // Only over a day there is something to send. A day still opening has
        // no words yet, and an offer to share an empty page is an offer of
        // nothing — the same answer the photo suggestions panel gives a day
        // the camera missed.
        if editor.state.isEditing, export.hasWords {
            if shared.isPreparing {
                // The button's own place, so nothing on the bar moves: a PDF
                // of a long day with photographs in it takes a moment, and a
                // button that looks idle is one somebody presses again.
                ProgressView()
                    .accessibilityIdentifier("preparingShare")
            } else {
                Menu {
                    Button("PDF", systemImage: "doc.richtext") {
                        Task { await shared.share(export, as: .pdf, drawnWith: pictures) }
                    }
                    .accessibilityIdentifier("shareAsPDF")

                    Button("Plain Text", systemImage: "doc.plaintext") {
                        Task { await shared.share(export, as: .plainText, drawnWith: pictures) }
                    }
                    .accessibilityIdentifier("shareAsPlainText")
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareEntry")
            }
        }
    }
}
