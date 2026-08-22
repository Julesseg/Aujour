import AujourCore
import ImageIO
import Observation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// A photograph on its way into the day being written: the system picker, the
/// file written into the Journal Root, and the embed that points at it.
///
/// ``EmbeddedPictures``'s other direction, and the same division of labour.
/// Where a photograph goes, what it is called there and how the Entry points
/// at it are decisions about paths, and are ``AujourCore/Attachment``'s —
/// unit-tested on Linux against the paths they come out as. What is left is
/// the half that needs a device: putting the picker on screen, and turning
/// what comes back into bytes a folder can keep for good.
///
/// ## Two doors, one pipeline
///
/// A photograph arrives either from the system picker on the accessory row or
/// from the suggestions panel below the day, and from there on the two are the
/// same photograph: converted where a vault could not hold it, written under
/// the Attachment Path Template for this Entry's Journal Day, and pointed at
/// by an embed at the caret. Only the way in differs, and only in one respect
/// — the picker takes the screen and the keyboard with it, so where the caret
/// *was* has to be read before it opens.
///
/// ## Only one of those doors asks for anything
///
/// `PHPickerViewController` runs in a process of its own and hands back only
/// what was chosen, so a journal can have photographs in it without the app
/// ever being able to read the library. The suggestions panel is the one that
/// needs the library permission (``AujourCore/PhotoSuggestions``) — and a
/// refusal costs only the panel, because this door is still open.
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

    /// How an embed reaches the text — set by the editor on screen, as
    /// ``EmbeddedPictures/whenOneArrives`` is, and for the same reason: the
    /// text view is built once and the view around it many times over.
    ///
    /// Only the suggestions panel needs it. A photograph from the picker is
    /// already inside a text view's own call, and the caret it goes at is the
    /// one read before the picker took the screen.
    @ObservationIgnored var writesTheEmbed: ((Attachment) -> Void)?

    /// Where a photograph comes from. The system picker in the app, and a
    /// photograph a test already has in a test — which is what lets everything
    /// after the picker be asked for headlessly, since the picker itself is
    /// another process's screen and the one part of this nothing here can
    /// drive.
    @ObservationIgnored private let picking: @MainActor (UIView) async -> Data?

    /// The system picker, which is where a photograph comes from in the app.
    convenience init() {
        self.init(picking: { view in await SystemPhotoPicker.photograph(over: view) })
    }

    init(picking: @escaping @MainActor (UIView) async -> Data?) {
        self.picking = picking
    }

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

    /// Puts the picker up over this view, writes what comes back into the
    /// folder, and answers the embed to put at the caret.
    ///
    /// `nil` for every way of not ending with a picture in the day: the picker
    /// was cancelled, the photograph could not be read, the folder would not
    /// take it. Only the last of those is news, and it is the one that sets
    /// ``problem``.
    func pick(over view: UIView) async -> Attachment? {
        guard entry != nil else { return nil }
        problem = nil

        guard let picked = await picking(view) else { return nil }
        return await write(picked)
    }

    /// Writes a photograph the suggestions panel offered into the folder, and
    /// puts its embed in the day.
    ///
    /// The panel's one tap, and everything after the tap. It ends by writing
    /// the embed itself rather than answering one, because the panel is a view
    /// beside the editor and not the editor: what it knows is which photograph
    /// was chosen, and where an embed goes in the text is the text view's
    /// (``writesTheEmbed``).
    ///
    /// A photograph the library will not hand over is said rather than
    /// swallowed, unlike a picker nobody chose from. Cancelling a picker is
    /// somebody changing their mind; tapping a photograph and getting nothing
    /// is the app failing to do the one thing that was asked, and an iCloud
    /// library that has not finished downloading is exactly when it happens.
    func insert(_ photograph: DayPhotograph, from suggestions: PhotoSuggestions) async {
        problem = nil
        guard let contents = await suggestions.contents(of: photograph) else {
            problem = StorageProblem(ThePhotographWouldNotCome())
            return
        }
        guard let attachment = await write(contents) else { return }
        writesTheEmbed?(attachment)
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
        "It may still be downloading from iCloud. Try again in a moment, or add it with the photo button above the keyboard."
    }
}

// MARK: - The picker

/// One photograph from the system picker, or none.
///
/// A `PHPickerViewController` presented over whatever is on screen, in the one
/// shape the editor can use it in: awaited. The picker's own answer arrives on
/// a delegate, and the delegate is this object — kept alive by itself for
/// exactly as long as the picker is up, because a picker holds its delegate
/// weakly and nothing else here has a reason to hold one.
@MainActor
private final class SystemPhotoPicker: NSObject, PHPickerViewControllerDelegate {
    private var answer: CheckedContinuation<Data?, Never>?

    /// Itself, while the picker is on screen. See above.
    private var whileItIsUp: SystemPhotoPicker?

    static func photograph(over view: UIView) async -> Data? {
        // A UI test cannot drive the system picker without becoming a test of
        // the system picker, so the suite says which photograph it means at
        // launch and it goes in through the same door — everything after this
        // point is the app's own code (`UITestingJournal`).
        if let asked = UITestingJournal.photographToInsert() { return asked }

        guard let presenter = view.viewControllerToPresentOver else { return nil }

        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        // The photograph as the library has it, rather than a copy the system
        // has already converted for us: which formats a journal folder keeps
        // is Aujour's own decision, and it should be the same one however a
        // photograph got here.
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        let picking = SystemPhotoPicker()
        picker.delegate = picking
        picking.whileItIsUp = picking

        return await withCheckedContinuation { continuation in
            picking.answer = continuation
            presenter.present(picker, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let chosen = results.first?.itemProvider,
            chosen.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        else { return finish(with: nil) }

        // The progress it hands back is for a screen that would show one; this
        // one is a picker being put away.
        _ = chosen.loadDataRepresentation(for: .image) { data, _ in
            Task { @MainActor in self.finish(with: data) }
        }
    }

    private func finish(with photograph: Data?) {
        answer?.resume(returning: photograph)
        answer = nil
        whileItIsUp = nil
    }
}

extension UIView {
    /// The view controller a sheet put up over this view belongs to.
    ///
    /// Found up the responder chain rather than handed in, because the view
    /// asking is a `UITextView` inside a SwiftUI hierarchy: the controller
    /// above it is one SwiftUI made and nothing in this file could have been
    /// given. Whatever it is already presenting comes first — presenting over
    /// a controller that is behind a sheet puts nothing on screen at all.
    fileprivate var viewControllerToPresentOver: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController {
                var presenting = controller
                while let presented = presenting.presentedViewController {
                    presenting = presented
                }
                return presenting
            }
            responder = next
        }
        return nil
    }
}
