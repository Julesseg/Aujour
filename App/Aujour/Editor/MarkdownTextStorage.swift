import AujourCore
import UIKit

/// The text an Entry is being written in, styled as markdown while it is
/// typed.
///
/// A text view's storage is the one place that sees every change to the text —
/// typed, pasted, dictated, undone — which is why the styling lives here
/// rather than in a delegate that only hears about some of them. The string is
/// never touched: this class adds attributes to characters and adds nothing to
/// the text, so what the editor holds is byte for byte what goes in the file
/// (ADR 0001).
///
/// ## Where the cursor is
///
/// Half of what an Entry is drawn from, and told to this class the same way
/// the text is (``selection``). Markdown away from the cursor is drawn as what
/// it means and its marks are left out; the element the cursor is in shows its
/// marks, because they are what is being edited. Which marks those are is
/// ``AujourCore/HiddenSyntax``'s to say, and leaving them out of the drawing
/// is ``HiddenSyntaxGlyphs``'s — here they meet, on one attribute over the
/// paragraph being restyled.
///
/// ## What a keystroke costs
///
/// The lines it landed in — never the whole Entry — which is what keeps typing
/// into a thousand-word day as quick as typing into an empty one. That is
/// sound only because markdown is read one line at a time in Core, where
/// reading a stretch of lines on its own is *proved* to give the same answer
/// as reading them in place (`EntryMarkdownLocalityTests`). Any block that
/// needed more than a line to recognise would break this, which is why none
/// is modelled.
final class MarkdownTextStorage: NSTextStorage {
    /// The attributed string this one is a façade over. `NSTextStorage` is an
    /// abstract class: subclassing it means holding the storage yourself and
    /// answering four questions about it.
    private let backing = NSMutableAttributedString()

    /// How markdown is drawn. Changing it — Dynamic Type, a theme, the editor
    /// font — restyles everything, because every font here is derived from it.
    var styling: MarkdownStyling {
        didSet {
            guard styling != oldValue else { return }
            restyleEverything()
        }
    }

    /// The stretches the last change was paid for in: one for a keystroke, and
    /// up to two for a cursor that moved from one paragraph to another.
    ///
    /// Kept because "only the paragraph that changed is restyled" is the whole
    /// performance claim of this editor, and a claim about work done is not
    /// observable from the text afterwards — the styling is identical either
    /// way. This is what a test can look at.
    private(set) var restyledRanges: [NSRange] = []

    /// Where the cursor is, as the text view has it — a caret, or the words a
    /// selection covers — and `nil` while nobody is writing in this Entry at
    /// all, which is a day being read rather than written and shows no marks
    /// anywhere.
    ///
    /// The second thing an Entry is drawn from, and the reason the editor is
    /// a live preview rather than a styled source view: which syntax is drawn
    /// at all depends on which element the cursor is in
    /// (``AujourCore/HiddenSyntax``).
    ///
    /// Setting it costs the lines it left and the lines it arrived in, read
    /// the way an edit is read. For a caret that is a paragraph at either end,
    /// whatever the day weighs; for a selection over half the day it is half
    /// the day, which is exactly the stretch whose marks it just revealed.
    var cursor: NSRange? {
        get { cursorRange }
        set {
            let moved = newValue.map { clamped($0) }
            guard moved != cursorRange else { return }
            let left = cursorRange
            cursorRange = moved
            restyle(leaving: left, arrivingIn: moved)
        }
    }

    private var cursorRange: NSRange? = NSRange(location: 0, length: 0)

    init(styling: MarkdownStyling = MarkdownStyling()) {
        self.styling = styling
        super.init()
    }

    /// Never happens: a text storage is made when an editor is, and nothing
    /// archives one. Answered rather than crashed on, because a journal that
    /// stopped at a decoder it was never handed to would be a bad trade.
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Being a text storage

    override var string: String { backing.string }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(
            .editedCharacters,
            range: range,
            changeInLength: (str as NSString).length - range.length
        )
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Restyling

    /// Guards against restyling in answer to restyling. Announcing the widened
    /// stretch below is what tells the layout manager to redraw a line that
    /// only just became a heading — and announcing a change is also what got
    /// this method called.
    private var restyling = false

    /// Restyles at the end of the whole editing group, which is the only
    /// moment the text has settled.
    ///
    /// Not beside the change itself, tempting as that is: a text view inserts
    /// text in two steps — the characters, and then the attributes they were
    /// typed in — and styling between the two is styling the second step wipes
    /// straight off whatever was just typed. This is also where a text storage
    /// is meant to fix up its own attributes.
    override func processEditing() {
        // The announcement below re-enters here. Nothing to do in that call
        // and nothing to announce from it either: it is folded into the
        // announcement the call already in progress is on its way to make.
        guard !restyling else { return }

        // Attributes changing is this class's own doing, and restyling in
        // answer to that would never stop. Asked once and remembered, because
        // announcing the edit below is what clears it.
        let textChanged = editedMask.contains(.editedCharacters)
        if textChanged {
            restyling = true
            restyledRanges = [restyle(around: editedRange)]
            restyling = false
        }
        super.processEditing()
        // After the announcement, because until it has been made the layout
        // still has the text at its old length, and these are offsets into the
        // new one.
        if textChanged {
            redrawGlyphs(over: restyledRanges)
        }
    }

