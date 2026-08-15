import Foundation

/// The syntax characters the editor does not draw, given where the cursor is.
///
/// The difference between reading a day and writing one. `**` around a word is
/// how bold is *spelled*; the word coming out bold is what it *means*, and
/// once the meaning is on screen the two stars are punctuation standing
/// between the user and their own sentence. So they are not drawn — until the
/// cursor comes to the word they belong to, where they stop being noise and
/// become the thing being edited. That is live preview: an Entry that reads
/// like a document everywhere the user is not, and like markdown exactly where
/// they are.
///
/// Nothing is removed. This is a list of stretches to draw as nothing wide,
/// and every one of those characters is still in the text, still selectable,
/// still deletable, and still in the file — which is plain markdown and stays
/// byte for byte what the editor holds (ADR 0001). Hidden is a fact about the
/// pixels, never about the string.
///
/// ## What may hide
///
/// Only a mark whose meaning is still on screen without it. A heading's hashes
/// may go, because the line stays large and bold; emphasis marks may go,
/// because the words stay slanted; a link's address may go, because its words
/// stay coloured.
///
/// A bullet's `- ` may not, nor a quote's `> `: those markers *are* how the
/// line is drawn, and hiding them would leave a paragraph where a list was.
/// Nor may a thematic break, which is nothing but its own characters. Nor an
/// embed's `![…](…)` — drawing the picture is a later stage of the editor, and
/// until there is one, the syntax is the only sign that a picture is there at
/// all.
///
/// ## Where the cursor has to be
///
/// In the element, and touching counts: a caret at either end of `*soft*`
/// reveals it, because that is where somebody typing the closing star stands.
/// Elements answer one at a time and not by line — standing in a heading does
/// not reveal the emphasis further along it — which is what keeps the reveal
/// as small as the thing being edited.
///
/// A selection reveals every element it covers, so that what is about to be
/// deleted is on screen before it goes. Between the two, the cursor is never
/// inside a stretch that is not drawn (`HiddenSyntaxSafetyTests`), which is
/// what makes editing at an element's edge safe: there is no invisible
/// character where the user is aiming.
public struct HiddenSyntax: Equatable, Sendable {
    /// The stretches that are not drawn: in order, never overlapping, never
    /// empty, and never covering anything but syntax.
    public let ranges: [NSRange]

    /// Reads a reading: which of the marks in `markdown` the cursor leaves
    /// hidden.
    ///
    /// Answers for whatever was read — the whole Entry, or the one paragraph
    /// the editor re-read after a keystroke. A cursor outside that stretch is
    /// in none of its elements, which is exactly what a cursor in another
    /// paragraph is.
    public init(_ markdown: EntryMarkdown, cursor: NSRange) {
        var hidden: [NSRange] = []
        for line in markdown.lines {
            let markerHides = line.block.hidesItsMarker && line.marker.length > 0
            if markerHides, !line.range.isTouched(by: cursor) {
                hidden.append(line.marker)
            }
            HiddenSyntax.hide(line.inlines, from: cursor, into: &hidden)
        }
        // Sorted, because a nested span's marks are found after its parent's
        // and are written between them: `***both***` hides `*`, `**`, `**`,
        // `*` and reads back in that order.
        self.ranges = hidden.sorted { $0.location < $1.location }
    }

    private static func hide(
        _ inlines: [MarkdownInline],
        from cursor: NSRange,
        into hidden: inout [NSRange]
    ) {
        for inline in inlines {
            if inline.style.hidesItsDelimiters, !inline.range.isTouched(by: cursor) {
                hidden.append(contentsOf: inline.delimiters)
            }
            // Whatever the span itself does: the cursor can be in a word of a
            // link whose brackets are showing, and outside the emphasis three
            // words further along inside the same bold.
            hide(inline.inlines, from: cursor, into: &hidden)
        }
    }
}

extension MarkdownBlock {
    /// Whether this line's marker may go undrawn — see ``HiddenSyntax``.
    ///
    /// Written out one shape at a time rather than as "a heading, and nothing
    /// else": a block added later should stop the compiler here and be
    /// answered for, not default quietly to being drawn.
    fileprivate var hidesItsMarker: Bool {
        switch self {
        case .heading:
            return true
        case .blank, .paragraph, .bulletItem, .numberedItem, .quote, .thematicBreak:
            return false
        }
    }
}

extension MarkdownInline.Style {
    /// Whether this span's delimiters may go undrawn — see ``HiddenSyntax``.
    fileprivate var hidesItsDelimiters: Bool {
        switch self {
        case .emphasis, .strong, .strikethrough, .code, .link:
            return true
        case .image:
            return false
        }
    }
}

extension NSRange {
    /// Whether a cursor is in this stretch, counting both of its ends: a caret
    /// against either edge of an element is editing that element.
    fileprivate func isTouched(by cursor: NSRange) -> Bool {
        cursor.location <= upperBound && cursor.upperBound >= location
    }
}
