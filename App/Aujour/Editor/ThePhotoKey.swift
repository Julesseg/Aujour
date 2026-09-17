import PhotosUI
import SwiftUI

import AujourCore

/// The photo key pressed, and the way back into the Entry for what it brings.
///
/// The key is pressed on a text view and the photograph is chosen in another
/// process's picker, which are two different worlds — so what crosses between
/// them is this: where the caret was when the key went down, folded into a
/// closure that puts an embed there, and a word for when the picker has gone.
/// Nothing about the Entry, the file or the cursor travels with it, and the
/// closure is the editor's own so that a photograph goes in through the same
/// door a ticked box does — one edit, one undo step, saved as typing is.
///
/// ``PlaceholderQuestion``'s twin, and shaped like it for the same reason.
struct PhotoRequest: Identifiable {
    /// New for every press, so that pressing the key twice puts the picker up
    /// twice.
    let id = UUID()

    /// Writes the embed into the Entry where the caret was when the key was
    /// pressed — not where it is now, because a picker takes the keyboard with
    /// it and a text view with no keyboard reports no caret worth having.
    let insert: @MainActor @Sendable (Attachment) -> Void

    /// The picker has gone, with or without a photograph. Somebody who pressed
    /// a key above the keyboard was writing, and the keyboard is asked back.
    let finished: () -> Void
}

extension View {
    /// The system photo picker, put up over the day being written in because
    /// the photo key was pressed.
    ///
    /// Directly, with no sheet of Aujour's own in between: the whole library
    /// is what this key is for, and the day's own photographs are offered on
    /// the Suggestions sheet instead (``SuggestionsSheet``). It needs no
    /// permission at all — the picker runs in a process of its own and hands
    /// back only what was chosen — so a journal can have photographs in it
    /// whatever the user said about the library.
    ///
    /// Here rather than on the editor because a picker is a presentation, and
    /// a presentation needs a view hierarchy to come up in: the text view can
    /// say the key went down and where the caret was, and that is all it can
    /// say (``PhotoRequest``).
    ///
    /// - Parameters:
    ///   - request: the key press waiting on a photograph, and `nil` the rest
    ///     of the time. Set by the editor, and put back to `nil` here when the
    ///     picker goes.
    ///   - photographs: the pipeline into the folder — the conversion, the
    ///     file, the embed to point at it.
    func thePhotoPicker(
        for request: Binding<PhotoRequest?>,
        through photographs: InsertedPhotographs
    ) -> some View {
        modifier(ThePhotoKeysPicker(request: request, photographs: photographs))
    }
}

/// What the photo key does, from the press to the embed.
///
/// The picker's own dismissal and the photograph it hands back are two
/// separate arrivals, and neither waits for the other — so the press is over
/// as soon as the picker goes, and the way into the Entry is kept a little
/// longer. A photograph that is only in iCloud takes seconds to come down, and
/// the keyboard is back and the day being typed in long before it lands.
private struct ThePhotoKeysPicker: ViewModifier {
    @Binding var request: PhotoRequest?

    let photographs: InsertedPhotographs

    /// Whether the picker is up.
    ///
    /// Its own state rather than read off the request, because the request is
    /// over the moment the picker goes and the picker is what says so.
    @State private var isUp = false

    /// What the picker handed back, while it is being read.
    @State private var picked: PhotosPickerItem?

    /// Where the embed goes, kept for as long as a photograph might still be
    /// arriving — which is past the point the press itself is over.
    @State private var insert: (@MainActor @Sendable (Attachment) -> Void)?

    /// Picked photographs in the order their pickers handed them back.
    ///
    /// The keyboard returns before an iCloud photograph necessarily arrives,
    /// so another press can overtake it. Keeping a queue here preserves both
    /// presses and the caret captured by each one.
    @State private var insertions = PhotoPickerInsertions()

    func body(content: Content) -> some View {
        content
            // The photograph as the library has it, rather than a copy the
            // system has already converted: which formats a journal folder
            // keeps is Aujour's own decision, and it should be the same one
            // whichever door a photograph came in by.
            .photosPicker(
                isPresented: $isUp,
                selection: Binding(
                    get: { picked },
                    set: { chosen in
                        picked = nil
                        guard let chosen, let insert else { return }
                        self.insert = nil
                        insertions.append(
                            loading: {
                                try? await chosen.loadTransferable(type: Data.self)
                            },
                            through: photographs,
                            inserting: insert
                        )
                    }
                ),
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: request?.id) { _, pressed in
                guard pressed != nil, let request else { return }
                insert = request.insert

                // In a UI test, the photograph the suite said it meant at
                // launch, through the same pipeline and with no picker at all:
                // the picker is another process's screen, and driving it would
                // make a test of the app into a test of that screen
                // (`UITestingJournal`).
                guard let asked = UITestingJournal.photographToInsert() else {
                    return isUp = true
                }
                let insert = request.insert
                self.insert = nil
                pressIsOver()
                insertions.append(
                    loading: { asked },
                    through: photographs,
                    inserting: insert
                )
            }
            .onChange(of: isUp) { _, up in
                // The picker has gone, with or without a photograph: somebody
                // who pressed a key above the keyboard was writing, and the
                // commonest outcome of opening a picker is closing it again.
                guard !up else { return }
                pressIsOver()
            }
    }

    /// The key press is done with: the keyboard is asked back, and nothing is
    /// waiting on the picker any more.
    private func pressIsOver() {
        guard let request else { return }
        insert = nil
        self.request = nil
        request.finished()
    }

}

/// The photographs picked while an earlier one may still be coming down from
/// iCloud, kept in order and paired with the caret from their own key press.
///
/// A folder that would not take one is said under the day (``EntryView``), and
/// nothing goes into the Entry. Something the picker would not hand over goes
/// no further and says nothing: the system only offers images, so that is a
/// defensive answer rather than a case somebody meets.
@MainActor
final class PhotoPickerInsertions {
    private var last: Task<Void, Never>?

    func append(
        loading: @escaping @MainActor () async -> Data?,
        through photographs: InsertedPhotographs,
        inserting insert: @escaping @MainActor @Sendable (Attachment) -> Void
    ) {
        let before = last
        last = Task {
            await before?.value
            guard
                !Task.isCancelled,
                let contents = await loading(),
                let attachment = await photographs.keep(contents)
            else { return }
            insert(attachment)
        }
    }

    /// Waits for everything already handed over. Internal for the test that
    /// proves two quick picker visits retain their own carets.
    func waitUntilIdle() async {
        await last?.value
    }
}
