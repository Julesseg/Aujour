import Foundation

/// The markdown in an Entry, read as the shapes an editor draws it in.
///
/// This is the whole of what Aujour knows about markdown while someone is
/// writing: which line is a heading, where its `##` ends and its words begin,
/// which run of characters is emphasised and which two characters made it so.
/// What that *looks like* — how large a heading is, how quiet its hashes are
/// — is the app's, and lives beside the fonts. What it *is* lives here, where
/// it is unit-tested against the text it came from rather than against a
/// screenshot.
///
/// Nothing is hidden and nothing is added. The Entry on screen is the file on
/// disk character for character (ADR 0001), so every syntax character is a
/// character the model points at rather than one it swallows.
///
/// ## One line at a time
///
/// A line's shape is read from that line alone, and no span inside it reaches
/// past its ends. That is a deliberate limit — a fenced code block spanning
/// lines is not modelled, and a heading inside a blockquote is quoted text
/// rather than a heading — and it buys the thing an editor cannot do without:
/// a keystroke costs the lines it touched. The editor restyles the paragraph
/// it was typed in, which is only correct because reading that stretch on its
/// own gives the same answer as reading the whole Entry
/// (`EntryMarkdownLocalityTests`).
///
/// Ranges are UTF-16 offsets into the source, which is what a text view
/// addresses its storage in. ``shifted(by:)`` moves a stretch that was read on
/// its own back into the coordinates of the whole.
public struct EntryMarkdown: Equatable, Sendable {
    /// The Entry's lines, in order — one per line break plus the last, so a
    /// blank line between paragraphs is a line like any other.
    public let lines: [MarkdownLine]

    /// Reads markdown. Cannot fail: every line is *something*, and text that
    /// does not parse as markdown is text.
    public init(_ source: String) {
        let units = Array(source.utf16)
        var lines: [MarkdownLine] = []
        var start = 0
        var index = 0

        while index < units.count {
            let breakLength = EntryMarkdown.lineBreakLength(in: units, at: index)
            guard breakLength > 0 else {
                index += 1
                continue
            }
            lines.append(EntryMarkdown.readLine(units, from: start, to: index))
            index += breakLength
            start = index
        }
        // The text after the last break is a line too, even when it is empty
        // — an Entry ending in a newline ends on a line the cursor can sit on.
        lines.append(EntryMarkdown.readLine(units, from: start, to: units.count))

        self.lines = lines
    }

    private init(lines: [MarkdownLine]) {
        self.lines = lines
    }

    /// The same reading, in the coordinates of a longer text this one is a
    /// stretch of — how the editor puts the lines it restyled back where they
    /// came from.
    public func shifted(by offset: Int) -> EntryMarkdown {
        EntryMarkdown(lines: lines.map { $0.shifted(by: offset) })
    }
}

// MARK: - Lines

/// One line of an Entry: what shape it is, and which characters make it that
/// shape rather than words.
///
/// ``indent``, ``marker`` and ``content`` partition ``range`` exactly, in that
/// order and with no gaps — the editor styles a line by styling its parts, and
/// a character in none of them would be a character with no styling at all.
public struct MarkdownLine: Equatable, Sendable {
    public let block: MarkdownBlock

    /// The line itself, without the break that ended it.
    public let range: NSRange

    /// The whitespace the line starts with — how deeply a list item is
    /// nested, and nothing to draw.
    public let indent: NSRange

    /// The characters that make the line the block it is, and the space that
    /// separates them from the words: `## `, `- `, `1. `, `> `. Empty for a
    /// paragraph, which is made of nothing.
    public let marker: NSRange

    /// The words: everything the marker introduces.
    public let content: NSRange

    /// The spans inside ``content``, outermost first. Nested spans are inside
    /// their parent rather than beside it, so emphasis within strong is found
    /// where it is written.
    public let inlines: [MarkdownInline]

