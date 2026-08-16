import UIKit

/// Paints the boxes and the pictures, into the room ``MarkdownGlyphs`` left
/// for them.
///
/// The last step of standing something in front of an Entry's own characters,
/// and the only one that needs a graphics context. Everything before it is a
/// decision — Core says which stretches are stood in for, the styling says
/// what with, glyph generation says how much room — and all of those are
/// tested without a screen. This draws.
///
/// A layout manager rather than the text view's `draw(_:)`, because the room
/// is a glyph's and only the layout manager knows where a glyph ended up: a
/// picture on a line that wrapped, in an entry scrolled half off the top, is
/// somewhere no view-level arithmetic would find it.
final class MarkdownLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }

        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.drawnMarkdown, in: characters) { value, range, _ in
            guard let drawn = value as? DrawnMarkdown else { return }
            draw(drawn, over: range, at: origin, in: storage)
        }
    }

    private func draw(
        _ drawn: DrawnMarkdown,
        over characters: NSRange,
        at origin: CGPoint,
        in storage: NSTextStorage
    ) {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        // The one control glyph the drawing stands on. The rest of the stretch
        // makes no glyphs at all, so asking for more would be asking about
        // nothing.
        let anchor = NSRange(location: glyphs.location, length: 1)
        guard let container = textContainer(forGlyphAt: anchor.location, effectiveRange: nil) else {
            return
        }

        var room = boundingRect(forGlyphRange: anchor, in: container)
        room.origin.x += origin.x
        room.origin.y += origin.y

        drawn.draw(in: room, in: storage.font(at: characters.location))
    }

    // MARK: - Finding one again

    /// What is drawn at this point, if anything is — the point being in the
    /// text's own coordinates, which is what a view hands over after taking
    /// its inset off.
    ///
    /// Here rather than wherever the tap arrives, because the room a drawing
    /// took is a glyph's and this is the only object that knows where a glyph
    /// ended up. What is asked of it is the same question drawing asks, from
    /// the other end.
    ///
    /// The nearest glyph on its own would not do: a layout manager answers
    /// that for a point anywhere at all, so a tap three lines below the last
    /// one would find the last box in the day. The room that glyph took has to
    /// hold the point as well — widened to something a thumb can hit, because
    /// a checkbox is about twenty points square and a finger is not.
    ///
    /// Safe to be generous about, because the drawing has already had to be
    /// the glyph *nearest* the point: a finger on the word after a box is
    /// nearest that word and finds nothing here. What the widening reaches is
    /// the margin around the box, and the inset above the first line — which
    /// is where a tap aimed at a box lands when it misses.
    func drawnMarkdown(under point: CGPoint, in container: NSTextContainer) -> DrawnMarkdown? {
        guard let storage = textStorage, storage.length > 0 else { return nil }

        let glyph = glyphIndex(for: point, in: container)
        let room = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard MarkdownLayoutManager.forAFinger(room).contains(point) else { return nil }

        let character = characterIndexForGlyph(at: glyph)
        guard character < storage.length else { return nil }
        return storage.attribute(.drawnMarkdown, at: character, effectiveRange: nil)
            as? DrawnMarkdown
    }

    private static func forAFinger(_ room: CGRect) -> CGRect {
        let comfortable: CGFloat = 44
        return room.insetBy(
            dx: min(0, (room.width - comfortable) / 2),
            dy: min(0, (room.height - comfortable) / 2)
        )
    }
}
