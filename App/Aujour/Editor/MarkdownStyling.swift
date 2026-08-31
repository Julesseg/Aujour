import AujourCore
import UIKit

/// The two colours a chip takes: the wash it sits on, and the words on it.
///
/// Two and not one, and that is the identity's own rule rather than an
/// elaboration of it. A colour written on a wash of itself loses about a point
/// of contrast, and every one of the nine accents lands between 3.6:1 and
/// 4.4:1 that way — under the sentence floor, in the exact place the identity
/// likes tinted pills most. So the accent carries a second shade for it:
/// ``AujourCore/Accent/uiColor`` for the shape and
/// ``AujourCore/Accent/inkColor`` for the words on it (ADR 0006), and
/// `IdentityTests` is what holds the pair to the floor.
///
/// Travelling as one value rather than as two properties, because a chip is
/// drawn in both or in neither — a wash that arrived without its ink would be
/// a chip lettered in whatever the last caller happened to pass.
struct ChipColours: Equatable {
    /// The fill under the chip.
    let wash: UIColor

    /// The lettering and the symbol on it.
    let ink: UIColor

    /// What a chip is before anybody has chosen an accent: the system's own
    /// tint, washed the way the identity washes one.
    ///
    /// For a preview and for a test of something else. The app itself always
    /// passes the accent this device chose, so nothing a user sees is drawn in
    /// this.
    ///
    /// Dynamic, like every colour in the app: resolved against the screen it
    /// lands on rather than against whichever appearance happened to be in
    /// force when the default was read.
    static let theSystemsOwn = ChipColours(
        wash: UIColor { _ in .tintColor.withAlphaComponent(0.15) },
        ink: .tintColor
    )
}

/// How an Entry's markdown is drawn: the fonts, the colours, and the indents
/// that turn ``EntryMarkdown``'s shapes into something to read.
///
/// The split is the same one the whole app is built on. *What* a stretch of
/// text is — a second-level heading, the two stars that made a word loud —
/// is Core's, unit-tested on Linux against the text it came from. What that
/// looks like is here, where it needs a font to be anything at all.
///
/// Nothing here hides a *character*. Marks the cursor is away from are left
/// out of the drawing — that is what live preview is, and which ones those
/// are is ``AujourCore/HiddenSyntax``'s to say — but they are left out by
/// marking them for glyph generation to skip (``MarkdownGlyphs``), never
/// by taking them out of the text. The file is plain markdown (ADR 0001) and
/// the editor is a view of it, not a second document that has to be turned
/// back into one.
struct MarkdownStyling: Equatable {
    /// The typeface everything else is derived from — headings by scaling it,
    /// emphasis by adding a trait, code by exchanging it for a monospaced one
    /// of the same size. So the editor font is one decision, made once, and
    /// Dynamic Type reaches every shape by reaching this.
    var body: UIFont

    /// The words themselves.
    var words: UIColor

    /// The characters that are syntax rather than words. Quiet enough to read
    /// past, dark enough to see and aim a cursor at — a `#` nobody can find
    /// is a `#` nobody can delete.
    ///
    /// The identity's faintest step, which is the marker floor rather than the
    /// sentence one (ADR 0006, and ``Palette/inkFaint``). A mark is not a
    /// sentence: it is punctuation held in reserve for the moment the cursor
    /// arrives, and drawing it as dark as the words either side of it would
    /// undo the reason it is hidden at all.
    ///
    /// The one colour here the identity has reached so far. The words a mark
    /// sits among are still the system's `.label`, because the paper they are
    /// drawn on is still the system's too — ink moved onto the identity over a
    /// ground that has not is the half-measure, not the other way round.
    var syntax: UIColor

    /// Quoted words, which are somebody else's.
    var quoted: UIColor

    /// The words of a link or an embed — the only thing here that is not
    /// simply text, and the only place the editor spends a colour.
    var link: UIColor

    /// A task's box. The app's own colour, because a checkbox is a control
    /// rather than a mark: it is the one thing in an Entry that answers a tap,
    /// and it should look like it.
    var box: UIColor

    /// An unanswered placeholder's chip — the other thing in an Entry that
    /// answers a tap, and the one drawn as a fill rather than as an outline.
    var chip: ChipColours

    /// The gap between lines, which the plain editor had too.
    var lineSpacing: CGFloat

    init(
        body: UIFont = .preferredFont(forTextStyle: .body),
        words: UIColor = .label,
        syntax: UIColor = Palette.inkFaint,
        quoted: UIColor = .secondaryLabel,
        link: UIColor = .tintColor,
        box: UIColor = .tintColor,
        chip: ChipColours = .theSystemsOwn,
        lineSpacing: CGFloat = 2
    ) {
        self.body = body
        self.words = words
        self.syntax = syntax
        self.quoted = quoted
        self.link = link
        self.box = box
        self.chip = chip
        self.lineSpacing = lineSpacing
    }