    public func shifted(by offset: Int) -> MarkdownLine {
        MarkdownLine(
            block: block,
            range: range.shifted(by: offset),
            indent: indent.shifted(by: offset),
            marker: marker.shifted(by: offset),
            content: content.shifted(by: offset),
            inlines: inlines.map { $0.shifted(by: offset) }
        )
    }
}

/// What a line is, as a whole.
///
/// One line, one shape: `> # Quoted` is a quote whose words happen to start
/// with a hash, not a heading inside a quote. Blocks that need more than a
/// line to recognise — fenced code, setext headings — are deliberately absent
/// (see ``EntryMarkdown``).
public enum MarkdownBlock: Equatable, Sendable {
    /// Nothing but whitespace.
    case blank

    /// Ordinary words.
    case paragraph

    /// `#` to `######`, followed by a space or by the end of the line.
    case heading(level: Int)

    /// `-`, `*` or `+`, followed by a space.
    case bulletItem

    /// `1.` or `1)`, followed by a space. Carries the number the user wrote,
    /// not the position in the list: a list that starts at 3 starts at 3.
    case numberedItem(number: Int)

    /// One or more `>`, as deep as there are of them.
    case quote(depth: Int)

    /// Three or more of `-`, `*` or `_`, alone on the line.
    case thematicBreak
}

// MARK: - Inline spans

/// A run of characters inside a line that is written differently from the
/// words around it.
///
/// ``opening``, ``content`` and ``closing`` partition ``range``, for the same
/// reason a line's parts partition it: the delimiters are drawn quietly and
/// the words between them are drawn as what they mean, and both have to be
/// pointed at to be drawn at all.
public struct MarkdownInline: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// `*one star*` or `_one underscore_`.
        case emphasis
        /// `**two stars**` or `__two underscores__`.
        case strong
        /// `~~two tildes~~`.
        case strikethrough
        /// `` `backticks` `` — and nothing inside them is anything else.
        case code
        /// `[words](destination)`.
        case link
        /// `![words](destination)` — an embed. Drawing the picture itself is
        /// a later stage of the editor; this is the span it will be drawn
        /// over.
        case image
    }

    public let style: Style

    /// The whole span, delimiters included.
    public let range: NSRange

    /// The delimiter that opened it: `**`, `` ` ``, `[`, `![`.
    public let opening: NSRange

    /// What is between the delimiters — the words themselves.
    public let content: NSRange

    /// The delimiter that closed it. For a link this is the whole
    /// `](destination)`, because all of it is punctuation the words are not.
    public let closing: NSRange

    /// Where a link or an embed points, inside ``closing``.
    public let destination: NSRange?

    /// Spans nested inside ``content`` — emphasis within strong, and the
    /// words of a link. Empty inside code, which shields whatever it holds.
    public let inlines: [MarkdownInline]

    public func shifted(by offset: Int) -> MarkdownInline {
        MarkdownInline(
            style: style,
            range: range.shifted(by: offset),
            opening: opening.shifted(by: offset),
            content: content.shifted(by: offset),
            closing: closing.shifted(by: offset),
            destination: destination?.shifted(by: offset),
            inlines: inlines.map { $0.shifted(by: offset) }
        )
    }
}

// MARK: - Reading lines

extension EntryMarkdown {
    /// How many code units of line break start at `index`, or zero for none.
    ///
    /// The same breaks a text view treats as paragraph ends, so that the
    /// stretch the editor restyles after an edit is exactly a stretch of the
    /// lines read here. `\r\n` counts once, as one break of two units.
    private static func lineBreakLength(in units: [UInt16], at index: Int) -> Int {
        switch units[index] {
        case Unit.carriageReturn:
            return index + 1 < units.count && units[index + 1] == Unit.newline ? 2 : 1
        case Unit.newline, Unit.paragraphSeparator:
            return 1
        default:
            return 0
        }
    }