    /// Replaces the whole text — opening a day, and taking the file's version
    /// when it has moved on underneath the editor.
    func setSource(_ source: String) {
        guard backing.string != source else { return }
        replaceCharacters(in: NSRange(location: 0, length: backing.length), with: source)
        // A version arriving from iCloud can be shorter than the one it
        // replaced, and a cursor past the end of the text is in no element at
        // all. Put through the setter rather than clamped in place, so that on
        // the days it does have to move, the paragraph it lands in is drawn
        // for a cursor that is really in it. On every other day it is already
        // where it was, and this does nothing.
        cursor = cursorRange
    }

    private func restyleEverything() {
        guard backing.length > 0 else { return }
        beginEditing()
        restyledRanges = [restyle(around: NSRange(location: 0, length: backing.length))]
        endEditing()
        redrawGlyphs(over: restyledRanges)
    }

    /// Draws the elements the cursor left and the ones it arrived in.
    ///
    /// Two readings at the most, and while somebody is typing it is one: the
    /// caret moves within the line it is writing, so both readings are of that
    /// line and the second is dropped. Reading it twice is a few dozen
    /// characters read twice, which is cheaper than the arithmetic that would
    /// work out it was the same line.
    private func restyle(leaving left: NSRange?, arrivingIn arrived: NSRange?) {
        guard backing.length > 0 else { return }
        beginEditing()
        var stretches: [NSRange] = []
        for place in [left, arrived] {
            guard let place else { continue }
            let stretch = restyle(around: place)
            if !stretches.contains(stretch) { stretches.append(stretch) }
        }
        restyledRanges = stretches
        endEditing()
        redrawGlyphs(over: stretches)
    }

    /// Reads the lines an edit touched, and draws what they say.
    ///
    /// Which lines those are is Core's to decide — the same rule that decides
    /// where a line ends decides how far back and forward to read, so the two
    /// cannot drift apart. Everything comes back in the storage's own
    /// coordinates, so there is no arithmetic here to get wrong either.
    ///
    /// The announcement at the end widens the edit to the whole stretch, which
    /// is more than the characters that changed — the `#` typed at the front
    /// of a line is what restyles the rest of it.
    ///
    /// Where the cursor is comes into it as much as what the text says: the
    /// same paragraph is drawn with its marks and without them depending on
    /// whether the cursor is in it. Every attribute is set again from scratch,
    /// so a mark that was hidden and is not any more simply comes back — there
    /// is nothing to undo.
    ///
    /// Restyling *during* an edit uses the cursor from before it, which is a
    /// keystroke behind: the text view moves the caret after the storage has
    /// changed. It settles itself — that move arrives as a cursor change and
    /// draws the same paragraph again — and it can only ever be wrong about
    /// the line being typed in, which is revealed either way.
    private func restyle(around edit: NSRange) -> NSRange {
        let reading = EntryMarkdown(backing.string, around: edit)
        guard reading.range.length > 0 else { return reading.range }

        backing.setAttributes(styling.baseAttributes, range: reading.range)
        let hidden = HiddenSyntax(reading, cursor: cursorRange.map { clamped($0) })
        styling.apply(reading, hiding: hidden, to: backing)
        edited(.editedAttributes, range: reading.range, changeInLength: 0)
        return reading.range
    }

    /// Has the layout make its glyphs again over stretches whose styling has
    /// just changed.
    ///
    /// Attributes changing does not ask for this on its own: a layout manager
    /// answers that by laying the same glyphs out again, and whether a
    /// character has a glyph at all is decided when glyphs are *made*
    /// (``HiddenSyntaxGlyphs``). Without this, a mark that just hid would go
    /// on taking up the room it took before, and one that just came back would
    /// have nowhere to appear.
    private func redrawGlyphs(over stretches: [NSRange]) {
        for stretch in stretches where stretch.length > 0 {
            for manager in layoutManagers {
                manager.invalidateGlyphs(
                    forCharacterRange: stretch,
                    changeInLength: 0,
                    actualCharacterRange: nil
                )
                manager.invalidateLayout(forCharacterRange: stretch, actualCharacterRange: nil)
            }
        }
    }

    /// A range brought inside the text — the cursor the text view had before a
    /// version arriving from iCloud made the day shorter.
    private func clamped(_ range: NSRange) -> NSRange {
        let location = min(max(range.location, 0), backing.length)
        let length = min(max(range.length, 0), backing.length - location)
        return NSRange(location: location, length: length)
    }
}
