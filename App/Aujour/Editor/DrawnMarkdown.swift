import UIKit

extension NSAttributedString.Key {
    /// Marks the one character an editor draws something else over: a task
    /// item's box, or an embed's picture.
    ///
    /// On the first character of the stretch and nowhere else. The rest of it
    /// carries ``hiddenSyntax`` and makes no glyphs at all, so the drawing has
    /// exactly one place in the line to stand and the characters either side
    /// of it close up around it.
    ///
    /// An attribute for the same reason hiding is one: the text storage is
    /// what every part of the editor already agrees about. The styling puts it
    /// on while drawing a paragraph, glyph generation reads it back to make
    /// room, the layout manager reads it back to draw, a tap reads it back to
    /// know what was tapped — and a stretch that is restyled loses it with
    /// every other attribute it had.
    static let drawnMarkdown = NSAttributedString.Key("AujourDrawnMarkdown")
}

/// Something the editor draws where an Entry's own characters would have gone.
///
/// A box or a picture, with the room it needs and how to paint it — the whole
/// of what the layout and the drawing need to know, so that neither has to ask
/// what kind of thing this is. Which stretches get one is
/// ``AujourCore/DrawnElements``' to say, and it says so from the text alone;
/// this is that answer once there is a font, a colour and a picture to make it
/// out of.
///
/// Nothing here changes the text. The characters underneath are still in the
/// storage and still in the file, still selectable and still deletable
/// (ADR 0001) — they are simply not the marks being made on screen while the
/// cursor is somewhere else.
final class DrawnMarkdown: NSObject {
    enum Kind {
        /// `- [x] `, drawn as a box the user can tap.
        case taskBox(isDone: Bool)
        /// `![…](…)`, drawn as the picture it points at.
        case picture(UIImage)
    }

    let kind: Kind

    /// The characters this stands in for — what a tap on it means, and what a
    /// restyle has to cover to take it away again.
    let text: NSRange

    /// The colour a box is drawn in. A picture brings its own.
    let tint: UIColor

    init(_ kind: Kind, over text: NSRange, tint: UIColor) {
        self.kind = kind
        self.text = text
        self.tint = tint
    }

    /// Whether this is something the user can tap to change the Entry.
    var isTappable: Bool {
        if case .taskBox = kind { return true }
        return false
    }

    // MARK: - How much room it takes

    /// The tallest a picture is ever drawn, whatever the photo's own size.
    ///
    /// A journal is words with pictures in it, not an album: a portrait photo
    /// at full width would be a screenful, and the sentence after it would be
    /// a scroll away from the sentence before. Landscape or portrait, an embed
    /// leaves room for the writing around it.
    private static let tallestPicture: CGFloat = 280

    /// The room the drawing needs on the line, in the font the line is set in
    /// and the width the text has to spread over.
    ///
    /// A box is square and the height of a line, plus the gap that separates
    /// it from the first word — so a task item sits exactly where its bullet
    /// did. A picture is as big as it can be without being wider than the
    /// text or taller than a journal wants, and never larger than it really
    /// is: a small picture drawn large is a blurred one.
    func size(in font: UIFont, fitting width: CGFloat) -> CGSize {
        switch kind {
        case .taskBox:
            let side = (font.capHeight * 1.5).rounded()
            return CGSize(width: side + font.pointSize * 0.4, height: font.lineHeight)
        case .picture(let picture):
            let natural = picture.size
            guard natural.width > 0, natural.height > 0 else { return .zero }
            let scale = min(
                1, width / natural.width, DrawnMarkdown.tallestPicture / natural.height
            )
            return CGSize(
                width: (natural.width * scale).rounded(),
                height: (natural.height * scale).rounded()
            )
        }
    }

    // MARK: - Painting it

    /// Draws into the space the layout left, which is a whole line's height —
    /// so a box is centred in it and a picture fills it from the top.
    func draw(in room: CGRect, in font: UIFont) {
        let size = size(in: font, fitting: room.width)
        switch kind {
        case .taskBox(let isDone):
            let side = min(size.height, room.height)
            let box = CGRect(
                x: room.minX,
                y: room.minY + ((room.height - side) / 2).rounded(),
                width: side,
                height: side
            )
            symbol(isDone: isDone, fitting: side)?.draw(in: box)
        case .picture(let picture):
            let drawn = CGRect(origin: room.origin, size: size)
            let rounded = UIBezierPath(roundedRect: drawn, cornerRadius: 8)
            UIGraphicsGetCurrentContext()?.saveGState()
            rounded.addClip()
            picture.draw(in: drawn)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
    }

    private func symbol(isDone: Bool, fitting side: CGFloat) -> UIImage? {
        UIImage(
            systemName: isDone ? "checkmark.square.fill" : "square",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: side, weight: .regular)
        )?
        .withTintColor(tint, renderingMode: .alwaysOriginal)
    }
}