    private static func readLine(_ units: [UInt16], from start: Int, to end: Int) -> MarkdownLine {
        var cursor = start
        while cursor < end, isSpaceOrTab(units[cursor]) { cursor += 1 }
        let indent = range(start, cursor)

        guard cursor < end else {
            // Whitespace and nothing else. The indent holds it all, so the
            // parts still add up to the line.
            return MarkdownLine(
                block: .blank,
                range: range(start, end),
                indent: indent,
                marker: range(end, end),
                content: range(end, end),
                inlines: []
            )
        }

        let (block, markerEnd) = readBlock(units, at: cursor, to: end)
        return MarkdownLine(
            block: block,
            range: range(start, end),
            indent: indent,
            marker: range(cursor, markerEnd),
            content: range(markerEnd, end),
            // A rule has no words, only the characters that draw it.
            inlines: block == .thematicBreak
                ? []
                : inlines(in: units, from: markerEnd, to: end)
        )
    }

    /// What the line is, and where its marker ends.
    private static func readBlock(
        _ units: [UInt16],
        at cursor: Int,
        to end: Int
    ) -> (MarkdownBlock, markerEnd: Int) {
        // A rule is checked first because it is spelled out of the same
        // characters as the other shapes: `---` is one dash away from a list
        // item, `***` from emphasis.
        if isThematicBreak(units, from: cursor, to: end) {
            return (.thematicBreak, end)
        }
        if let heading = readHeading(units, at: cursor, to: end) {
            return heading
        }
        if let quote = readQuote(units, at: cursor, to: end) {
            return quote
        }
        if let bullet = readBulletItem(units, at: cursor, to: end) {
            return bullet
        }
        if let numbered = readNumberedItem(units, at: cursor, to: end) {
            return numbered
        }
        return (.paragraph, cursor)
    }

    private static func isThematicBreak(_ units: [UInt16], from start: Int, to end: Int) -> Bool {
        let mark = units[start]
        guard mark == Unit.hyphen || mark == Unit.asterisk || mark == Unit.underscore else {
            return false
        }
        var marks = 0
        for index in start..<end {
            if units[index] == mark {
                marks += 1
            } else if !isSpaceOrTab(units[index]) {
                return false
            }
        }
        return marks >= 3
    }

    private static func readHeading(
        _ units: [UInt16],
        at cursor: Int,
        to end: Int
    ) -> (MarkdownBlock, Int)? {
        var index = cursor
        while index < end, units[index] == Unit.hash { index += 1 }
        let level = index - cursor
        // Seven hashes is not a seventh-level heading, and `#tag` is a word:
        // both are what every other markdown editor does, and the second is
        // what keeps a journal full of tags out of headings.
        guard (1...6).contains(level), index == end || isSpaceOrTab(units[index]) else {
            return nil
        }
        return (.heading(level: level), skippingSpaces(units, from: index, to: end))
    }

    private static func readQuote(
        _ units: [UInt16],
        at cursor: Int,
        to end: Int
    ) -> (MarkdownBlock, Int)? {
        guard units[cursor] == Unit.greaterThan else { return nil }
        var index = cursor
        var depth = 0
        while index < end, units[index] == Unit.greaterThan {
            depth += 1
            index = skippingSpaces(units, from: index + 1, to: end)
        }
        return (.quote(depth: depth), index)
    }

    private static func readBulletItem(
        _ units: [UInt16],
        at cursor: Int,
        to end: Int
    ) -> (MarkdownBlock, Int)? {
        let mark = units[cursor]
        guard mark == Unit.hyphen || mark == Unit.asterisk || mark == Unit.plus else { return nil }
        // The space is what separates a bullet from a word that starts with a
        // dash, and `*emphasis*` from a list item.
        guard cursor + 1 == end || isSpaceOrTab(units[cursor + 1]) else { return nil }
        return (.bulletItem, skippingSpaces(units, from: cursor + 1, to: end))
    }

