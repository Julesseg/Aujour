import SwiftUI
import UIKit

import AujourCore

/// The day's own photographs, offered under the day being written.
///
/// A journal is written in the evening about a day that is already on the
/// phone in pictures. This is the shortest way between the two: a strip of
/// what the camera has from this Journal Day, where one tap writes it into
/// the folder and points the Entry at it — the same pipeline the picker's
/// photographs go through, and the same markdown at the end of it.
///
/// The view holds no rules. Which photographs belong to the day, whether there
/// is a panel at all and what asking for the library means are
/// ``AujourCore/PhotoSuggestions``'s, unit-tested on Linux; what is here is
/// the strip, the words for a count, and the pixels.
///
/// Nothing at all, most of the time. A refused library, a device with none and
/// a day the camera missed all come to the same absence — and none of them is
/// worth a sentence in front of somebody who is writing, because the photo
/// button above the keyboard is still there and still needs no permission.
struct PhotoSuggestionsPanel: View {
    let suggestions: PhotoSuggestions

    /// What one tap does — the attachment pipeline, and the embed at the
    /// caret. Handed in rather than done here for the reason the day's
    /// photographs are read elsewhere: this is the strip.
    let insert: (DayPhotograph) -> Void

    /// Whether one is already on its way into the day. A photograph that is
    /// only in iCloud takes seconds to come down, and a strip that looked
    /// exactly the same throughout would be one somebody taps again.
    var isAddingOne = false

    var body: some View {
        switch suggestions.state {
        case .nothingToOffer:
            EmptyView()

        case .couldLook:
            // The one place in Aujour that asks for a photo library, and it
            // asks because a finger landed here. A day being opened never
            // does: an alert in front of an Entry that is meant to be
            // appearing is the thing this whole seam is shaped to avoid.
            Button {
                Task { await suggestions.askToLook() }
            } label: {
                Label("Show photos from this day", systemImage: "photo.on.rectangle.angled")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityIdentifier("showPhotoSuggestions")
            .background(.thinMaterial)

        case .offering(let photographs):
            VStack(alignment: .leading, spacing: 6) {
                Text(headline(for: photographs.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("photoSuggestions")

                ScrollView(.horizontal) {
                    // Lazily, because a day at the seaside is two hundred
                    // photographs and only the first few are ever on screen —
                    // and a thumbnail is asked for by the square that shows it.
                    LazyHStack(spacing: 6) {
                        ForEach(Array(photographs.enumerated()), id: \.element.id) { nth, photo in
                            SuggestedPhotograph(
                                photograph: photo,
                                suggestions: suggestions,
                                identifier: "photoSuggestion\(nth)",
                                insert: insert
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
                // As tall as the squares in it and no taller. A horizontal
                // scroll view is happy to be any height at all, and one left
                // to itself in a safe-area inset takes the whole screen —
                // which leaves the day being written in nothing to write in.
                .frame(height: Self.square)
            }
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .opacity(isAddingOne ? 0.5 : 1)
            // The taps are refused underneath this too (``InsertedPhotographs``),
            // because a strip is easy to hit twice and this is only what says
            // so.
            .disabled(isAddingOne)
        }
    }

    /// A thumb's worth of photograph, and what the strip is as tall as.
    ///
    /// `nonisolated` because it is also what the library sizes a thumbnail
    /// against, and that happens off the main actor — a square drawn at one
    /// size and fetched at another is somebody's whole photograph decoded and
    /// thrown away, once per square.
    nonisolated static let square: CGFloat = 64

    /// "3 photos from this day" — the day's own count, because the panel is
    /// about the day on screen and not about today.
    private func headline(for count: Int) -> String {
        count == 1 ? "1 photo from this day" : "\(count) photos from this day"
    }
}

/// One square in the strip: the photograph, and the tap that puts it in the
/// day.
private struct SuggestedPhotograph: View {
    let photograph: DayPhotograph
    let suggestions: PhotoSuggestions

    /// What a UI test finds this one by. By position in the strip, which is
    /// the only thing about a photograph a test outside the app can know —
    /// the library's own name for it is the library's.
    let identifier: String

    let insert: (DayPhotograph) -> Void

    /// The thumbnail, once the library has handed one over. A square of
    /// nothing until then, which is what a photograph still coming down from
    /// iCloud looks like.
    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            insert(photograph)
        } label: {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: PhotoSuggestionsPanel.square, height: PhotoSuggestionsPanel.square)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        // A square of pixels has nothing to say for itself, and the one thing
        // that tells two of them apart in a day is when each was taken.
        .accessibilityLabel("Photo taken at \(photograph.takenAt.formatted(date: .omitted, time: .shortened))")
        // Asked for by the square that shows it, and asked again when the day
        // changes underneath the strip.
        .task(id: photograph.id) {
            thumbnail = await suggestions.thumbnail(of: photograph).flatMap(UIImage.init(data:))
        }
    }
}
