import AujourCore
import Foundation
import UIKit

@testable import Aujour

/// An Entry in a text storage with a real layout manager behind it — the only
/// way to ask how wide a mark came out, how tall a line is, or where a
/// paragraph wrapped.
///
/// Shared by every suite that has to measure the editor rather than read its
/// attributes, because all three of them need the same four objects wired up
/// in the same order and the wiring has a trap in it: a layout manager keeps
/// neither its delegate nor its text storage alive, and a storage that went
/// away under one would take the attributes being measured with it. Holding
/// all four here is what makes that somebody else's problem.
///
/// The measurements are deliberately the plain ones — a rect, a width, a font.
/// What any of them *mean* belongs in the suite asking, next to the sentence
/// it is proving.
@MainActor
struct LaidOutDay {
    let storage: MarkdownTextStorage
    let layoutManager: NSLayoutManager
    let container: NSTextContainer
    let glyphs: MarkdownGlyphs

    /// - Parameters:
    ///   - width: how much room the day has. Wide enough that nothing wraps
    ///     unless a test is asking about wrapping.
    ///   - layoutManager: the editor's own where a test is about something
    ///     painted (a box, a picture), and a plain one where it is about the
    ///     room a character takes.
    init(
        _ source: String,
        styling: MarkdownStyling = MarkdownStyling(),
        cursor: NSRange? = nil,
        width: CGFloat = 2000,
        layoutManager: NSLayoutManager = NSLayoutManager(),
        pictures: EmbeddedPictures? = nil
    ) {
        let storage = MarkdownTextStorage(styling: styling)
        let glyphs = MarkdownGlyphs()
        let container = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )

        layoutManager.delegate = glyphs
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        storage.pictures = pictures
        storage.setSource(source)
        storage.cursor = cursor
        layoutManager.ensureLayout(for: container)

        self.storage = storage
        self.layoutManager = layoutManager
        self.container = container
        self.glyphs = glyphs
    }

    /// Moves the cursor and lays the day out again — the interaction itself,
    /// rather than two days built separately and compared. What a caret
    /// arriving does to a day that is already on screen is the question every
    /// live-preview measurement is really asking.
    func moveCursor(to cursor: NSRange?) {
        storage.cursor = cursor
        layoutManager.ensureLayout(for: container)
    }

    func moveCaret(to caret: Int) {
        moveCursor(to: NSRange(location: caret, length: 0))
    }

    // MARK: - What a character is drawn as

    func font(at character: Int) -> UIFont? {
        storage.attribute(.font, at: character, effectiveRange: nil) as? UIFont
    }

    func colour(at character: Int) -> UIColor? {
        storage.attribute(.foregroundColor, at: character, effectiveRange: nil) as? UIColor
    }

    /// Every character's font over a stretch, as something that compares and
    /// reads back when it does not: `.SFUI-Semibold@26.35`.
    func fonts(over range: NSRange) -> [String] {
        (range.location..<range.upperBound).map { character in
            guard let font = font(at: character) else { return "—" }
            return "\(font.fontName)@\(font.pointSize)"
        }
    }

    var whole: NSRange {
        NSRange(location: 0, length: storage.length)
    }

    // MARK: - How much room it took

    /// How much room a stretch of characters takes on screen — nothing at all,
    /// for the ones that were not turned into glyphs.
    func width(of characters: NSRange) -> CGFloat {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characters,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return 0 }
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).width
    }

    func lineWidth(atCharacter character: Int) -> CGFloat {
        lineFragment(atCharacter: character).width
    }

    func lineHeight(atCharacter character: Int) -> CGFloat {
        lineFragment(atCharacter: character).height
    }

    func lineTop(atCharacter character: Int) -> CGFloat {
        lineFragment(atCharacter: character).minY
    }

    private func lineFragment(atCharacter character: Int) -> CGRect {
        let glyph = layoutManager.glyphIndexForCharacter(at: character)
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    // MARK: - Where the day broke into lines

    /// Every line the day came out as. The fragment rather than the used rect,
    /// because a line that moved down the page moved whether or not its words
    /// changed.
    func lineFragments() -> [CGRect] {
        fragments(fromGlyph: 0)
    }

    /// The lines from the one a character sits on onwards — what "the rest of
    /// the day did not move" is asked as.
    func lineFragments(from character: Int) -> [CGRect] {
        fragments(fromGlyph: layoutManager.glyphIndexForCharacter(at: character))
    }

    func lineHeights() -> [CGFloat] {
        lineFragments().map(\.height)
    }

    /// How much of each line the words actually filled — the fragment is the
    /// full width of the page whatever is written on it, so this is the one
    /// that moves when a mark takes its room back.
    func lineUsedWidths() -> [CGFloat] {
        layoutManager.ensureLayout(for: container)
        var widths: [CGFloat] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, used, _, _, _ in
            widths.append(used.width)
        }
        return widths
    }

    private func fragments(fromGlyph first: Int) -> [CGRect] {
        layoutManager.ensureLayout(for: container)
        var fragments: [CGRect] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(
                location: first,
                length: layoutManager.numberOfGlyphs - first
            )
        ) { rect, _, _, _, _ in
            fragments.append(rect)
        }
        return fragments
    }
}