    private static func readNumberedItem(
        _ units: [UInt16],
        at cursor: Int,
        to end: Int
    ) -> (MarkdownBlock, Int)? {
        var index = cursor
        while index < end, isDigit(units[index]), index - cursor < 9 { index += 1 }
        guard index > cursor, index < end else { return nil }
        guard units[index] == Unit.period || units[index] == Unit.rightParenthesis else {
            return nil
        }
        guard index + 1 == end || isSpaceOrTab(units[index + 1]) else { return nil }

        let digits = String(decoding: units[cursor..<index], as: UTF16.self)
        guard let number = Int(digits) else { return nil }
        return (.numberedItem(number: number), skippingSpaces(units, from: index + 1, to: end))
    }

    private static func skippingSpaces(_ units: [UInt16], from index: Int, to end: Int) -> Int {
        var cursor = index
        while cursor < end, isSpaceOrTab(units[cursor]) { cursor += 1 }
        return cursor
    }
}

// MARK: - Reading spans

extension EntryMarkdown {
    /// Every span between `start` and `end`, left to right.
    ///
    /// Recursive: a span's contents are read the same way, which is how
    /// emphasis is found inside strong and words are found inside a link.
    private static func inlines(
        in units: [UInt16],
        from start: Int,
        to end: Int
    ) -> [MarkdownInline] {
        var found: [MarkdownInline] = []
        var index = start

        while index < end {
            switch units[index] {
            case Unit.backslash:
                // An escaped mark is a mark. Both characters are skipped so
                // that `\*` cannot open anything.
                index += index + 1 < end && isASCIIPunctuation(units[index + 1]) ? 2 : 1

            case Unit.backtick:
                if let code = codeSpan(units, at: index, to: end) {
                    found.append(code)
                    index = code.range.upperBound
                } else {
                    index += runLength(units, at: index, to: end)
                }

            case Unit.asterisk, Unit.underscore, Unit.tilde:
                if let span = emphasisSpan(units, at: index, from: start, to: end) {
                    found.append(span)
                    index = span.range.upperBound
                } else {
                    // Past the whole run: a `**` that opens nothing is not two
                    // chances at a `*` that does.
                    index += runLength(units, at: index, to: end)
                }

            case Unit.exclamationMark
            where index + 1 < end && units[index + 1] == Unit.leftBracket:
                if let embed = linkSpan(units, bracket: index + 1, to: end, embedded: true) {
                    found.append(embed)
                    index = embed.range.upperBound
                } else {
                    index += 1
                }

            case Unit.leftBracket:
                if let link = linkSpan(units, bracket: index, to: end, embedded: false) {
                    found.append(link)
                    index = link.range.upperBound
                } else {
                    index += 1
                }

            default:
                index += 1
            }
        }
        return found
    }

    /// `` `code` ``, or `` ``code with a backtick in it`` `` — a run of
    /// backticks, closed by a run of exactly the same length.
    private static func codeSpan(_ units: [UInt16], at index: Int, to end: Int) -> MarkdownInline? {
        let fence = runLength(units, at: index, to: end)
        var cursor = index + fence

        while cursor < end {
            guard units[cursor] == Unit.backtick else {
                cursor += 1
                continue
            }
            let closing = runLength(units, at: cursor, to: end)
            if closing == fence {
                return MarkdownInline(
                    style: .code,
                    range: range(index, cursor + fence),
                    opening: range(index, index + fence),
                    content: range(index + fence, cursor),
                    closing: range(cursor, cursor + fence),
                    destination: nil,
                    // Nothing inside code is markdown — that is what code is.
                    inlines: []
                )
            }
            cursor += closing
        }
        return nil
    }

