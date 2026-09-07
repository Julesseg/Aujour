import PhotosUI
import SwiftUI
import UIKit

import AujourCore

/// The photo key pressed, and the way back into the Entry for what it brings.
///
/// The key is pressed on a text view and the photograph is chosen on a sheet,
/// which are two different worlds — so what crosses between them is this:
/// where the caret was when the key went down, folded into a closure that
/// puts an embed there, and a word for when the sheet has gone. Nothing about
/// the Entry, the file or the cursor travels with it, and the closure is the
/// editor's own so that a photograph goes in through the same door a ticked
/// box does — one edit, one undo step, saved as typing is.
///
/// ``PlaceholderQuestion``'s twin, and shaped like it for the same reason.
struct PhotoRequest: Identifiable {
    /// New for every press, so that pressing the key twice puts the sheet up
    /// twice.
    let id = UUID()

    /// Writes the embed into the Entry where the caret was when the key was
    /// pressed — not where it is now, because a sheet takes the keyboard with
    /// it and a text view with no keyboard reports no caret worth having.
    let insert: (Attachment) -> Void

    /// The sheet has gone, with or without a photograph. Somebody who pressed
    /// a key above the keyboard was writing, and the keyboard is asked back.
    let finished: () -> Void
}

/// The sheet the photo key puts up: the day's own photographs, and under them
/// the way to the rest of the library.
///
/// A journal is written in the evening about a day that is already on the
/// phone in pictures, so the shortest way between the two comes first: what
/// the camera has from this Journal Day, one tap each. The system picker is
/// under it for everything else — a photograph from another day, one somebody
/// was sent — and for a library Aujour was never allowed to read, since the
/// picker runs in a process of its own and needs no permission at all.
///
/// The sheet holds no rules. Which photographs belong to the day, whether
/// there is anything to offer and what asking for the library means are
/// ``AujourCore/PhotoSuggestions``'s, unit-tested on Linux; what a chosen
/// photograph becomes on its way into the folder is ``InsertedPhotographs``'s.
/// What is here is the grid, the words for a count, and the picker.
///
/// Either door ends the same way: the photograph is in the folder and its
/// embed in the day, and the sheet goes. It goes on a failure too, because
/// what went wrong is said under the day (``EntryView``) and a notice behind
/// a sheet is a notice nobody reads.
struct PhotoSheet: View {
    /// The Journal Day being written about, whose photographs are offered — a
    /// Monday filled in on Friday is offered Monday's.
    let day: JournalDay

    /// The pipeline into the folder, and the one place that says whether a
    /// photograph is already on its way.
    let photographs: InsertedPhotographs

    /// Where the embed goes once the photograph is in the folder — the
    /// request's own closure, which knows where the caret was.
    let insert: (Attachment) -> Void

    /// The day's photographs, read out of the library for the day on screen.
    /// Made with the sheet and gone with it: the library is read when it is
    /// looked at and not while the day is being written.
    @State private var suggestions: PhotoSuggestions

    /// Whether the system picker is up over this sheet.
    @State private var isPickingFromTheLibrary = false

    /// What the picker handed back, while it is being read.
    @State private var pickedFromTheLibrary: PhotosPickerItem?

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - day: the Journal Day whose photographs are offered.
    ///   - library: where they are read from. `nil` is a sheet with no
    ///     library behind it — the picker alone, which is what a preview and
    ///     a test of something else want.
    ///   - photographs: the way a chosen photograph reaches the folder.
    ///   - insert: the way its embed reaches the Entry.
    init(
        for day: JournalDay,
        photographsFrom library: (any PhotoLibrary)?,
        through photographs: InsertedPhotographs,
        inserting insert: @escaping (Attachment) -> Void
    ) {
        self.day = day
        self.photographs = photographs
        self.insert = insert
        _suggestions = State(wrappedValue: PhotoSuggestions(from: library))
    }

