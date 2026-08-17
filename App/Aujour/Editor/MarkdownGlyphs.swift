import UIKit

extension NSAttributedString.Key {
    /// Marks characters the editor draws as nothing at all — the syntax
    /// ``AujourCore/HiddenSyntax`` says the cursor is not in, and the
    /// characters a box or a picture is standing in front of.
    ///
    /// An attribute rather than a list held to one side, because the text
    /// storage is what every part of the editor already agrees about: the
    /// styling puts it on while it is drawing a paragraph, glyph generation
    /// reads it back below, and a stretch that is restyled loses it with every
    /// other attribute it had. Nothing has to be kept in step with anything.
    static let hiddenSyntax = NSAttributedString.Key("AujourHiddenSyntax")
}

/// Decides what room each of an Entry's characters takes on screen: none for
/// the ones the storage marked hidden, and a box's or a picture's worth for
/// the one it marked drawn.
///
/// This is the whole mechanism of live preview, and it is deliberately the
/// only place in the app that can make a character take up a different amount
/// of room than it is. Glyphs are where it has to happen: the text is
/// untouched (ADR 0001) and so are the attributes, so what changes is the one
/// step between a character and a mark on screen — TextKit asks which glyphs a
/// run of characters makes, and this answers "none" for the hidden ones and
/// "one, this big" for the character a drawing stands on. They all keep their
/// place in the text, the caret can still be put among them, and the file has
/// never heard of any of it.
///
/// Painting the box and the picture is ``MarkdownLayoutManager``'s, which
/// draws into exactly the room asked for here.
final class MarkdownGlyphs: NSObject, NSLayoutManagerDelegate {
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
        var anyChanged = false

        // The attribute is asked for a run at a time rather than a character
        // at a time: glyphs are generated in long batches, and the answer is
        // the same for every character of a paragraph that has no syntax in it
        // at all — which is most of them.
        var run = NSRange(location: NSNotFound, length: 0)
        var runIsHidden = false

        for glyph in 0..<glyphRange.length {
            let character = characterIndexes[glyph]
            guard character < storage.length else { continue }

            // Asked first and one character at a time, because a drawing
            // stands on a single character in the middle of a hidden run and
            // is the exception to it.
            if storage.attribute(.drawnMarkdown, at: character, effectiveRange: nil) != nil {
                // Not a mark of its own: a control character laid out as
                // whitespace, whose width and height this delegate is asked
                // for below and into which the layout manager paints.
                amended[glyph] = .controlCharacter
                anyChanged = true
                run = NSRange(location: NSNotFound, length: 0)
                continue
            }

            if !NSLocationInRange(character, run) {
                runIsHidden =
                    storage.attribute(.hiddenSyntax, at: character, effectiveRange: &run) != nil
            }
            guard runIsHidden else { continue }
            // Not drawn and not laid out: the characters either side of it
            // close up, which is what makes an Entry read as a document.
            //
            // Replacing whatever TextKit said rather than adding to it, on
            // purpose. A hidden character is not an elastic anything and not a
            // control character to take action over — it is nothing at all,
            // and every other property of it describes a mark that is not
            // being made.
            amended[glyph] = .null
            anyChanged = true
        }

        // Nothing changed in this batch — which is the common answer, and
        // returning zero leaves TextKit's own glyphs exactly as they were.
        guard anyChanged else { return 0 }

        layoutManager.setGlyphs(
            glyphs,
            properties: &amended,
            characterIndexes: characterIndexes,
            font: font,
            forGlyphRange: glyphRange
        )
        return glyphRange.length
    }

    /// What TextKit should do with the control characters made above: leave a
    /// gap of the size asked for next, and nothing else.
    ///
    /// Every other action a control character can have — a tab stop, a line
    /// break, a zero-advance mark — is about a character that means something
    /// to the typesetter. This one means something to Aujour, and the
    /// typesetter's only part in it is holding the space open.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt characterIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard drawing(in: layoutManager, at: characterIndex) != nil else { return action }
        return .whitespace
    }

    /// How much room to leave: what the drawing says it needs, in the font
    /// that line is set in and the width still free on it.
    ///
    /// Asked at layout rather than answered once and stored, because the
    /// answer moves with the text container — a rotated iPad and a
    /// half-screen iPhone are different widths for the same photo — and
    /// because Dynamic Type changes the font a box is measured against.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: CGRect,
        glyphPosition: CGPoint,
        characterIndex: Int
    ) -> CGRect {
        guard let storage = layoutManager.textStorage,
            let drawn = drawing(in: layoutManager, at: characterIndex)
        else { return .zero }
        let font = storage.font(at: characterIndex)
        // What is left of the line after everything already on it — a picture
        // is as wide as the text is, and an indented one is narrower by its
        // indent.
        let free = proposedRect.width - (glyphPosition.x - proposedRect.minX)
        let size = drawn.size(in: font, fitting: max(free, 1))
        return CGRect(origin: .zero, size: size)
    }

    /// Makes the line as tall as the picture on it.
    ///
    /// The room asked for above is the room the *glyph* takes, and a line's
    /// height does not come from its glyphs — it comes from the font the line
    /// is set in, which knows nothing about a photograph. Without this the
    /// picture would be painted over the sentence below it.
    ///
    /// The baseline goes to the bottom of the taller line, so that words
    /// sharing the line with a picture sit under it rather than through it.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        let width = lineFragmentRect.pointee.width
        guard let tallest = tallestDrawing(in: layoutManager, over: glyphRange, fitting: width),
            tallest > lineFragmentUsedRect.pointee.height
        else { return false }

        lineFragmentRect.pointee.size.height = tallest
        lineFragmentUsedRect.pointee.size.height = tallest
        baselineOffset.pointee = tallest
        return true
    }

    /// How tall the tallest thing drawn on this line is, or `nil` for a line
    /// with nothing drawn on it — which is nearly every line, and the answer
    /// that leaves the typesetter's own arithmetic alone.
    private func tallestDrawing(
        in layoutManager: NSLayoutManager,
        over glyphRange: NSRange,
        fitting width: CGFloat
    ) -> CGFloat? {
        guard let storage = layoutManager.textStorage, storage.length > 0 else { return nil }
        let characters = layoutManager.characterRange(
            forGlyphRange: glyphRange, actualGlyphRange: nil
        )
        guard characters.length > 0, characters.upperBound <= storage.length else { return nil }

        var tallest: CGFloat?
        storage.enumerateAttribute(.drawnMarkdown, in: characters) { value, range, _ in
            guard let drawn = value as? DrawnMarkdown else { return }
            let room = drawn.size(in: storage.font(at: range.location), fitting: max(width, 1))
            tallest = max(tallest ?? 0, room.height)
        }
        return tallest
    }

    // MARK: - Reading it back

    private func drawing(in layoutManager: NSLayoutManager, at character: Int) -> DrawnMarkdown? {
        guard let storage = layoutManager.textStorage, character < storage.length else {
            return nil
        }
        return storage.attribute(.drawnMarkdown, at: character, effectiveRange: nil)
            as? DrawnMarkdown
    }
}
