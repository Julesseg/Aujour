import AujourCore
import SwiftUI
import UIKit

/// A day on its way to the system share sheet: the file it leaves as, and
/// getting it written.
///
/// Sending a day happens in two steps and this is the first of them. The file
/// is made *before* the sheet comes up — the PDF drawn, the photographs it
/// embeds waited for, the bytes on disk — so that what the user hands to Mail
/// or to Files or to a printer is a finished document rather than a promise
/// to make one. It is also why there is somewhere here for a failure to be
/// said: a share that quietly did nothing is the one outcome somebody would
/// sit and repeat.
///
/// Which day and what it says is ``AujourCore/EntryExport``'s; what a page
/// looks like is ``EntryPaper``'s. What is left here is the part that needs a
/// disk and a view hierarchy.
@MainActor
@Observable
final class SharedEntry {
    /// The file the share sheet is up for, and `nil` the rest of the time.
    ///
    /// Settable because the sheet clears it on the way down — that is what
    /// "the user is finished with it" looks like from here, and there is
    /// nothing else to do about it.
    var file: File?

    /// While the file is being made. A PDF of a long day with photographs in
    /// it is not instant, and a button that does nothing for a second is a
    /// button somebody presses twice.
    private(set) var isPreparing = false

    /// A file that could not be written, said where the user asked for it.
    private(set) var problem: StorageProblem?

    /// One day, written out, waiting to be handed over.
    ///
    /// A type around a URL rather than the URL itself, because `.sheet(item:)`
    /// wants something identifiable and a file path is not one.
    struct File: Identifiable, Equatable {
        let url: URL

        var id: URL { url }
    }

    /// Writes the day out in this form, and puts the share sheet up over it.
    ///
    /// - Parameter pictures: where the photographs an embed points at come
    ///   from — the ones the day on screen already found, so that the page
    ///   carries what the screen does. `nil` is a page where every embed is
    ///   the markdown it is, which is also what an embed naming nothing
    ///   comes out as.
    func share(
        _ export: EntryExport,
        as form: EntryExport.Form,
        drawnWith pictures: EmbeddedPictures? = nil
    ) async {
        // A second tap while the first is still drawing is the same request.
        guard !isPreparing else { return }
        isPreparing = true
        problem = nil
        defer { isPreparing = false }

        do {
            file = File(url: try await write(export, as: form, drawnWith: pictures))
        } catch {
            problem = StorageProblem(CouldNotPrepareTheFile(form: form, because: error))
        }
    }

    /// Puts away a failure the user has read.
    func acknowledge() {
        problem = nil
    }

    // MARK: - Writing it out

    private func write(
        _ export: EntryExport,
        as form: EntryExport.Form,
        drawnWith pictures: EmbeddedPictures?
    ) async throws -> URL {
        let folder = Self.scratch
        // Last time's file, on the way in rather than on the way out: while a
        // share sheet is up the system is still reading the URL it was handed,
        // and clearing it out from under one is how an AirDrop arrives empty.
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let file = folder.appending(path: export.fileName(as: form))
        switch form {
        case .plainText:
            // UTF-8 and nothing else: the file is the Entry's own characters,
            // which is what a text form means (ADR 0001).
            try Data(export.markdown.utf8).write(to: file, options: .atomic)
        case .pdf:
            await pictures?.findEverything(embeddedTargets(of: export.markdown))
            try EntryPaper(pictures: pictures).pdf(of: export).write(to: file, options: .atomic)
        }
        return file
    }

    /// The targets this day's embeds point at.
    ///
    /// Read the same way the editor reads them, which is the only way there
    /// is: Core says which stretches of an Entry are pictures and what each
    /// one names, from the text alone.
    private func embeddedTargets(of markdown: String) -> [String] {
        DrawnElements(EntryMarkdown(markdown), in: markdown, cursor: nil)
            .elements
            .compactMap { element in
                guard case .picture(let target) = element.kind else { return nil }
                return target
            }
    }

    /// Where the file is written: a folder of Aujour's own inside the
    /// system's scratch space, so that the one thing in it is the one thing
    /// being shared and clearing it can never reach anything else.
    ///
    /// Temporary on purpose. An exported day is a copy handed to something
    /// else; the journal is the folder, and nothing Aujour makes for a share
    /// sheet belongs in it.
    private static var scratch: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Sharing", directoryHint: .isDirectory)
    }
}

/// A day that could not be got ready to send.
///
/// Its own words rather than the folder's, because nothing about the journal
/// has gone wrong: the Entry is where it was, and what failed is a copy of it
/// on the way out.
private struct CouldNotPrepareTheFile: LocalizedError {
    let form: EntryExport.Form
    let because: any Error

    var errorDescription: String? {
        switch form {
        case .pdf: "Aujour couldn't make a PDF of this day."
        case .plainText: "Aujour couldn't get this day ready to send."
        }
    }

    var recoverySuggestion: String? {
        "Your entry hasn't been touched — it's still in its folder. Try again in a moment; if it keeps happening, check that the device has room."
    }
}

/// The system share sheet, over a file Aujour has already written.
///
/// A file rather than a string or an image, and the same for both forms: it
/// is what every destination understands. Mail attaches it, Files saves it,
/// AirDrop sends it, and Print prints it — and it arrives named after the day
/// it is, which is what makes a folder of exported entries worth keeping.
struct ShareSheet: UIViewControllerRepresentable {
    let file: SharedEntry.File

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    }

    func updateUIViewController(_ sheet: UIActivityViewController, context: Context) {}
}