    /// A run of `*`, `_` or `~` that closes again on the same line.
    private static func emphasisSpan(
        _ units: [UInt16],
        at index: Int,
        from start: Int,
        to end: Int
    ) -> MarkdownInline? {
        let mark = units[index]
        let openRun = runLength(units, at: index, to: end)

        // Nothing to emphasise: a mark followed by a space is arithmetic, or
        // the end of a sentence.
        guard index + openRun < end, !isSpaceOrTab(units[index + openRun]) else { return nil }
        // A single tilde is a tilde.
        guard mark != Unit.tilde || openRun >= 2 else { return nil }
        // `snake_case_names` are words, and a journal is full of them. Stars
        // carry no such rule, so `a*b*c` is emphasised — as it is everywhere.
        guard mark != Unit.underscore || index == start || !isWordUnit(units[index - 1]) else {
            return nil
        }

        var cursor = index + openRun
        while cursor < end {
            if units[cursor] == Unit.backslash {
                cursor += 2
                continue
            }
            // Skipped whole, so that a star inside code cannot close emphasis
            // that opened outside it.
            if units[cursor] == Unit.backtick, let code = codeSpan(units, at: cursor, to: end) {
                cursor = code.range.upperBound
                continue
            }
            guard units[cursor] == mark else {
                cursor += 1
                continue
            }

            let closeRun = runLength(units, at: cursor, to: end)
            if closes(
                units, mark: mark, at: cursor, run: closeRun, openedAt: index + openRun, to: end
            ) {
                let width = mark == Unit.tilde ? 2 : min(openRun, closeRun, 3)
                return span(
                    mark: mark,
                    width: width,
                    openEnd: index + openRun,
                    closeStart: cursor,
                    in: units
                )
            }
            cursor += closeRun
        }
        return nil
    }

    /// Whether a run of marks can be the closing one.
    private static func closes(
        _ units: [UInt16],
        mark: UInt16,
        at cursor: Int,
        run: Int,
        openedAt contentStart: Int,
        to end: Int
    ) -> Bool {
        // There has to be something between the two, and it must not end in a
        // space: `*a *` closes nothing.
        guard cursor > contentStart, !isSpaceOrTab(units[cursor - 1]) else { return false }
        guard mark != Unit.tilde || run >= 2 else { return false }
        // The opening rule, from the other end: an underscore inside a word
        // does not close emphasis either.
        guard mark != Unit.underscore || cursor + run == end || !isWordUnit(units[cursor + run])
        else { return false }
        return true
    }

    /// Builds the span a matched pair of delimiter runs makes.
    ///
    /// The opening delimiter is the *last* `width` marks of the opening run
    /// and the closing one the *first* of the closing run, so that the marks
    /// left over on either side stay plain text next to the span rather than
    /// inside it.
    ///
    /// Three marks are emphasis around strong, which is what markdown means by
    /// `***both***` — and why this returns one span with another inside it
    /// rather than two side by side.
    private static func span(
        mark: UInt16,
        width: Int,
        openEnd: Int,
        closeStart: Int,
        in units: [UInt16]
    ) -> MarkdownInline {
        let openStart = openEnd - width
        let closeEnd = closeStart + width

        guard width == 3 else {
            return MarkdownInline(
                style: mark == Unit.tilde ? .strikethrough : (width == 2 ? .strong : .emphasis),
                range: range(openStart, closeEnd),
                opening: range(openStart, openEnd),
                content: range(openEnd, closeStart),
                closing: range(closeStart, closeEnd),
                destination: nil,
                inlines: inlines(in: units, from: openEnd, to: closeStart)
            )
        }

        let strong = MarkdownInline(
            style: .strong,
            range: range(openStart + 1, closeStart + 2),
            opening: range(openStart + 1, openEnd),
            content: range(openEnd, closeStart),
            closing: range(closeStart, closeStart + 2),
            destination: nil,
            inlines: inlines(in: units, from: openEnd, to: closeStart)
        )
        return MarkdownInline(
            style: .emphasis,
            range: range(openStart, closeEnd),
            opening: range(openStart, openStart + 1),
            content: range(openStart + 1, closeStart + 2),
            closing: range(closeStart + 2, closeEnd),
            destination: nil,
            inlines: [strong]
        )
    }

