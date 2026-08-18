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
/// from ``EntryMarkdown`` in Core, what that looks like from
/// ``MarkdownStyling`` beside it, and what a formatting control writes from
/// ``MarkdownFormatting``. All this adds is the two things only a text view
/// knows: what was typed, and where the cursor is — the second because the
/// marks around the cursor are shown and the rest are not, which is what makes
/// the Entry read like a document while staying markdown under the hand
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
        context.coordinator.formats(in: textView)
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
        ///
        /// A finger is the only way to *this*, and deliberately so: a box is
        /// painted glyphs, not a view, so VoiceOver and Switch Control reach
        /// the line's `- [ ] ` as text and nothing they can activate. What
        /// answers for them is the accessory row's checkbox control, which
        /// goes round all three states of a task — made, ticked, and neither —
        /// so a box can be ticked by somebody who never aims at one.
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
            apply(edit, in: textView)
            return true
        }

        // MARK: - The accessory row

        /// Puts the formatting row above the keyboard.
        ///
        /// The text view's own `inputAccessoryView`, which is the whole of how
        /// it comes and goes with the keyboard — see ``MarkdownAccessoryRow``.
        /// The row is handed a way to say which control was pressed and
        /// nothing else: what a control writes is Core's, and where it writes
        /// it is this text view's. Nothing is handed it for the photo control,
        /// which is why that one is on the row and not yet offered — inserting
        /// a photograph is the attachment pipeline's (issue #22).
        func formats(in textView: UITextView) {
            textView.inputAccessoryView = MarkdownAccessoryRow {
                [weak self, weak textView] command in
                guard let self, let textView else { return }
                format(command, in: textView)
            }
        }

        /// Rewrites what the cursor is on the way this control means, and says
        /// whether there was anything to rewrite.
        ///
        /// All this adds to Core's answer is the two things only a text view
        /// knows: what the text says, and where the cursor is in it. Internal
        /// so that a test can press a control without a keyboard.
        @discardableResult
        func format(_ command: MarkdownFormatting, in textView: UITextView) -> Bool {
            guard let edit = command.edit(textView.text, over: textView.selectedRange) else {
                return false
            }
            apply(edit, in: textView)
            return true
        }

        // MARK: - Changing the text under the cursor

        /// Makes an edit the user asked for by tapping something, and tells the
        /// Entry.
        ///
        /// Undoable, because a tick and a bold word are edits like any other,
        /// and the day they are in is full of typing: shaking to undo after
        /// ticking the wrong line should take back the tick, not the sentence
        /// typed before it. Registered against the same undo manager the
        /// typing uses, so the two share one stack in the order they happened.
        private func apply(_ edit: MarkdownEdit, in textView: UITextView) {
            let onScreen = textView.text as NSString
            // An edit is about the text it was worked out from, and an undo
            // registered against a day the file has since replaced is about
            // characters that are not there any more. Left undone rather than
            // reaching past the end of the Entry, which is an exception in
            // front of somebody who is writing.
            guard edit.range.upperBound <= onScreen.length else { return }

            let selection = textView.selectedRange
            let before = onScreen.substring(with: edit.range)

            // A control can ask for nothing but a different cursor — bold at
            // the end of a bold word steps out over its closing marks — and an
            // edit that writes the same characters back is not an edit to save
            // or to undo.
            guard before != edit.replacement else {
                put(edit.selection ?? selection, in: textView)
                return
            }

            textView.textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            // Where the edit says, or back where it was. Ticking something off
            // is not a claim about where the user was writing, and a caret
            // that jumped to the box would reveal that line's markdown under
            // the finger that just tapped it — while a formatting control
            // wrote its characters around the very place they are writing, and
            // has to hand the words back.
            put(edit.selection ?? selection, in: textView)
            // The text view announces what it was told to change, not what
            // this told its storage — so the Entry is told here, and hears
            // about a tick exactly as it hears about a keystroke.
            text.wrappedValue = textView.text

            // The way back: the characters that are there now, and the words
            // that were there before them. Its range is where the replacement
            // ended up rather than where it went in, which are two different
            // stretches whenever a control wrote more than it took away.
            let inverse = MarkdownEdit(
                range: NSRange(
                    location: edit.range.location, length: (edit.replacement as NSString).length
                ),
                replacement: before,
                selection: selection
            )
            textView.undoManager?.registerUndo(withTarget: self) { [weak textView] coordinator in
                guard let textView else { return }
                coordinator.apply(inverse, in: textView)
            }
        }

        /// Leaves the cursor where an edit said to, and tells the storage —
        /// which hears about the caret the user moves and not the one moved
        /// for them, and has to draw the element it is now in.
        ///
        /// Brought inside the text on the way, for the same reason the edit
        /// above is: a range past the end of an Entry is an exception rather
        /// than a misplaced caret.
        private func put(_ cursor: NSRange, in textView: UITextView) {
            let length = (textView.text as NSString).length
            let location = min(max(cursor.location, 0), length)
            textView.selectedRange = NSRange(
                location: location,
                length: min(max(cursor.length, 0), length - location)
            )
            storage(of: textView)?.cursor = cursorIfSomebodyIsWriting(in: textView)
        }

        /// The edit a tap at this point would make, or `nil` for a tap that
        /// landed on words.
        ///
        /// All this adds to the layout manager's answer is the one thing only
        /// a text view knows: where its text starts, which its inset moved.
        private func box(in textView: UITextView, under point: CGPoint) -> MarkdownEdit? {
            guard let storage = textView.textStorage as? MarkdownTextStorage,
                let layout = textView.layoutManager as? MarkdownLayoutManager
            else { return nil }

            let inText = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            guard let drawn = layout.drawnMarkdown(under: inText, in: textView.textContainer)
            else { return nil }
            // Whether that drawing is one a tap means anything to is the
            // storage's to say, along with what the tap changes — a picture is
            // drawn over an Entry too, and is not a control.
            return storage.tickingTheBox(at: drawn.text.location)
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// Opens the next item when a return lands in a list, in place of the
        /// plain line break the text view would have written.
        ///
        /// The one keystroke this editor answers itself. Which characters that
        /// is — the marker again, its number moved on, its box empty — is
        /// ``AujourCore/MarkdownReturn``'s, decided from the text alone and
        /// unit-tested there; and it goes in through the same door a tapped
        /// control does, so it is one undo step and the Entry hears about it
        /// as it hears about typing.
        ///
        /// Every other keystroke is the text view's own, including a return
        /// anywhere but in a list.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n",
                let edit = MarkdownReturn.edit(textView.text, over: range)
            else { return true }

            apply(edit, in: textView)
            return false
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
