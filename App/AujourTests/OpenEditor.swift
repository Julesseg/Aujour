import AujourCore
import SwiftUI
import UIKit

@testable import Aujour

/// A day open in the editor the app builds — a text view over the markdown
/// storage, laid out, with the coordinator that answers a finger on a box and
/// a press on the accessory row.
///
/// The real thing rather than a stand-in: what a tap does is the coordinator's
/// to answer, and standing in for it here would be testing the stand-in. What
/// it does *not* have is a keyboard, a screen or a run loop — a storage with a
/// layout manager attached is enough to ask how big anything came out and what
/// a control did to the text.
@MainActor
final class OpenEditor {
    /// Standing in for the Entry the editor is bound to: what the app would be
    /// saving. `nil` until something tells it anything.
    private final class Entry {
        var text: String?
    }

    let textView: UITextView
    let coordinator: MarkdownEditor.Coordinator
    /// Held because a layout manager keeps neither its delegate nor its text
    /// storage alive.
    let glyphs: MarkdownGlyphs
    let storage: MarkdownTextStorage

    private let entry = Entry()

    /// What the Entry has been told, or `nil` if it has been told nothing.
    var written: String? { entry.text }

    init(holding source: String, styling: MarkdownStyling = MarkdownStyling()) {
        let storage = MarkdownTextStorage(styling: styling)
        let layoutManager = MarkdownLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude)
        )
        let glyphs = MarkdownGlyphs()

        layoutManager.delegate = glyphs
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.widthTracksTextView = true

        let textView = UITextView(
            frame: CGRect(x: 0, y: 0, width: 350, height: 400), textContainer: container
        )
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        self.textView = textView
        self.storage = storage
        self.glyphs = glyphs

        let entry = self.entry
        coordinator = MarkdownEditor.Coordinator(
            text: Binding(get: { entry.text ?? source }, set: { entry.text = $0 })
        )
        textView.delegate = coordinator
        coordinator.ticksBoxes(in: textView)
        coordinator.formats(in: textView)

        storage.setSource(source)
        layoutManager.ensureLayout(for: container)
    }

    /// Where the first line's box is: a little in from the top left of the
    /// text, which is where a finger goes.
    var firstBox: CGPoint {
        CGPoint(
            x: textView.textContainerInset.left + 8,
            y: textView.textContainerInset.top + 8
        )
    }

    /// Puts the cursor somewhere, the way tapping into the day would.
    func cursor(at location: Int, length: Int = 0) {
        textView.selectedRange = NSRange(location: location, length: length)
    }

    /// Offers the editor a keystroke, and says whether it let the text view
    /// have it — which is the question the return key in a list is the one
    /// answer to.
    func typed(_ keystroke: String, at range: NSRange) -> Bool {
        coordinator.textView(textView, shouldChangeTextIn: range, replacementText: keystroke)
    }
}