    /// The same styling for a day nobody has written yet: the words quieter,
    /// and nothing else touched.
    ///
    /// A day with no file is spawned from the Content Template exactly as
    /// today is, so it arrives headings and all and looks like a day somebody
    /// wrote. This is the difference, said in the one place a page of prose
    /// can say anything about itself — the ink it is in. It goes at the first
    /// keystroke, which is when the words become the reader's own.
    ///
    /// The faint step, which the identity keeps for markers and for **a
    /// field's placeholder** (``Palette/inkFaint``) — and that is what these
    /// words are. A Content Template spawned for a day is not somebody's
    /// prose; it is what stands in the Entry until they write it, and it is
    /// gone the moment they do.
    ///
    /// Worth being plain about, because it sits against ADR 0006: the faint
    /// ink is held to the marker floor and not the sentence one, so a page in
    /// it is quieter than the app's rule for sentences allows. What makes that
    /// the right side of the line here is that nothing in it is the reader's
    /// own — their first keystroke takes the whole page to the full ink, and
    /// no word anybody wrote is ever drawn below the sentence floor. Raise
    /// this to ``Palette/inkMuted`` and the difference is barely a difference,
    /// which is the fault this replaced.
    ///
    /// Which does mean the marks and the words are one step on an unwritten
    /// day, where a written one draws marks quieter than the words around
    /// them. There is nothing under the faint step to move them to, and the
    /// distinction is back at the first keystroke — along with the reason to
    /// care about it, which is that the words are worth telling apart from the
    /// punctuation once they are yours.
    ///
    /// Only the words. A link is still a link and a task's box is still a
    /// control, both drawn in the accent this device chose and both held to a
    /// floor of their own.
    var forADayNobodyHasWritten: MarkdownStyling {
        var quieter = self
        quieter.words = Palette.inkFaint
        return quieter
    }

    /// What every character is before anything markdown has to say about it,
    /// and what the editor types in.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: body,
            .foregroundColor: words,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    // MARK: - Drawing a reading

    /// Draws a reading of some markdown onto the text it was read from.
    ///
    /// The ranges are already in `text`'s own coordinates, whether the whole
    /// Entry was read or only the lines around a keystroke — so there is no
    /// arithmetic here, and none to get wrong.
    ///
    /// Additive by design: a line is drawn, then the spans inside it are drawn
    /// over it, then the spans inside *those*. Emphasis inside a bold heading
    /// therefore comes out bold, italic and heading-sized without anywhere
    /// having to name that combination.
    ///
    /// Hiding comes last, and is one attribute: the marks the cursor is away
    /// from are still coloured and still fonted like the syntax they are —
    /// they are simply not drawn while they are marked, and are drawn again
    /// the moment a later reading leaves the mark off. Nothing here needs to
    /// know how that is done, or to undo it.
    ///
    /// Then the boxes and the pictures, which are the same idea one step
    /// further on: their characters are not drawn *and* something is drawn
    /// instead. The stretch is hidden like any other and one character of it
    /// carries the drawing, so that a restyle takes both away together and
    /// there is never a box left standing over words that have moved on.
    func apply(
        _ markdown: EntryMarkdown,
        hiding hidden: HiddenSyntax,
        drawing drawn: [DrawnMarkdown],
        to text: NSMutableAttributedString
    ) {
        for line in markdown.lines {
            apply(line, to: text)
        }
        for mark in hidden.ranges {
            text.addAttribute(.hiddenSyntax, value: true, range: mark)
        }
        for drawing in drawn {
            apply(drawing, to: text)
        }
    }

    /// Stands one drawing in front of the characters it is for: all of them
    /// undrawn, and the first of them carrying the thing to draw.
    ///
    /// The first character rather than a new one, because there is no new one
    /// to have — the text is the file (ADR 0001) and this adds nothing to it.
    /// So the box or the picture is laid out where that character would have
    /// been, and the caret can still be put either side of it.
    private func apply(_ drawing: DrawnMarkdown, to text: NSMutableAttributedString) {
        guard drawing.text.length > 0, drawing.text.upperBound <= text.length else { return }
        text.addAttribute(.hiddenSyntax, value: true, range: drawing.text)
        text.addAttribute(
            .drawnMarkdown,
            value: drawing,
            range: NSRange(location: drawing.text.location, length: 1)
        )
    }

    private func apply(_ line: MarkdownLine, to text: NSMutableAttributedString) {
        // The last line of an Entry with nothing after it: no characters, so
        // nothing to draw them as.
        guard line.paragraph.length > 0 else { return }

        // Over the paragraph rather than the line, so that the break carries
        // the line's own font and spacing: the caret sits after the last word
        // of a heading too, and it should be a heading's height there.
        text.setAttributes(attributes(for: line, in: text), range: line.paragraph)
        if line.marker.length > 0 {
            text.addAttribute(.foregroundColor, value: syntax, range: line.marker)
        }
        for inline in line.inlines {
            apply(inline, to: text)
        }
    }

