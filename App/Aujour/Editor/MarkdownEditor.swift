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

    /// Where the pictures this Entry's embeds point at come from. Already
    /// aimed at the day on screen by whoever owns it, because which folder and
    /// which Entry is not a thing a text view knows.
    let pictures: EmbeddedPictures

    /// What a UI test finds this by, and what VoiceOver calls it. Set on the
    /// text view itself rather than through SwiftUI's accessibility
    /// modifiers, which would describe the wrapper instead of the thing being
    /// typed in.
    let identifier: String
    let label: String

    func makeUIView(context: Context) -> UITextView {
        let styling = MarkdownStyling()
        let storage = MarkdownTextStorage(styling: styling)
        // Its own layout manager, because a box and a picture are painted
        // where their glyphs ended up and nothing above the layout knows
        // where that is.
        let layoutManager = MarkdownLayoutManager()
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

        // A picture arriving from the folder is the one change to an Entry
        // that nobody typed, so it is the one that has to ask for the drawing
        // again. Weakly, because the pictures outlive this text view when the
        // day on screen changes.
        storage.pictures = pictures
        pictures.whenOneArrives = { [weak storage] in storage?.aPictureArrived() }

        context.coordinator.ticksBoxes(in: textView)
        storage.setSource(text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // The coordinator outlives this struct, which is rebuilt on every
        // keystroke; the binding it writes back through has to be this one.
        context.coordinator.text = $text
        textView.accessibilityLabel = label

        guard let storage = textView.textStorage as? MarkdownTextStorage else { return }
        storage.pictures = pictures

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
        storage.cursor = context.coordinator.cursorIfSomebodyIsWriting(in: textView)
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
        let glyphs = MarkdownGlyphs()

        /// The gesture that ticks boxes, kept so that the delegate below can
        /// tell it apart from every gesture a text view has of its own.
        fileprivate var tick: UITapGestureRecognizer?

        init(text: Binding<String>) {
            self.text = text
        }

        // MARK: - Ticking a box

        /// Makes the boxes tappable.
        ///
        /// A gesture of its own rather than the text view's own tap, because
        /// the two want opposite things from the same finger: a tap on a box
        /// should tick it and leave the caret where it was, and a tap on
        /// anything else should put the caret there. So this one is offered
        /// first, answers only over a box, and the text view's tap waits to
        /// see whether it did.
        func ticksBoxes(in textView: UITextView) {
            let tick = UITapGestureRecognizer(target: self, action: #selector(tickTheBoxTapped))
            tick.delegate = self
            self.tick = tick
            textView.addGestureRecognizer(tick)
        }

        /// Ticks or unticks the box the tap landed on.
        ///
        /// One character of the Entry changes, and the file is plain markdown
        /// before and after — a task Aujour ticked and a task Obsidian ticked
        /// are the same file (ADR 0001).
        @objc private func tickTheBoxTapped(_ tap: UITapGestureRecognizer) {
            guard let textView = tap.view as? UITextView else { return }
            tickTheBox(in: textView, at: tap.location(in: textView))
        }

        /// Ticks the box at this point, and says whether there was one.
        ///
        /// Internal so that both halves of a tap — finding the box under a
        /// finger, and the rewrite it makes — can be asked for without a
        /// simulator; the gesture above is then the only part left that needs
        /// one.
        @discardableResult
        func tickTheBox(in textView: UITextView, at point: CGPoint) -> Bool {
            guard let edit = box(in: textView, under: point) else { return false }

            let selection = textView.selectedRange
            textView.textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            // Put back where it was, if it was anywhere. Ticking something off
            // is not a claim about where the user was writing, and a caret
            // that jumped to the box would reveal that line's markdown under
            // the finger that just tapped it.
            textView.selectedRange = selection
            // The text view announces what it was told to change, not what
            // this told its storage — so the Entry is told here, and hears
            // about a tick exactly as it hears about a keystroke.
            text.wrappedValue = textView.text
            return true
        }

        /// The edit a tap at this point would make, or `nil` for a tap that
        /// landed on words.
        ///
        /// The glyph nearest the tap is not enough on its own: a text view
        /// answers that question for a point anywhere on the screen, so a tap
        /// three lines below the last one would tick the last box in the day.
        /// The room that glyph took has to hold the tap as well, which is the
        /// difference between tapping a box and tapping near one.
        private func box(in textView: UITextView, under point: CGPoint) -> MarkdownEdit? {
            guard let storage = textView.textStorage as? MarkdownTextStorage,
                let layout = textView.layoutManager as? MarkdownLayoutManager
            else { return nil }

            // Into the text's own coordinates, which the inset moved.
            let inText = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            let glyph = layout.glyphIndex(for: inText, in: textView.textContainer)
            let room = layout.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: textView.textContainer
            )
            guard forAFinger(room).contains(inText) else { return nil }
            return storage.tickingTheBox(at: layout.characterIndexForGlyph(at: glyph))
        }

        /// A box's room, widened to something a thumb can hit: a checkbox is
        /// about twenty points square, and a finger is not.
        ///
        /// Safe to be generous, because the box has already had to be the
        /// glyph *nearest* the tap. A finger on the word after it is nearest
        /// that word, and this is never asked; what the widening reaches is
        /// the margin around the box and the inset above the first line, which
        /// is where a tap aimed at the box lands when it misses.
        private func forAFinger(_ room: CGRect) -> CGRect {
            let comfortable: CGFloat = 44
            return room.insetBy(
                dx: min(0, (room.width - comfortable) / 2),
                dy: min(0, (room.height - comfortable) / 2)
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// Every tap, every arrow key, every drag over a word — and the caret
        /// moving as something is typed. The storage draws the element the
        /// cursor is in differently from the rest of the day, so it has to
        /// hear about all of them.
        ///
        /// Unless nobody is writing here. A text view has a selection whether
        /// or not anybody is in it — a day just put on screen reports a caret
        /// at its very start — and taking that for a cursor would open every
        /// Entry with its first line's markdown showing: the heading's hashes,
        /// or the `- [ ] ` where a box belongs.
        func textViewDidChangeSelection(_ textView: UITextView) {
            storage(of: textView)?.cursor = cursorIfSomebodyIsWriting(in: textView)
        }

        /// Where the cursor is, as live preview means it: where the caret is
        /// while somebody is writing here, and nowhere at all while nobody is.
        func cursorIfSomebodyIsWriting(in textView: UITextView) -> NSRange? {
            textView.isFirstResponder ? textView.selectedRange : nil
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

extension MarkdownEditor.Coordinator: UIGestureRecognizerDelegate {
    /// Over a box and nowhere else. Every other tap in the Entry belongs to
    /// the text view, and is not delayed by this one for longer than deciding
    /// takes.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let textView = gesture.view as? UITextView else { return false }
        return box(in: textView, under: gesture.location(in: textView)) != nil
    }

    /// A single tap in the Entry goes to the box first, and to the text view
    /// only if there was no box under it.
    ///
    /// Said here rather than by calling `require(toFail:)` on the text view's
    /// own recognizers, because there is no moment at which they are all
    /// there to be called on: a text view installs the gestures that move a
    /// caret when it first becomes the one being written in, which is long
    /// after this editor was built. Asked instead, and asked every time, it
    /// covers whichever recognizers exist by then.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        guard gesture === tick, let tap = other as? UITapGestureRecognizer else { return false }
        // Single taps only: a double tap selects a word and a triple selects a
        // line, and neither is a thing a checkbox has an opinion about.
        return tap.numberOfTapsRequired == 1
    }
}
