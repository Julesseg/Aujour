import AujourCore
import UIKit

extension NSAttributedString.Key {
    /// Marks the one character an editor draws something else over: a task
    /// item's box, an embed's picture, or an unanswered placeholder's widget.
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
/// A box, a picture or a widget, with the room it needs and how to paint it —
/// the whole of what the layout and the drawing need to know, so that neither
/// has to ask what kind of thing this is. Which stretches get one is
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
        /// `- [x] `, drawn as a box the user can tap — in the colour a
        /// control is drawn in, which a picture has no use for and so does
        /// not carry.
        case taskBox(isDone: Bool, tint: UIColor)
        /// `![…](…)`, drawn as the picture it points at.
        case picture(UIImage)
        /// `{{mood}}`, drawn as the widget that asks it — one chip over the
        /// whole token, carrying the placeholder's own name and symbol, which
        /// is what an unanswered question looks like in the middle of a
        /// sentence.
        ///
        /// Over the whole token including a `:FORMAT` suffix, because the
        /// format is part of the question and goes when the question is
        /// answered. A token that words itself —
        /// `{{mood:Woke up feeling {value}}}` — is the same one chip, and not
        /// the format's words drawn as prose around a smaller one.
        case widget(InteractivePlaceholder, chip: ChipColours)
    }

    let kind: Kind

    /// The characters this stands in for — what a tap on it means, and what a
    /// restyle has to cover to take it away again.
    let text: NSRange

    init(_ kind: Kind, over text: NSRange) {
        self.kind = kind
        self.text = text
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
    /// is: a small picture drawn large is a blurred one. A widget is a line
    /// tall and as wide as the word on it, because it stands in the middle of
    /// a sentence and a sentence is what it will become.
    func size(in font: UIFont, fitting width: CGFloat) -> CGSize {
        switch kind {
        case .taskBox:
            let side = (font.capHeight * 1.5).rounded()
            return CGSize(width: side + font.pointSize * 0.4, height: font.lineHeight)
        case .widget(let placeholder, let colours):
            let chip = Chip(placeholder, in: font, colours: colours)
            return CGSize(width: min(chip.width, width), height: font.lineHeight)
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
        case .taskBox(let isDone, let tint):
            let side = min(size.height, room.height)
            let box = CGRect(
                x: room.minX,
                y: room.minY + ((room.height - side) / 2).rounded(),
                width: side,
                height: side
            )
            symbol(isDone: isDone, tinted: tint, fitting: side)?.draw(in: box)
        case .widget(let placeholder, let colours):
            // As wide as it asked for and as tall as the line, which is what
            // the chip centres itself in.
            let space = CGRect(
                origin: room.origin,
                size: CGSize(width: size.width, height: room.height)
            )
            Chip(placeholder, in: font, colours: colours).draw(in: space)
        case .picture(let picture):
            let drawn = CGRect(origin: room.origin, size: size)
            let rounded = UIBezierPath(roundedRect: drawn, cornerRadius: 8)
            UIGraphicsGetCurrentContext()?.saveGState()
            rounded.addClip()
            picture.draw(in: drawn)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
    }

    /// The face a chip's lettering is set in, for a line of the Entry set in
    /// `line`.
    ///
    /// The identity's chip role's face and weight, and never the face the day
    /// is written in. That is the load-bearing half: a chip is a control, and
    /// one set in the reader's own serif or monospace would read as words they
    /// typed rather than as a question waiting for them.
    ///
    /// Its *size* is the line's rather than the role's own, because a chip
    /// stands inside a line and has to fit one. The Entry is the one thing on
    /// the device the S/M/L/XL writing control moves, so a fixed 13 points
    /// would be a chip to squint at in a day set to XL and a chip taller than
    /// its line in a day set to S with the system's text size turned up. Taken
    /// off the line it is the same proportion at every setting of both — and
    /// the proportion is the identity's own, which draws a chip at 13 points
    /// where the prose it sits among is 17.
    static func chipLettering(in line: UIFont) -> UIFont {
        Lettering.chipLabel.uiFont(ofSize: (line.pointSize * chipAgainstItsLine).rounded())
    }

    private static let chipAgainstItsLine = Lettering.chipLabel.size / Lettering.prose.size

    /// The chip an unanswered placeholder is drawn as: its name and its
    /// symbol, on a wash of the accent, on the line where its token stands.
    ///
    /// One chip over the whole token and nothing else — a `:FORMAT` suffix is
    /// covered by the same chip, because the format is the question's wording
    /// and not words standing beside it.
    ///
    /// A chip drawn as a *pill*, which is two of the identity's words and not
    /// a muddle of them (`Metrics`). "Chip" is what this is — a small labelled
    /// control, the word `CONTEXT.md` and the design decisions both use for it
    /// — and a pill is the shape it takes, which is why it does not wear
    /// ``Rounding/chip``: that role is the 6-point corner for a chip too small
    /// to round further, and this one is a capsule at every size the type
    /// scale can grow it to.
    ///
    /// Small enough to sit inside a line's own height either way, so that a
    /// paragraph with a question in it is still a paragraph.
    ///
    /// What it says is the placeholder's own (`PlaceholderWidgets`), which is
    /// all a new one has to bring to be drawn.
    private struct Chip {
        /// The identity's own steps: the gap either side of the words, and the
        /// tighter one between a thing and its own label.
        private static let padding = Spacing.close
        private static let gap = Spacing.tight

        private let title: NSAttributedString
        private let symbol: UIImage?
        private let colours: ChipColours
        private let height: CGFloat

        init(
            _ placeholder: InteractivePlaceholder,
            in font: UIFont,
            colours: ChipColours
        ) {
            let lettering = DrawnMarkdown.chipLettering(in: font)
            self.title = NSAttributedString(
                string: placeholder.title,
                attributes: [
                    .font: lettering,
                    .foregroundColor: colours.ink,
                    // The role's tracking at the size it actually came out —
                    // a role that lost its tracking on the way to the screen
                    // is a role drawn wrong.
                    .kern: Lettering.chipLabel.tracking(atSize: lettering.pointSize),
                ]
            )
            self.symbol = UIImage(
                systemName: placeholder.symbol,
                withConfiguration: UIImage.SymbolConfiguration(font: lettering)
            )?.withTintColor(colours.ink, renderingMode: .alwaysOriginal)
            self.colours = colours
            self.height = font.lineHeight
        }

        var width: CGFloat {
            let symbolWidth = symbol.map { $0.size.width + Chip.gap } ?? 0
            return (Chip.padding * 2 + symbolWidth + title.size().width).rounded()
        }

        /// Into the room the layout left, which is a whole line's height — so
        /// the chip is centred in it, as a box is.
        func draw(in room: CGRect) {
            let chip = CGRect(
                x: room.minX,
                y: room.minY + ((room.height - height) / 2).rounded(),
                width: room.width,
                height: height
            )
            colours.wash.setFill()
            // A pill, in the sense `Metrics` gives the word: half its own
            // height, which is `Capsule()` written for a path.
            UIBezierPath(roundedRect: chip, cornerRadius: height / 2).fill()

            var cursor = chip.minX + Chip.padding
            if let symbol {
                symbol.draw(
                    in: CGRect(
                        x: cursor,
                        y: chip.midY - symbol.size.height / 2,
                        width: symbol.size.width,
                        height: symbol.size.height
                    )
                )
                cursor += symbol.size.width + Chip.gap
            }
            let words = title.size()
            title.draw(at: CGPoint(x: cursor, y: chip.midY - words.height / 2))
        }
    }

    private func symbol(isDone: Bool, tinted: UIColor, fitting side: CGFloat) -> UIImage? {
        UIImage(
            systemName: isDone ? "checkmark.square.fill" : "square",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: side, weight: .regular)
        )?
        .withTintColor(tinted, renderingMode: .alwaysOriginal)
    }
}

extension NSAttributedString {
    /// The font a character is set in — the body face for one that somehow is
    /// not set in anything, which is nothing this editor ever writes.
    ///
    /// Here because the two halves of drawing over a stretch of text both need
    /// it and neither owns it: glyph generation measures a box in the line's
    /// own font, and the layout manager paints it in the same one.
    func font(at character: Int) -> UIFont {
        guard character < length else { return .preferredFont(forTextStyle: .body) }
        return attribute(.font, at: character, effectiveRange: nil) as? UIFont
            ?? .preferredFont(forTextStyle: .body)
    }
}
