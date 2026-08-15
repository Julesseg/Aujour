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
/// ## What a keystroke costs
///
/// One paragraph. After a change, only the paragraph it landed in is read and
/// re-styled — never the whole Entry — which is what keeps typing into a
/// thousand-word day as quick as typing into an empty one. That is sound only
/// because markdown is read one line at a time in Core, where reading a
/// stretch of lines on its own is *proved* to give the same answer as reading
/// them in place (`EntryMarkdownLocalityTests`). Any block that needed more
/// than a line to recognise would break this, which is why none is modelled.
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

    /// The stretch the last change was paid for in.
    ///
    /// Kept because "only the paragraph that changed is restyled" is the whole
    /// performance claim of this editor, and a claim about work done is not
    /// observable from the text afterwards — the styling is identical either
    /// way. This is what a test can look at.
    private(set) var restyledRange = NSRange(location: 0, length: 0)

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

    /// Guards against restyling in answer to restyling.
    ///
    /// Announcing the attribute change below is what tells the layout manager
    /// to redraw a paragraph that grew a heading — and announcing a change is
    /// also what got this method called. The flag, rather than a rule about
    /// which edits are whose, because re-entering here is the one failure that
    /// would not be a wrong style but a hung app.
    private var restyling = false

    override func processEditing() {
        // Announcing the widened range below re-enters here. There is nothing
        // to do in that call and nothing to announce from it either: the
        // announcement is folded into the one the call already in progress is
        // on its way to make.
        guard !restyling else { return }

        // Before `super`, which is where the layout manager is told: the
        // paragraph is styled by the time anything lays it out, so a heading
        // is never drawn twice, once at each size.
        if editedMask.contains(.editedCharacters) {
            restyling = true
            let stretch = stretchToRestyle(after: editedRange)
            restyle(stretch)
            // Widened to whole paragraphs, which is more than the characters
            // that changed — the `#` typed at the front of a line is what
            // restyles the rest of it.
            edited(.editedAttributes, range: stretch, changeInLength: 0)
            restyling = false
        }
        super.processEditing()
    }

    /// The whole lines an edit can have changed the meaning of.
    ///
    /// The paragraph it landed in, and — when it ended on a line break — the
    /// one after. A return typed into the middle of a heading leaves half a
    /// heading above the break and something that is not a heading at all
    /// below it, and the half below is in a paragraph the edit never touched.
    private func stretchToRestyle(after edit: NSRange) -> NSRange {
        let text = backing.string as NSString
        let paragraph = text.paragraphRange(for: edit)
        guard edit.upperBound == paragraph.upperBound, paragraph.upperBound < text.length else {
            return paragraph
        }
        return NSUnionRange(
            paragraph,
            text.paragraphRange(for: NSRange(location: paragraph.upperBound, length: 0))
        )
    }

    /// Replaces the whole text — opening a day, and taking the file's version
    /// when it has moved on underneath the editor.
    func setSource(_ source: String) {
        guard backing.string != source else { return }
        replaceCharacters(in: NSRange(location: 0, length: backing.length), with: source)
    }

    private func restyleEverything() {
        let whole = NSRange(location: 0, length: backing.length)
        guard whole.length > 0 else {
            restyledRange = whole
            return
        }
        beginEditing()
        restyle(whole)
        edited(.editedAttributes, range: whole, changeInLength: 0)
        endEditing()
    }

    /// Reads a stretch of whole lines and draws what it says.
    ///
    /// The stretch is read on its own, so the cost is the stretch's rather
    /// than the Entry's, and shifted back into the Entry's coordinates before
    /// anything is drawn.
    private func restyle(_ stretch: NSRange) {
        restyledRange = stretch
        guard stretch.length > 0 else { return }

        let source = (backing.string as NSString).substring(with: stretch)
        backing.setAttributes(styling.baseAttributes, range: stretch)
        styling.apply(EntryMarkdown(source).shifted(by: stretch.location), to: backing)
    }
}