    private func apply(_ inline: MarkdownInline, to text: NSMutableAttributedString) {
        switch inline.style {
        case .emphasis:
            add(.traitItalic, over: inline.content, in: text)
        case .strong:
            add(.traitBold, over: inline.content, in: text)
        case .strikethrough:
            text.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: inline.content
            )
        case .code:
            // Backticks included: a monospaced span with proportional
            // delimiters either side reads as a mistake.
            monospace(inline.range, in: text)
        case .link, .image:
            text.addAttribute(.foregroundColor, value: link, range: inline.content)
        }

        // Last, so that whatever the span did to its own text does not also
        // happen to the punctuation that marks it.
        for delimiter in inline.delimiters {
            text.addAttribute(.foregroundColor, value: syntax, range: delimiter)
        }
        for nested in inline.inlines {
            apply(nested, to: text)
        }
    }

    // MARK: - What a line looks like

    private func attributes(
        for line: MarkdownLine,
        in text: NSMutableAttributedString
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        switch line.block {
        case .heading(let level):
            attributes[.font] = heading(level: level)
            attributes[.paragraphStyle] = paragraphStyle(spacedLikeAHeading: true)
        case .bulletItem, .taskItem, .numberedItem:
            attributes[.paragraphStyle] = paragraphStyle(hangingUnder: line, in: text)
        case .quote:
            attributes[.foregroundColor] = quoted
            attributes[.paragraphStyle] = paragraphStyle(hangingUnder: line, in: text)
        case .thematicBreak:
            attributes[.foregroundColor] = syntax
        case .paragraph, .blank:
            break
        }
        return attributes
    }

    /// A heading's font: the body face, bolder, and larger the higher the
    /// level. Derived rather than listed so that it follows the editor font
    /// and Dynamic Type wherever they go.
    private func heading(level: Int) -> UIFont {
        let scales: [CGFloat] = [1.55, 1.35, 1.2, 1.12, 1.06, 1.0]
        // Core only ever says 1 to 6. Clamped anyway, because the cost of
        // being wrong here is the editor stopping rather than a wrong size.
        let scale = scales[min(max(level, 1), scales.count) - 1]
        let bolder =
            body.fontDescriptor.withSymbolicTraits(
                body.fontDescriptor.symbolicTraits.union(.traitBold)
            ) ?? body.fontDescriptor
        return UIFont(descriptor: bolder, size: body.pointSize * scale)
    }

    private func paragraphStyle(spacedLikeAHeading: Bool = false) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        if spacedLikeAHeading {
            style.paragraphSpacingBefore = body.pointSize * 0.7
            style.paragraphSpacing = body.pointSize * 0.15
        }
        return style
    }

    /// A list item's or a quote's paragraph style: a wrapped line lands under
    /// the words rather than under the marker, which is the difference between
    /// a list that looks like a list and one that looks like a paragraph with
    /// dashes in it.
    private func paragraphStyle(
        hangingUnder line: MarkdownLine,
        in text: NSMutableAttributedString
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing

        let prefix = NSRange(
            location: line.indent.location,
            length: line.marker.upperBound - line.indent.location
        )
        style.firstLineHeadIndent = width(of: line.indent, in: text)
        style.headIndent = width(of: prefix, in: text)
        return style
    }

    /// How wide a stretch of the text is in the body font — measured rather
    /// than counted, because `1. ` and `- ` are not the same number of points
    /// wide however many characters they are.
    private func width(of range: NSRange, in text: NSMutableAttributedString) -> CGFloat {
        guard range.length > 0 else { return 0 }
        let prefix = (text.string as NSString).substring(with: range)
        return (prefix as NSString).size(withAttributes: [.font: body]).width
    }

    // MARK: - Changing the font under a stretch of text

    /// Adds a trait to whatever font each part of a range is already in, so
    /// that emphasis inside strong inside a heading is all three.
    private func add(
        _ traits: UIFontDescriptor.SymbolicTraits,
        over range: NSRange,
        in text: NSMutableAttributedString
    ) {
        refont(range, in: text) { $0.adding(traits) }
    }

    private func monospace(_ range: NSRange, in text: NSMutableAttributedString) {
        refont(range, in: text) { font in
            // A touch smaller: a monospaced face at the same point size reads
            // heavier than the words either side of it.
            .monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular)
        }
    }

    /// Re-fonts a range a part at a time.
    ///
    /// Gathered before anything is written, because changing an attribute
    /// while enumerating that same attribute is a walk over a collection being
    /// mutated underneath it.
    private func refont(
        _ range: NSRange,
        in text: NSMutableAttributedString,
        to newFont: (UIFont) -> UIFont
    ) {
        guard range.length > 0 else { return }
        var changes: [(font: UIFont, range: NSRange)] = []
        text.enumerateAttribute(.font, in: range) { value, part, _ in
            guard let font = value as? UIFont else { return }
            changes.append((newFont(font), part))
        }
        for refonted in changes {
            text.addAttribute(.font, value: refonted.font, range: refonted.range)
        }
    }
}

extension UIFont {
    /// The same font, also italic, or bold, or both.
    fileprivate func adding(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard
            let descriptor = fontDescriptor.withSymbolicTraits(
                fontDescriptor.symbolicTraits.union(traits)
            )
        else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
