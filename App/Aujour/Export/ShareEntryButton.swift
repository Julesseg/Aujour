import AujourCore
import SwiftUI

/// The way a day leaves the app, as it appears on the bar: one button, and the
/// sheet it summons.
///
/// A button and not a menu of the two forms, because which form somebody wants
/// is a question about what the file will look like at the other end — so it
/// is asked on a sheet that shows them (``ShareEntrySheet``) rather than in a
/// list of two words.
///
/// ## Why this holds the Entry rather than what is in it
///
/// Whether there is anything to send is a fact about the words, and the words
/// change on every keystroke. Reading them here rather than on the screen
/// above is what keeps that read where it costs nothing: a toolbar button
/// redrawn as somebody types is a toolbar button redrawn, and the same read
/// one level up would be the whole Entry screen — editor, panel and all —
/// invalidated by every letter.
///
/// It is also what takes the words *once*, on the way to the sheet: what is
/// previewed and what is handed over are then the same day, and neither is a
/// re-read of an editor nobody is typing into any more.
struct ShareEntryButton: View {
    /// The day this is about, and the words in it.
    let editor: EntryEditor

    /// The day on its way out, while the sheet asking how is up — set by this
    /// button and put away by the sheet.
    ///
    /// The sheet itself is put up by the screen rather than from here, like
    /// every other sheet in the app: one declared inside a toolbar item is one
    /// that lives and dies with a control on a bar.
    @Binding var sending: ADayToSend?

    /// Where the sheet rises from, so that it comes out of this button rather
    /// than up from the bottom of the screen.
    let risingFrom: Namespace.ID

    var body: some View {
        // Only over a day there is something to send. A day still opening has
        // no words yet, and an offer to share an empty page is an offer of
        // nothing — the same answer the photo suggestions panel gives a day
        // the camera missed.
        if editor.state.isEditing, editor.words.hasWords {
            Button("Share", systemImage: "square.and.arrow.up") {
                sending = ADayToSend(export: editor.words)
            }
            .summonsASheet(Sheets.share, in: risingFrom)
            .accessibilityIdentifier("shareEntry")
        }
    }
}

/// One day on its way out, while the sheet asking how to send it is up.
///
/// A type around the export rather than the export itself, because
/// `.sheet(item:)` wants something identifiable and a day and its words are
/// not one — the same reason ``SharedEntry/File`` exists.
struct ADayToSend: Identifiable, Equatable {
    let export: EntryExport

    var id: JournalDay { export.day }
}

extension EntryEditor {
    /// This day as the thing it would be sent as: the words on screen rather
    /// than the ones in the folder, because the last second of typing has not
    /// reached it yet and a share sheet is a strange place to find that out.
    var words: EntryExport {
        EntryExport(day, markdown: content)
    }
}