    var body: some View {
        NavigationStack {
            List {
                fromThisDay

                Section {
                    Button("Choose from Library", systemImage: "photo.on.rectangle") {
                        chooseFromTheLibrary()
                    }
                    .accessibilityIdentifier("chooseFromLibrary")
                }
                .settingsRows()
            }
            // The sheet's own paper rather than the system's grouped grey, and
            // the rows on the identity's card — the same ground the place
            // widget's list stands on (`PlaceWidget`), so that one sheet looks
            // like one app whichever key put it up.
            .scrollContentBackground(.hidden)
            .navigationTitle("Add a Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelPhoto")
                }
            }
            // Dimmed while one is on its way. A photograph that is only in
            // iCloud takes seconds to come down, and a grid that looked
            // exactly the same throughout would be one somebody taps again —
            // the taps are refused underneath this too (``InsertedPhotographs``),
            // and this is only what says so.
            .opacity(photographs.isAddingOne ? 0.5 : 1)
            .disabled(photographs.isAddingOne)
        }
        // Read when the sheet comes up and not before: the library is asked
        // about one day, at the moment somebody wants its photographs.
        .task(id: day) { await suggestions.look(for: day) }
        // The system's own picker, put up from here rather than from the
        // Entry behind, because a sheet cannot present anything while another
        // is covering it. The photograph as the library has it, rather than a
        // copy the system has already converted: which formats a journal
        // folder keeps is Aujour's own decision, and it should be the same one
        // whichever door a photograph came in by.
        .photosPicker(
            isPresented: $isPickingFromTheLibrary,
            selection: $pickedFromTheLibrary,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: pickedFromTheLibrary) { _, picked in
            guard let picked else { return }
            Task { await add(fromTheLibrary: picked) }
        }
        // Half the screen to begin with, and draggable to all of it: a day at
        // the seaside is two hundred photographs, and a sheet that could only
        // ever be half is one nobody can reach the bottom of.
        .presentationDetents([.medium, .large])
        .sheetChrome()
        .accessibilityIdentifier("photoSheet")
    }

    // MARK: - The day's own photographs

    /// The day's photographs, the offer to look for them, or a word that
    /// there are none to show — whichever the library's standing allows.
    @ViewBuilder private var fromThisDay: some View {
        switch suggestions.state {
        case .nothingToOffer:
            // A refused library, a device with none and a day the camera
            // missed all come to the same absence. Said in a line rather than
            // left as a gap, because a finger asked for a photo and the top
            // of the sheet is where the day's would have been.
            Section {
                Text("Nothing to show from this day.")
                    .foregroundStyle(Palette.inkMutedColor)
                    .accessibilityIdentifier("noPhotoSuggestions")
            }
            .settingsRows()

        case .couldLook:
            // The one place in Aujour that asks for a photo library besides
            // the `{{location}}` widget, and it asks because a finger landed
            // here. A day being opened never does.
            Section {
                Button("Show photos from this day", systemImage: "photo.on.rectangle.angled") {
                    Task { await suggestions.askToLook() }
                }
                .accessibilityIdentifier("showPhotoSuggestions")
            }
            .settingsRows()

        case .offering(let found):
            Section {
                // Lazily, because a day at the seaside is two hundred
                // photographs and only the first rows are ever on screen —
                // and a thumbnail is asked for by the square that shows it.
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: Self.narrowest, maximum: Self.square),
                            spacing: Spacing.close
                        )
                    ],
                    spacing: Spacing.close
                ) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { nth, photograph in
                        APhotographOfTheDay(
                            photograph: photograph,
                            suggestions: suggestions,
                            identifier: "photoSuggestion\(nth)",
                            add: { photograph in Task { await add(photograph) } }
                        )
                    }
                }
                .padding(.vertical, Spacing.tight)
            } header: {
                Text(headline(for: found.count))
                    // In the words the count was written in: a header is set
                    // in capitals by default, and "2 PHOTOS FROM THIS DAY" is
                    // a heading shouting about a count.
                    .textCase(nil)
                    .accessibilityIdentifier("photoSuggestions")
            }
            .settingsRows()
        }
    }

    /// "3 photos from this day" — the day's own count, because the sheet is
    /// about the day on screen and not about today.
    private func headline(for count: Int) -> String {
        count == 1 ? "1 photo from this day" : "\(count) photos from this day"
    }

    /// The most a square in the grid comes out at, and what a thumbnail is
    /// fetched for.
    ///
    /// `nonisolated` because it is also what the library sizes a thumbnail
    /// against, and that happens off the main actor — a square drawn at one
    /// size and fetched at another is somebody's whole photograph decoded and
    /// thrown away, once per square.
    nonisolated static let square: CGFloat = 150

    /// The least a square comes out at, which is what decides how many go in
    /// a row: three across a phone, more across a sheet on an iPad.
    private static let narrowest: CGFloat = 96

    // MARK: - Either door

    /// One tap on one of the day's photographs, and everything after it.
    private func add(_ photograph: DayPhotograph) async {
        finished(with: await photographs.insert(photograph, from: suggestions))
    }

    /// The other door: the system picker, or — in a UI test — the photograph
    /// the suite said it meant at launch, through the same pipeline. The
    /// picker is another process's screen, and driving it would make a test
    /// of the app into a test of that screen (`UITestingJournal`).
    private func chooseFromTheLibrary() {
        if let asked = UITestingJournal.photographToInsert() {
            Task { finished(with: await photographs.keep(asked)) }
        } else {
            isPickingFromTheLibrary = true
        }
    }

    /// What the picker handed back, into the folder.
    ///
    /// A photograph that would not be read goes no further and says nothing:
    /// a picker only hands back images, so this is the defensive answer
    /// rather than a case anybody meets.
    private func add(fromTheLibrary picked: PhotosPickerItem) async {
        pickedFromTheLibrary = nil
        guard let contents = try? await picked.loadTransferable(type: Data.self) else { return }
        finished(with: await photographs.keep(contents))
    }

    /// The photograph is in the folder, or the reason it is not has been set:
    /// either way the sheet has done what it can, and goes.
    ///
    /// It stays only when nothing happened at all — a photograph the picker
    /// could not read — which leaves the way to try again where it was.
    private func finished(with attachment: Attachment?) {
        if let attachment { insert(attachment) }
        guard attachment != nil || photographs.problem != nil else { return }
        dismiss()
    }
}

/// One square in the grid: the photograph, and the tap that puts it in the
/// day.
private struct APhotographOfTheDay: View {
    let photograph: DayPhotograph
    let suggestions: PhotoSuggestions

    /// What a UI test finds this one by. By position in the grid, which is
    /// the only thing about a photograph a test outside the app can know —
    /// the library's own name for it is the library's.
    let identifier: String

    let add: (DayPhotograph) -> Void

    /// The thumbnail, once the library has handed one over. A square of
    /// nothing until then, which is what a photograph still coming down from
    /// iCloud looks like.
    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            add(photograph)
        } label: {
            // Square whatever the column came out at, and the photograph
            // filling it edge to edge.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Rounding.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Rounding.control, style: .continuous))
        }
        // Its own tap, and not the row's: buttons left to a list's own style
        // all fire together when the row is tapped.
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        // A square of pixels has nothing to say for itself, and the one thing
        // that tells two of them apart in a day is when each was taken.
        .accessibilityLabel("Photo taken at \(photograph.takenAt.formatted(date: .omitted, time: .shortened))")
        // Asked for by the square that shows it.
        .task(id: photograph.id) {
            thumbnail = await suggestions.thumbnail(of: photograph).flatMap(UIImage.init(data:))
        }
    }
}