    /// `[words](destination)`, and its embed twin `![words](destination)`.
    private static func linkSpan(
        _ units: [UInt16],
        bracket: Int,
        to end: Int,
        embedded: Bool
    ) -> MarkdownInline? {
        guard let closeBracket = matching(
            units, open: Unit.leftBracket, close: Unit.rightBracket, from: bracket, to: end
        ) else { return nil }
        guard closeBracket + 1 < end, units[closeBracket + 1] == Unit.leftParenthesis else {
            return nil
        }
        guard let closeParenthesis = matching(
            units,
            open: Unit.leftParenthesis,
            close: Unit.rightParenthesis,
            from: closeBracket + 1,
            to: end
        ) else { return nil }

        let start = embedded ? bracket - 1 : bracket
        return MarkdownInline(
            style: embedded ? .image : .link,
            range: range(start, closeParenthesis + 1),
            opening: range(start, bracket + 1),
            content: range(bracket + 1, closeBracket),
            // All of `](destination)` is punctuation, and drawn as such.
            closing: range(closeBracket, closeParenthesis + 1),
            destination: range(closeBracket + 2, closeParenthesis),
            inlines: inlines(in: units, from: bracket + 1, to: closeBracket)
        )
    }

    /// The index of the delimiter closing the one at `start`, counting nested
    /// pairs so that `[a [b] c](d)` is one link.
    private static func matching(
        _ units: [UInt16],
        open: UInt16,
        close: UInt16,
        from start: Int,
        to end: Int
    ) -> Int? {
        var depth = 0
        var cursor = start
        while cursor < end {
            switch units[cursor] {
            case Unit.backslash:
                cursor += 2
                continue
            case open:
                depth += 1
            case close:
                depth -= 1
                if depth == 0 { return cursor }
            default:
                break
            }
            cursor += 1
        }
        return nil
    }
}

// MARK: - Code units

/// The syntax of markdown is ASCII, so the whole model is read in UTF-16 code
/// units: the offsets a text view addresses its storage in, arrived at without
/// a second pass to convert them.
private enum Unit {
    static let tab: UInt16 = 0x09
    static let newline: UInt16 = 0x0A
    static let carriageReturn: UInt16 = 0x0D
    static let space: UInt16 = 0x20
    static let exclamationMark: UInt16 = 0x21
    static let hash: UInt16 = 0x23
    static let leftParenthesis: UInt16 = 0x28
    static let rightParenthesis: UInt16 = 0x29
    static let asterisk: UInt16 = 0x2A
    static let plus: UInt16 = 0x2B
    static let hyphen: UInt16 = 0x2D
    static let period: UInt16 = 0x2E
    static let zero: UInt16 = 0x30
    static let nine: UInt16 = 0x39
    static let greaterThan: UInt16 = 0x3E
    static let leftBracket: UInt16 = 0x5B
    static let backslash: UInt16 = 0x5C
    static let rightBracket: UInt16 = 0x5D
    static let underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60
    static let tilde: UInt16 = 0x7E
    static let paragraphSeparator: UInt16 = 0x2029
}

private func isSpaceOrTab(_ unit: UInt16) -> Bool {
    unit == Unit.space || unit == Unit.tab
}

private func isDigit(_ unit: UInt16) -> Bool {
    (Unit.zero...Unit.nine).contains(unit)
}

/// What an underscore may not sit next to and still emphasise. Anything
/// outside ASCII counts as a letter, so an accented word is a word.
private func isWordUnit(_ unit: UInt16) -> Bool {
    if isDigit(unit) { return true }
    if (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) { return true }
    return unit >= 0x80
}

private func isASCIIPunctuation(_ unit: UInt16) -> Bool {
    (0x21...0x2F).contains(unit)
        || (0x3A...0x40).contains(unit)
        || (0x5B...0x60).contains(unit)
        || (0x7B...0x7E).contains(unit)
}

/// How many of the same code unit start at `index`.
private func runLength(_ units: [UInt16], at index: Int, to end: Int) -> Int {
    let unit = units[index]
    var cursor = index
    while cursor < end, units[cursor] == unit { cursor += 1 }
    return cursor - index
}

private func range(_ start: Int, _ end: Int) -> NSRange {
    NSRange(location: start, length: end - start)
}

extension NSRange {
    fileprivate func shifted(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}
