import AujourCore
import SwiftUI
import UIKit

/// The editor an Entry is written in: markdown, styled where it is typed.
///
/// A `UITextView` rather than SwiftUI's `TextEditor`, for the one reason that
/// matters — its text storage. Styling markdown while it is being written
/// means restyling only the paragraph a keystroke landed in, and the storage
/// is the only place that sees every change and can answer it that precisely.
/// Everything else here is the same editor as before: the text is bound to
/// ``EntryEditor/content``, so a keystroke is an edit the Entry knows to save.
///
/// The view holds no rules and no markdown knowledge. What the text *is* comes
/// from ``EntryMarkdown`` in Core, and what that looks like from
/// ``MarkdownStyling`` beside it. All this adds is the two things only a text
/// view knows: what was typed, and where the cursor is — the second because
/// the marks around the cursor are shown and the rest are not, which is what
/// makes the Entry read like a document while staying markdown under the hand
/// writing it.
struct MarkdownEditor: UIViewRepresentable {
    /// The Entry's text — the file's own words, and nothing the editor added.
    @Binding var text: String

    /// What a UI test finds this by, and what VoiceOver calls it. Set on the
    /// text view itself rather than through SwiftUI's accessibility
    /// modifiers, which would describe the wrapper instead of the thing being
    /// typed in.
    let identifier: String
    let label: String

    func makeUIView(context: Context) -> UITextView {
        let styling = MarkdownStyling()
        let storage = MarkdownTextStorage(styling: styling)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        // What makes this a live preview rather than a styled source view: the
        // syntax the storage marked hidden is not turned into glyphs at all.
        // Held by the coordinator, because a layout manager does not keep its
        // delegate alive.
        layoutManager.delegate = context.coordinator.glyphs
        // A day can run to thousands of words, and laying all of them out to
        // show the first screenful is the wait the user would feel.
        layoutManager.allowsNonContiguousLayout = true
        container.widthTracksTextView = true

        let textView = UITextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.typingAttributes = styling.baseAttributes

        // The three substitutions that would put characters in the file that
        // nobody typed. A curly quote is a fine thing in prose and a wrong
        // thing in `code`, and an em dash where `--` was typed is a markdown
        // rule silently rewritten — and both would reach Obsidian as somebody
        // else's edit (ADR 0001).
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        textView.accessibilityIdentifier = identifier
        textView.accessibilityLabel = label

        storage.setSource(text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // The coordinator outlives this struct, which is rebuilt on every
        // keystroke; the binding it writes back through has to be this one.
        context.coordinator.text = $text
        textView.accessibilityLabel = label

        guard let storage = textView.textStorage as? MarkdownTextStorage else { return }

        // Dynamic Type: the font everything else is derived from has moved, so
        // everything is drawn again. Compared by font rather than by whole
        // styling, because this runs on every keystroke and restyling a long
        // day for a colour that only looks new would undo the point of the
        // storage below.
        let body = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: textView.traitCollection
        )
        if storage.styling.body != body {
            storage.styling = storage.styling.with(body: body)
            textView.typingAttributes = storage.styling.baseAttributes
        }

        // Only when the text came from somewhere other than this text view —
        // the day being opened, or the file having moved on underneath it.
        // What the user just typed is already here, and putting it back would
        // take the cursor with it.
        guard textView.text != text else { return }

        let caret = textView.selectedRange
        storage.setSource(text)
        // Wherever it was, if there is still a there: a version arriving from
        // iCloud can be shorter than the one on screen.
        let length = (text as NSString).length
        textView.selectedRange = NSRange(location: min(caret.location, length), length: 0)
        storage.cursor = textView.selectedRange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    /// Carries what was typed back to the Entry, and where the cursor is back
    /// to the storage.
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        /// Kept for as long as the text view is, because the layout manager
        /// holds its delegate weakly.
        let glyphs = HiddenSyntaxGlyphs()

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// Every tap, every arrow key, every drag over a word — and the caret
        /// moving as something is typed. The storage draws the element the
        /// cursor is in differently from the rest of the day, so it has to
        /// hear about all of them.
        func textViewDidChangeSelection(_ textView: UITextView) {
            storage(of: textView)?.cursor = textView.selectedRange
        }

        /// Tapping back in without moving the caret: the same selection as
        /// before, so no change is announced, and the element it is in has to
        /// be revealed again by hand.
        func textViewDidBeginEditing(_ textView: UITextView) {
            storage(of: textView)?.cursor = textView.selectedRange
        }

        /// The keyboard going down, and with it the last revealed element. A
        /// day nobody is writing in is a day being read, and it reads as a
        /// document — no hashes left over around the heading that happened to
        /// be edited last.
        func textViewDidEndEditing(_ textView: UITextView) {
            storage(of: textView)?.cursor = nil
        }

        private func storage(of textView: UITextView) -> MarkdownTextStorage? {
            textView.textStorage as? MarkdownTextStorage
        }
    }
}
