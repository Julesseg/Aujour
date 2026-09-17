import SwiftUI
import UIKit

import AujourCore

/// The Suggestions key pressed, and the way back into the Entry for what is
/// tapped on the sheet it puts up.
///
/// ``PhotoRequest``'s twin, and shaped like it for the same reason: the key is
/// pressed on a text view and the tapping happens on a sheet, so what crosses
/// between them is where the caret was, folded into a closure that writes
/// its attachment there, and a word for when the sheet has gone.
struct SuggestionsRequest: Identifiable {
    /// New for every press, so that pressing the key twice puts the sheet up
    /// twice.
    let id = UUID()

    /// Writes this photograph into the Entry where the caret was when the key
    /// was pressed.
    let insert: (Attachment) -> Void

    /// The sheet has gone, with or without anything written. Somebody who
    /// pressed a key above the keyboard was writing, and the keyboard is asked
    /// back.
    let finished: () -> Void
}

/// The sheet the Suggestions key puts up: the day's own material, offered to
/// be written into it.
///
/// A journal is written in the evening about a day that is already on the
/// phone — in pictures, in the calendar, in what the list said — so the
/// shortest way between the two is a sheet of that day's own things, one tap
/// each. Everything on it is an insertion, which is why it is reached from the
/// row above the keyboard and nowhere else: an insertion needs a caret, and a
/// day being read has none.
///
/// One section per kind, drawn only where there is something to offer, and one
/// line for the whole sheet where there is nothing in any of them. The
/// photographs are what M1 has; the day's events and its reminders come next,
/// and arrive as two more sections under this one.
///
/// The sheet holds no rules. Which photographs belong to the day, whether
/// there is anything to offer and what asking for the library means are
/// ``AujourCore/PhotoSuggestions``'s, unit-tested on Linux; what a tapped
/// photograph becomes on its way into the folder is ``InsertedPhotographs``'s;
/// where the markdown lands is the editor's (``SuggestionsRequest``). What is
/// here is the grid, the words for a count, and the offer to look.
struct SuggestionsSheet: View {
    /// The Journal Day being written about, whose material is offered — a
    /// Monday filled in on Friday is offered Monday's.
    let day: JournalDay

    /// The pipeline into the folder, and the one place that says whether a
    /// photograph is already on its way.
    let photographs: InsertedPhotographs

    /// Where a tapped photograph goes — the request's own closure, which knows
    /// where the caret was.
    let insert: (Attachment) -> Void

    /// The day's photographs, read out of the library for the day on screen.
    /// Made with the sheet and gone with it: the library is read when it is
    /// looked at and not while the day is being written.
    @State private var suggestions: PhotoSuggestions

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - day: the Journal Day whose material is offered.
    ///   - library: where its photographs are read from. `nil` is a sheet with
    ///     no library behind it — nothing from the day, ever, which is what a
    ///     preview and a test of something else want.
    ///   - photographs: the way a tapped photograph reaches the folder.
    ///   - insert: the way a photograph reaches the Entry.
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
                thePhotographs
                nothingAtAll
            }
            // The sheet's own paper rather than the system's grouped grey, and
            // the rows on the identity's card — the same ground the place
            // widget's list stands on (`PlaceWidget`), so that one sheet looks
            // like one app whichever key put it up.
            .scrollContentBackground(.hidden)
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelSuggestions")
                }
            }
            // Dimmed while a photograph is on its way. One that is only in
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
        // Half the screen to begin with, and draggable to all of it: a day at
        // the seaside is two hundred photographs, and a sheet that could only
        // ever be half is one nobody can reach the bottom of.
        .presentationDetents([.medium, .large])
        .sheetChrome()
        .accessibilityIdentifier("suggestionsSheet")
    }

    // MARK: - Nothing to suggest

    /// The one line the sheet says about itself, and only where every section
    /// has come up empty and there is nothing left to ask about.
    ///
    /// Once for the whole sheet rather than once per section: a day with no
    /// photographs has no photograph section rather than a sentence saying so,
    /// and only a day with nothing in any of them says so (`CONTEXT.md`,
    /// **Suggestions**).
    @ViewBuilder private var nothingAtAll: some View {
        if suggestions.state == .nothingToOffer {
            Section {
                Text("Nothing to suggest from this day.")
                    .foregroundStyle(Palette.inkMutedColor)
                    .accessibilityIdentifier("nothingToSuggest")
            }
            .settingsRows()
        }
    }

    // MARK: - The day's own photographs

    /// The day's photographs, or the offer to look for them — and nothing at
    /// all where the library is refused, this device has none, or the camera
    /// missed the day.
    ///
    /// The one thing always drawn is the offer: a permission nobody has been
    /// asked about is a button in the words of the thing it would read, and
    /// tapping it is what asks — never opening the day, and never opening the
    /// sheet.
    @ViewBuilder private var thePhotographs: some View {
        switch suggestions.state {
        case .nothingToOffer:
            // Said once for the sheet, by `nothingAtAll` above, and not here:
            // a section that drew its own absence would be a sentence about
            // photographs on a day whose meetings are the thing on offer.
            EmptyView()

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

    // MARK: - One tap

    /// One tap on one of the day's photographs, and everything after it.
    ///
    /// A photograph closes the sheet: it did what it was for. It closes on a
    /// failure too, because what went wrong is said under the day
    /// (``EntryView``) and a notice behind a sheet is a notice nobody reads.
    /// It stays only when nothing happened at all, which leaves the way to try
    /// again where it was.
    private func add(_ photograph: DayPhotograph) async {
        let attachment = await photographs.insert(photograph, from: suggestions)
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
