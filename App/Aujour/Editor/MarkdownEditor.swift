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

    /// The way a photograph gets into the day: the picker, and the file
    /// written into the Journal Root beside the Entry. Aimed at the day on
    /// screen by the same hand as the pictures above, and for the same reason.
    ///
    /// `nil` leaves the row's photograph control on the row and not offered,
    /// which is what a text view with no Entry behind it — a preview, a test
    /// of the formatting controls — has to show.
    let photographs: InsertedPhotographs?

    /// Asks an unanswered placeholder's question, because a finger landed on
    /// its widget. What that looks like is a sheet, and a sheet is put up
    /// where there is a view hierarchy to put it in — which is the screen the
    /// day is on, not the text view the token is in.
    let asks: (PlaceholderQuestion) -> Void

    /// What a UI test finds this by, and what VoiceOver calls it. Set on the
    /// text view itself rather than through SwiftUI's accessibility
    /// modifiers, which would describe the wrapper instead of the thing being
    /// typed in.
    let identifier: String
    let label: String

    /// The typeface the day is written in and the colour the app is drawn in,
    /// both of them this device's own choice (ADR 0003). Out of the
    /// environment rather than handed down: between the settings that hold
    /// them and this text view are the day on screen, the calendar that pushed
    /// it and the search results that pushed it, none of which have anything
    /// to say about typefaces.
    @Environment(\.editorLook) private var look

    /// The room around the text.
    private static let textInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    /// What the text container leaves either side of every line, on top of
    /// that.
    private static let lineFragmentPadding: CGFloat = 5

    /// Where an Entry's first character lands, measured from this view's own
    /// top-left.
    ///
    /// Published because a view drawn *over* the editor — the prompt on a day
    /// nobody has written yet — has to start in the same place, and the two
    /// numbers it is made of are this file's. Left to be copied, changing the
    /// inset here would quietly leave that prompt crooked.
    static let whereTheFirstCharacterGoes = CGPoint(
        x: textInset.left + lineFragmentPadding,
        y: textInset.top
    )

    func makeUIView(context: Context) -> UITextView {
        let styling = look.styling(compatibleWith: nil)
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
        textView.textContainerInset = Self.textInset
        // Set rather than left at the default, so that the number a view drawn
        // over the text lines itself up by is one this file decides.
        container.lineFragmentPadding = Self.lineFragmentPadding
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.typingAttributes = styling.baseAttributes
        textView.tintColor = styling.box

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

        context.coordinator.asks = asks
        context.coordinator.answersTaps(in: textView)
        context.coordinator.formats(in: textView, addingPhotographs: photographs)
        storage.setSource(text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // The coordinator outlives this struct, which is rebuilt on every
        // keystroke; the binding it writes back through has to be this one,
        // and so does the way to the sheet.
        context.coordinator.text = $text
        context.coordinator.asks = asks
        textView.accessibilityLabel = label

        guard let storage = textView.textStorage as? MarkdownTextStorage else { return }
        storage.pictures = pictures
        context.coordinator.insertsPhotographs(from: photographs, into: textView)

        // The three things that move how an Entry is drawn without a word of
        // it changing: Dynamic Type, the editor font, and the accent. All of
        // them arrive here as a styling that is not the one in force, and all
        // of them mean drawing the day again.
        //
        // Compared by the font and the colour rather than by the whole
        // styling, because this runs on every keystroke: the rest of a styling
        // is system colours that never move, and comparing a dynamic colour
        // built afresh each time would restyle a long day for a colour that
        // only looks new.
        let wanted = look.styling(compatibleWith: textView.traitCollection)
        if storage.styling.body != wanted.body || storage.styling.box != wanted.box {
            storage.styling = wanted
            textView.typingAttributes = wanted.baseAttributes
            // The caret and the selection too, which are the text view's own
            // and not the storage's — an accent everything else in the app
            // answered to, with a blue cursor left blinking in the middle of
            // it, is the one place the choice would look unfinished.
            textView.tintColor = wanted.box
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

        /// Puts an unanswered placeholder's question in front of the user.
        /// Nothing at all until the editor is on screen, and rebuilt with the
        /// view it writes back through.
        var asks: ((PlaceholderQuestion) -> Void)?

        /// Kept for as long as the text view is, because the layout manager
        /// holds its delegate weakly.
        let glyphs = MarkdownGlyphs()

        /// The gesture that answers a tap on a drawing, kept so that the
        /// delegate below can tell it apart from every gesture a text view has
        /// of its own.
        fileprivate var drawingTap: UITapGestureRecognizer?

        /// The way to a photograph, if this editor is over an Entry that could
        /// hold one. Kept rather than captured, because the row is built once
        /// and this struct is rebuilt on every keystroke.
        var photographs: InsertedPhotographs?

        init(text: Binding<String>) {
            self.text = text
        }

        // MARK: - Tapping a box or a widget

        /// Makes the boxes and the widgets tappable.
        ///
        /// A gesture of its own rather than the text view's own tap, because
        /// the two want opposite things from the same finger: a tap on a box
        /// should tick it and leave the caret where it was, and a tap on
        /// anything else should put the caret there. So this one is offered
        /// first, answers only over a drawing, and the text view's tap waits
        /// to see whether it did.
        ///
        /// A finger is the only way to *this*, and deliberately so: a box and
        /// a widget are painted glyphs, not views, so VoiceOver and Switch
        /// Control reach the line's `- [ ] ` and its `{{mood}}` as text and
        /// nothing they can activate. For a box what answers for them is the
        /// accessory row's checkbox control, which goes round all three states
        /// of a task. For a placeholder it is the token itself: it is literal
        /// text in an editable text view, so answering one without ever
        /// aiming at a pill is selecting those characters and typing the
        /// answer over them — which is the same edit the widget makes, and
        /// exactly what somebody in Obsidian would do with it.
        func answersTaps(in textView: UITextView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(drawingTapped))
            tap.delegate = self
            drawingTap = tap
            textView.addGestureRecognizer(tap)
        }

        /// Answers the drawing the tap landed on: a box is ticked, a widget
        /// asks its question.
        ///
        /// Ticking changes one character of the Entry, and the file is plain
        /// markdown before and after — a task Aujour ticked and a task
        /// Obsidian ticked are the same file (ADR 0001).
        @objc private func drawingTapped(_ tap: UITapGestureRecognizer) {
            guard let textView = tap.view as? UITextView else { return }
            tapped(in: textView, at: tap.location(in: textView))
        }

        /// Answers the drawing at this point, and says whether there was one.
        ///
        /// Internal so that both halves of a tap — finding the drawing under a
        /// finger, and what it does — can be asked for without a simulator;
        /// the gesture above is then the only part left that needs one.
        @discardableResult
        func tapped(in textView: UITextView, at point: CGPoint) -> Bool {
            switch drawing(in: textView, under: point) {
            case .box(let edit):
                apply(edit, in: textView)
                return true
            case .widget(let token):
                ask(token, in: textView)
                return true
            case nil:
                return false
            }
        }

        /// Puts the placeholder's question up, with the way back into this
        /// Entry attached to it.
        ///
        /// The way back is a closure rather than a range handed over, because
        /// what an answer means is "rewrite the token that is there now": the
        /// storage reads the text again when the answer arrives, and an Entry
        /// that has moved on underneath the sheet is simply left alone.
        private func ask(_ token: InteractivePlaceholder.Token, in textView: UITextView) {
            asks?(
                PlaceholderQuestion(placeholder: token.placeholder) {
                    [weak self, weak textView] answer in
                    guard let self, let textView,
                        let storage = storage(of: textView),
                        let edit = storage.answering(token, with: answer)
                    else { return }
                    apply(edit, in: textView)
                }
            )
        }

        // MARK: - The accessory row

        /// Puts the formatting row above the keyboard.
        ///
        /// The text view's own `inputAccessoryView`, which is the whole of how
        /// it comes and goes with the keyboard — see ``MarkdownAccessoryRow``.
        /// The row is handed two ways of saying what was pressed and nothing
        /// else: what a control writes is Core's, and where it writes it is
        /// this text view's. The photograph control is the one that is not
        /// punctuation, and it is offered exactly when there is an Entry
        /// behind this editor for a photograph to be written beside.
        func formats(in textView: UITextView, addingPhotographs: InsertedPhotographs?) {
            insertsPhotographs(from: addingPhotographs, into: textView)
            textView.inputAccessoryView = MarkdownAccessoryRow(
                insertPhoto: addingPhotographs == nil
                    ? nil
                    : { [weak self, weak textView] in
                        guard let self, let textView else { return }
                        insertAPhotograph(in: textView)
                    }
            ) { [weak self, weak textView] command in
                guard let self, let textView else { return }
                format(command, in: textView)
            }
        }

        /// Points both ways into a photograph at this text view — the control
        /// on the row, which is already here, and the suggestions panel, which
        /// is not.
        ///
        /// The panel is a view beside this one and has no caret to insert at,
        /// so the way into the text is handed to it: it says which photograph,
        /// and where an embed goes stays the text view's. The edit is the one a
        /// tapped control makes, so a suggested picture is one undo step and
        /// the Entry saves it as typing.
        ///
        /// Called again whenever the editor is handed different ones, because
        /// the text view is built once and this struct is rebuilt on every
        /// keystroke.
        func insertsPhotographs(
            from addingPhotographs: InsertedPhotographs?,
            into textView: UITextView
        ) {
            // Once each, and not once per keystroke: this runs from
            // `updateUIView`, which runs on every character typed, and the
            // way in is the same way in until the day on screen changes.
            guard addingPhotographs !== photographs else { return }
            photographs = addingPhotographs
            addingPhotographs?.writesTheEmbed = { [weak self, weak textView] attachment in
                guard let self, let textView else { return }
                // Where the caret is if somebody is writing there, and the end
                // of the day if nobody is: a text view reports a caret at its
                // very start whether or not anyone is in it, and a panel tapped
                // over a day nobody has touched would put the picture above the
                // first line.
                let caret =
                    cursorIfSomebodyIsWriting(in: textView)
                    ?? NSRange(location: (textView.text as NSString).length, length: 0)
                apply(attachment.insertion(into: textView.text, at: caret), in: textView)
            }
        }

        /// Puts the picker up, and what comes back into the folder and then
        /// into the day.
        ///
        /// The caret is read before the picker rather than after it: a picker
        /// is another screen, and it takes the keyboard and the first
        /// responder with it — so "at the caret" has to mean where the cursor
        /// was when the control was pressed. The keyboard is asked back
        /// afterwards, because somebody who has just put a picture in their day
        /// is somebody who was writing in it.
        ///
        /// Internal, and answering with the work it started, so that a test
        /// can press the control and wait for what it did.
        @discardableResult
        func insertAPhotograph(in textView: UITextView) -> Task<Void, Never>? {
            guard let photographs else { return nil }
            let caret = textView.selectedRange

            return Task {
                let added = await photographs.pick(over: textView)
                // Back to writing either way, including the commonest outcome
                // of opening a picker — closing it again. Somebody who has
                // just been to the picker and back was writing before they
                // went, and the row and the keyboard went with it.
                textView.becomeFirstResponder()

                guard let added else { return }
                // Through the same door a tapped control goes through, so the
                // picture is one undo step and the Entry saves it as typing.
                apply(added.insertion(into: textView.text, at: caret), in: textView)
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
            // Where the edit says, or back where it was. Ticking a box and
            // answering a widget are not claims about where the user was
            // writing, and a caret that jumped to either would reveal that
            // line's markdown under the finger that just tapped it — while a
            // formatting control wrote its characters around the very place
            // they are writing, and has to hand the words back.
            put(edit.selection ?? edit.cursorLeftWhere(it: selection), in: textView)
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

        /// What a tap at this point would answer, or `nil` for a tap that
        /// landed on words.
        ///
        /// All this adds to the layout manager's answer is the one thing only
        /// a text view knows: where its text starts, which its inset moved.
        private func drawing(
            in textView: UITextView,
            under point: CGPoint
        ) -> MarkdownTextStorage.TappedDrawing? {
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
            // storage's to say, along with what the tap does — a picture is
            // drawn over an Entry too, and is not a control.
            return storage.tapping(at: drawn.text.location)
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
        return drawing(in: textView, under: gesture.location(in: textView)) != nil
    }

    /// A single tap in the Entry goes to the drawing first, and to the text
    /// view only if there was none under it.
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
        guard gesture === drawingTap, let tap = other as? UITapGestureRecognizer else {
            return false
        }
        // Single taps only: a double tap selects a word and a triple selects a
        // line, and neither is a thing a checkbox has an opinion about.
        return tap.numberOfTapsRequired == 1
    }
}
