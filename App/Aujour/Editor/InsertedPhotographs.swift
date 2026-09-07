import AujourCore
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// A photograph on its way into the day being written: the file written into
/// the Journal Root, and the embed that points at it.
///
/// ``EmbeddedPictures``'s other direction, and the same division of labour.
/// Where a photograph goes, what it is called there and how the Entry points
/// at it are decisions about paths, and are ``AujourCore/Attachment``'s —
/// unit-tested on Linux against the paths they come out as. What is left is
/// the half that needs a device: turning what was chosen into bytes a folder
/// can keep for good.
///
/// ## Two doors, one pipeline
///
/// A photograph is chosen on the sheet the photo key puts up (``PhotoSheet``),
/// and it arrives either as one of the day's own, handed over by the library,
/// or as whatever the system picker came back with. From there on the two are
/// the same photograph: converted where a vault could not hold it, written
/// under the Attachment Path Template for this Entry's Journal Day, and
/// answered as the embed to put at the caret — which is the sheet's to place,
/// since where the caret was is a thing only the editor knew.
///
/// ## Only one of those doors asks for anything
///
/// The system picker runs in a process of its own and hands back only what
/// was chosen, so a journal can have photographs in it without the app ever
/// being able to read the library. The day's own photographs are the ones
/// that need the library permission (``AujourCore/PhotoSuggestions``) — and a
/// refusal costs only those, because the other door is still open.
///
/// ## What a vault can hold
///
/// The photograph is kept as it is where the format is one anything can open,
/// and converted where it is not — which for an iPhone camera's HEIC is every
/// time. Which formats those are is ``AujourCore/AttachmentFormat``'s to say;
/// the conversion itself is here, because it is ImageIO's.
@MainActor
@Observable
final class InsertedPhotographs {
    /// What stopped the last photograph reaching the folder, if anything did.
    ///
    /// Said rather than swallowed. A picture that silently inserted nothing is
    /// the one outcome somebody would sit and repeat, and the folder failing
    /// is exactly when they would.
    private(set) var problem: StorageProblem?

    /// The Entry a photograph is being added to — weakly, because it is the
    /// day on screen and this is only the way of putting something in it.
    @ObservationIgnored private weak var entry: EntryEditor?

    /// Whether a photograph is on its way into the day right now.
    ///
    /// A photograph that is only in iCloud takes seconds to come down, and a
    /// grid of thumbnails is easy to tap twice — which without this would be
    /// two files in the folder and two embeds in the day for one photograph
    /// somebody wanted once. The sheet dims itself while it is true, so the
    /// wait is something they can see rather than a tap that did nothing.
    private(set) var isAddingOne = false

    /// Points this at the Entry now on screen.
    ///
    /// The day matters twice over: it names the file, and it renders the
    /// Attachment Path Template the file goes under — so a picture added on
    /// the morning an app left open overnight moves on belongs to the day it
    /// was added to and not the one that was open.
    func adds(to entry: EntryEditor) {
        self.entry = entry
        problem = nil
    }

    /// The user has seen what went wrong.
    func acknowledge() {
        problem = nil
    }

    /// Writes one of the day's own photographs into the folder, and answers
    /// the embed to put at the caret.
    ///
    /// A photograph the library will not hand over is said rather than
    /// swallowed, unlike a picker nobody chose from. Cancelling a picker is
    /// somebody changing their mind; tapping a photograph and getting nothing
    /// is the app failing to do the one thing that was asked, and an iCloud
    /// library that has not finished downloading is exactly when it happens.
    ///
    /// One at a time — see ``isAddingOne``.
    func insert(_ photograph: DayPhotograph, from suggestions: PhotoSuggestions) async -> Attachment? {
        await adding {
            guard let contents = await suggestions.contents(of: photograph) else {
                problem = StorageProblem(ThePhotographWouldNotCome())
                return nil
            }
            return await write(contents)
        }
    }

    /// Writes what the system picker handed back into the folder, and answers
    /// the embed to put at the caret.
    ///
    /// `nil` for every way of not ending with a picture in the day: the
    /// photograph could not be read, or the folder would not take it. Only
    /// the second is news, and it is the one that sets ``problem``.
    func keep(_ picked: Data) async -> Attachment? {
        await adding { await write(picked) }
    }

    /// One photograph at a time, and the last problem cleared before it.
    private func adding(_ work: () async -> Attachment?) async -> Attachment? {
        guard !isAddingOne else { return nil }
        isAddingOne = true
        defer { isAddingOne = false }

        problem = nil
        return await work()
    }

    /// The pipeline both doors go through: kept in a format a vault can hold,
    /// written into the Journal Root beside this Entry, and answered as the
    /// embed that points at it.
    private func write(_ picked: Data) async -> Attachment? {
        guard let entry, let (contents, format) = Self.keeping(picked) else { return nil }

        do {
            return try await entry.attach(contents, keeping: format)
        } catch {
            problem = StorageProblem(error)
            return nil
        }
    }

    // MARK: - What goes into the folder

    /// The bytes to write and the format they are in — the photograph itself
    /// where a vault can hold it, and a JPEG where it cannot.
    ///
    /// `nil` for data that is not an image at all, which is a photograph that
    /// was never going to be one on screen either.
    ///
    /// Internal so that the conversion can be asked for without a picker: what
    /// a HEIC becomes is the acceptance criterion, and the simulator is where
    /// there is an ImageIO to answer it.
    static func keeping(_ picked: Data) -> (contents: Data, format: AttachmentFormat)? {
        guard let source = CGImageSourceCreateWithData(picked as CFData, nil),
            let arrivedAs = CGImageSourceGetType(source) as String?
        else { return nil }

        let format = AttachmentFormat.keeping(arrivedAs)
        guard format.contentType != arrivedAs else { return (picked, format) }
        guard let converted = convert(source, to: format) else { return nil }
        return (converted, format)
    }

    /// Re-encodes a photograph in the format the folder keeps.
    ///
    /// From the *source* rather than from a decoded image, because that is
    /// what carries everything besides the pixels across: an iPhone photograph
    /// says which way up it is in its metadata rather than in its rows, and a
    /// re-encode that dropped that would turn every landscape photo on its
    /// side.
    private static func convert(_ source: CGImageSource, to format: AttachmentFormat) -> Data? {
        let converted = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                converted as CFMutableData, format.contentType as CFString, 1, nil
            )
        else { return nil }

        CGImageDestinationAddImageFromSource(
            destination, source, 0,
            // Visually lossless, and a fraction of the size: these go into
            // somebody's iCloud Drive and are synced to every device they own.
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return converted as Data
    }
}

/// A photograph the library would not hand over.
///
/// Almost always an iCloud photograph that is not on this device: PhotoKit is
/// asked to fetch it and says so when it cannot, and a minute later on a
/// better connection the same tap works.
private struct ThePhotographWouldNotCome: LocalizedError {
    var errorDescription: String? { "Aujour couldn't read that photo." }

    var recoverySuggestion: String? {
        "It may still be downloading from iCloud. Try again in a moment, or choose it from the library instead."
    }
}
