import AujourCore
import UIKit

/// The pictures an Entry's embeds point at, as an editor needs them: at once,
/// or not at all yet.
///
/// Drawing happens a paragraph at a time while somebody is typing, and reading
/// a photo off iCloud does not. So this answers immediately with whatever it
/// already has, goes and looks for the rest, and says when something arrived —
/// at which point the editor draws that paragraph again and the picture is
/// there. Until then the embed is its own markdown on screen, which is what an
/// embed that names nothing stays as for good.
///
/// ## Not there is an answer
///
/// A target naming no file in the folder is not an error and not a placeholder
/// box: the embed is drawn as the text it is, visible and harmless and exactly
/// what Obsidian shows for the same line. That is the whole of "unresolvable
/// targets degrade to visible text", and it falls out of answering `nil` — the
/// editor only stands a picture in front of characters when it has one.
///
/// Remembered either way, so that a day with a broken embed in it does not
/// search the folder again on every keystroke. A day is reopened often enough
/// — every launch, every time it is come back to — that a file which arrives
/// later is found soon enough, and a file that arrives *while the day is open*
/// is what the folder's own change notice reopens it for.
@MainActor
final class EmbeddedPictures {
    /// What to do when a picture has been found: draw the Entry again, so
    /// that the paragraph holding the embed can stand it in front of its
    /// markdown.
    var whenOneArrives: (() -> Void)?

    private var found: [String: UIImage] = [:]
    private var looked: Set<String> = []
    private var looking: Set<String> = []

    private var folder: (any JournalStore)?
    private var entryPath: String?

    /// Points this at the Entry now on screen.
    ///
    /// Everything already found is forgotten when the Entry changes, because
    /// a target is relative to the Entry that wrote it: `market.jpg` in
    /// March's day and `market.jpg` in April's are allowed to be two
    /// different photographs.
    func look(in folder: any JournalStore, beside entryPath: String?) {
        guard self.entryPath != entryPath else {
            self.folder = folder
            return
        }
        self.folder = folder
        self.entryPath = entryPath
        found = [:]
        looked = []
        looking = []
    }

    /// The picture at this target, if it has been found — and if it has not,
    /// `nil` now and a look for it.
    ///
    /// Answered from wherever the drawing is happening rather than awaited,
    /// because the drawing is a text storage restyling a paragraph and there
    /// is nowhere in that to wait. Which thread that is, is not in doubt: a
    /// text storage is edited and laid out on the main one, from the same run
    /// loop the typing arrives on.
    nonisolated func picture(for target: String) -> UIImage? {
        MainActor.assumeIsolated { pictureOnHand(for: target) }
    }

    private func pictureOnHand(for target: String) -> UIImage? {
        if let picture = found[target] { return picture }
        guard !looked.contains(target), !looking.contains(target) else { return nil }

        looking.insert(target)
        Task { await goAndLook(for: target) }
        return nil
    }

    private func goAndLook(for target: String) async {
        let picture = await find(target)
        looking.remove(target)
        looked.insert(target)
        guard let picture else { return }
        found[target] = picture
        whenOneArrives?()
    }

    /// Where the target might be, asked of the folder in order — and for a
    /// bare wiki name that was nowhere obvious, a look through the whole
    /// folder for a file of that name, which is what `![[market.jpg]]` means.
    private func find(_ target: String) async -> UIImage? {
        guard let folder else { return nil }

        for path in EmbedTarget.candidates(for: target, inEntryAt: entryPath) {
            if let picture = await picture(at: path, in: folder) { return picture }
        }
        guard let files = try? await folder.listFiles(),
            let named = EmbedTarget.match(target, among: files)
        else { return nil }
        return await picture(at: named, in: folder)
    }

    private func picture(at path: String, in folder: any JournalStore) async -> UIImage? {
        // Every failure is the same answer here: no file, an unreadable one, a
        // path the store refuses. The embed is drawn as its own text, which is
        // what it should be for all three.
        guard let data = try? await folder.read(at: path) else { return nil }
        return await EmbeddedPictures.decode(data)
    }

    /// Off the main actor, because a photograph is megabytes and decoding one
    /// where the typing happens is the typing stopping.
    private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached { UIImage(data: data)?.preparingForDisplay() }.value
    }
}
