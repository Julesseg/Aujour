import UIKit

extension NSAttributedString.Key {
    /// Marks characters the editor draws as nothing at all — the syntax
    /// ``AujourCore/HiddenSyntax`` says the cursor is not in.
    ///
    /// An attribute rather than a list held to one side, because the text
    /// storage is what every part of the editor already agrees about: the
    /// styling puts it on while it is drawing a paragraph, glyph generation
    /// reads it back below, and a stretch that is restyled loses it with every
    /// other attribute it had. Nothing has to be kept in step with anything.
    static let hiddenSyntax = NSAttributedString.Key("AujourHiddenSyntax")
}

/// Leaves out the glyphs for the characters the storage marked hidden, so that
/// syntax away from the cursor takes up no space rather than being drawn in
/// the background colour.
///
/// This is the whole mechanism of live preview, and it is deliberately the
/// only place in the app that can make a character disappear. Glyphs are where
/// it has to happen: the text is untouched (ADR 0001) and the attributes are
/// untouched, so what changes is the one step between a character and a mark
/// on screen — TextKit asks which glyphs a run of characters makes, and this
/// answers "none" for the hidden ones. They keep their place in the text, the
/// caret can still be put among them, and the file has never heard of any of
/// it.
final class HiddenSyntaxGlyphs: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: UIFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }

        var amended = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var anyHidden = false

        // The attribute is asked for a run at a time rather than a character
        // at a time: glyphs are generated in long batches, and the answer is
        // the same for every character of a paragraph that has no syntax in it
        // at all — which is most of them.
        var run = NSRange(location: NSNotFound, length: 0)
        var runIsHidden = false

        for glyph in 0..<glyphRange.length {
            let character = characterIndexes[glyph]
            guard character < storage.length else { continue }
            if !NSLocationInRange(character, run) {
                runIsHidden =
                    storage.attribute(.hiddenSyntax, at: character, effectiveRange: &run) != nil
            }
            guard runIsHidden else { continue }
            // Not drawn and not laid out: the characters either side of it
            // close up, which is what makes an Entry read as a document.
            amended[glyph] = .null
            anyHidden = true
        }

        // Nothing hidden in this batch — which is the common answer, and
        // returning zero leaves TextKit's own glyphs exactly as they were.
        guard anyHidden else { return 0 }

        layoutManager.setGlyphs(
            glyphs,
            properties: &amended,
            characterIndexes: characterIndexes,
            font: font,
            forGlyphRange: glyphRange
        )
        return glyphRange.length
    }
}
