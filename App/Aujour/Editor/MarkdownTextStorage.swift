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
        // answer to that would never stop.
        if editedMask.contains(.editedCharacters) {
            restyling = true
            restyle(around: editedRange)
            restyling = false
        }
        super.processEditing()
    }

    /// Replaces the whole text — opening a day, and taking the file's version
    /// when it has moved on underneath the editor.
    func setSource(_ source: String) {
        guard backing.string != source else { return }
        replaceCharacters(in: NSRange(location: 0, length: backing.length), with: source)
    }

    private func restyleEverything() {
        guard backing.length > 0 else { return }
        beginEditing()
        restyle(around: NSRange(location: 0, length: backing.length))
        endEditing()
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
    private func restyle(around edit: NSRange) {
        let reading = EntryMarkdown(backing.string, around: edit)
        restyledRange = reading.range
        guard reading.range.length > 0 else { return }

        backing.setAttributes(styling.baseAttributes, range: reading.range)
        styling.apply(reading, to: backing)
        edited(.editedAttributes, range: reading.range, changeInLength: 0)
    }
}
