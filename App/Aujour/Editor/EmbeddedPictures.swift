import AujourCore
import UIKit

/// The pictures an Entry's embeds point at, as an editor needs them: at once,
/// or not at all yet.
///
/// Drawing happens a paragraph at a time while somebody is typing, and reading
/// a photo off iCloud does not. So this answers immediately with whatever it
/// already has, goes and asks the Entry for the rest, and says when something
/// arrived — at which point the editor draws that paragraph again and the
/// picture is there. Until then the embed is its own markdown on screen, which
/// is what an embed naming nothing stays as for good.
///
/// Which file a target means is not decided here. That is a question about the
/// Journal Root and the Entry's own path — domain, and `EntryEditor`'s to
/// answer (`AujourCore/EntryEditor/attachment(named:)`). What is left is the
/// half that needs a screen: turning bytes into a picture, and remembering it.
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
/// search the folder again on every keystroke — and forgotten again when the
/// app comes back to the front, which is when a photo iCloud was still
/// bringing down is likely to have arrived
/// (``lookAgainForWhatWasMissing()``).
@MainActor
final class EmbeddedPictures {
    /// What to do when a picture has been found: draw the Entry again, so
    /// that the paragraph holding the embed can stand it in front of its
    /// markdown.
    var whenOneArrives: (() -> Void)?

    private var found: [String: UIImage] = [:]
    private var looked: Set<String> = []
    private var looking: Set<String> = []

    /// The Entry whose embeds these are — weakly, because it is the day on
    /// screen and this is only a drawer of what it holds.
    private weak var entry: EntryEditor?

    /// Points this at the Entry now on screen, forgetting everything the last
    /// one pointed at.
    ///
    /// Forgetting, because a target is relative to the Entry that wrote it:
    /// `market.jpg` in March's day and `market.jpg` in April's are allowed to
    /// be two different photographs, and so are the same day's two versions in
    /// two folders after the user moves their journal.
    ///
    /// Cheap because it is rare — this is called when the day on screen
    /// becomes a different day, not when somebody types.
    func look(in entry: EntryEditor) {
        self.entry = entry
        found = [:]
        looked = []
        looking = []
    }

    /// Forgets the targets that were not there, and keeps the pictures that
    /// were.
    ///
    /// What the app coming back to the front means for an embed: the folder is
    /// shared, so the photo an Entry names can arrive after the Entry did —
    /// iCloud bringing it down, or Obsidian on another device putting it
    /// there. Without this, a "not there" stands for as long as the day is
    /// open, and the embed nobody could draw stays undrawable until the day is
    /// left and come back to.
    ///
    /// Only the failures, because a picture already found is the same picture:
    /// re-reading every photograph in the day on every foreground would be
    /// paying a folder read for an answer nothing has changed.
    func lookAgainForWhatWasMissing() {
        guard !looked.isEmpty else { return }
        looked = []
        whenOneArrives?()
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

    /// Finds every one of these, and waits until it has.
    ///
    /// The one place anything here waits. Drawing an Entry cannot — a
    /// keystroke has nowhere to put a folder read — so on screen a picture
    /// that has not arrived is the embed's own markdown for a moment, and the
    /// paragraph is drawn again when it lands. A page being exported has no
    /// second chance: it is drawn once and sent, and a page carrying
    /// `![the market](…)` where the photograph should be is a page nobody
    /// meant to share.
    ///
    /// One after another, because a day holds a handful of photographs and
    /// not a library — and because the ones already found cost nothing, which
    /// is nearly all of them by the time anybody asks. A target that is not
    /// there stays not there, which is the same answer the editor draws.
    func findEverything(_ targets: [String]) async {
        for target in Set(targets) where found[target] == nil {
            looking.insert(target)
            await goAndLook(for: target)
        }
    }

    /// The same wait, asked of a day rather than of a list of targets: finds
    /// every photograph this markdown embeds.
    ///
    /// Which stretches of an Entry are pictures and what each one names is
    /// read the same way the editor reads them, which is the only way there
    /// is: Core says so, from the text alone. Here rather than at each caller
    /// because both of them — the page that is drawn to be sent and the page
    /// drawn to be looked at first — have to find the same photographs, or the
    /// preview is of a different document.
    func findEverything(embeddedIn markdown: String) async {
        await findEverything(
            DrawnElements(EntryMarkdown(markdown), in: markdown, cursor: nil)
                .elements
                .compactMap { element in
                    guard case .picture(let target) = element.kind else { return nil }
                    return target
                }
        )
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

    private func find(_ target: String) async -> UIImage? {
        guard let contents = await entry?.attachment(named: target) else { return nil }
        return await EmbeddedPictures.decode(contents)
    }

    /// Off the main actor, because a photograph is megabytes and decoding one
    /// where the typing happens is the typing stopping.
    private static func decode(_ contents: Data) async -> UIImage? {
        await Task.detached { UIImage(data: contents)?.preparingForDisplay() }.value
    }
}
