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

        let font =
            storage.attribute(.font, at: characters.location, effectiveRange: nil) as? UIFont
            ?? .preferredFont(forTextStyle: .body)
        drawn.draw(in: room, in: font)
    }
}
