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
/// addresses its storage in — and they stay in the source's coordinates
/// whether the whole Entry was read or only the lines around an edit, so a
/// reading can be drawn onto the text it came from without any arithmetic in
/// between.
public struct EntryMarkdown: Equatable, Sendable {
    /// The stretch of the source these lines cover: all of it, or the whole
    /// lines an edit touched.
    public let range: NSRange

    /// The lines, in order — one per line break plus the last, so a blank line
    /// between paragraphs is a line like any other.
    public let lines: [MarkdownLine]

    /// Reads the whole of it. Cannot fail: every line is *something*, and text
    /// that does not parse as markdown is text.
    public init(_ source: String) {
        let units = Array(source.utf16)
        self.init(units, covering: bounds(0, units.count))
    }

    /// Reads only the whole lines an edit can have changed the meaning of.
    ///
    /// What the editor asks after every keystroke, and the reason blocks are
    /// one line: the answer for this stretch is the answer it has in the whole
    /// Entry, so the editor can restyle a paragraph and leave the rest of the
    /// day alone (`EntryMarkdownLocalityTests`).
    ///
    /// Wider than the edit at both ends. Backwards to the start of the line
    /// the edit begins in — a `#` typed at the front of a line is what makes
    /// the *rest* of it a heading. Forwards past the end of the line it ends
    /// in, which is one line further when the edit ended on a line break: a
    /// return typed into the middle of a heading leaves half a heading above
    /// the break and words that are not a heading at all below it, and the
    /// half below was never touched.
    public init(_ source: String, around edit: NSRange) {
        let units = Array(source.utf16)
        self.init(units, covering: EntryMarkdown.wholeLines(of: units, around: edit))
    }

    private init(_ units: [UInt16], covering stretch: NSRange) {
        self.range = stretch

        var lines: [MarkdownLine] = []
        var start = stretch.location
        var index = start

        while index < stretch.upperBound {
            let breakLength = EntryMarkdown.lineBreakLength(in: units, at: index)
            guard breakLength > 0 else {
                index += 1
                continue
            }
            lines.append(EntryMarkdown.readLine(units, from: start, to: index, ending: breakLength))
            index += breakLength
            start = index
        }

        // The text after the last break is a line too, even when it is empty —
        // an Entry ending in a newline ends on a line the cursor can sit on.
        // Unless a stretch stopped at that break part-way through the Entry,
        // where the line after it runs on past what was read.
        if start < stretch.upperBound || stretch.upperBound == units.count {
            lines.append(
                EntryMarkdown.readLine(units, from: start, to: stretch.upperBound, ending: 0)
            )
        }
        self.lines = lines
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

    /// The line together with that break — what a text system calls a
    /// paragraph, and the stretch a line's own font and spacing are drawn
    /// over. Including the break, because the caret sits after the last word
    /// of a heading too, and it should be a heading's height there.
    public let paragraph: NSRange

    /// The whitespace the line starts with — how deeply a list item is
    /// nested, and nothing to draw.
    public let indent: NSRange

    /// The characters that make the line the block it is, and the space that
    /// separates them from the words: `## `, `- `, `1. `, `> `, `- [x] `.
    /// Empty for a paragraph, which is made of nothing.
    public let marker: NSRange

    /// A task item's `[ ]` or `[x]` — the three characters the editor draws a
    /// box over. Inside ``marker`` rather than beside it, because the box is
    /// part of what makes the line a task; empty on every other line.
    public let box: NSRange

    /// The words: everything the marker introduces.
    public let content: NSRange

    /// The spans inside ``content``, outermost first. Nested spans are inside
    /// their parent rather than beside it, so emphasis within strong is found
    /// where it is written.
    public let inlines: [MarkdownInline]
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

    /// A bullet whose first word is a box: `- [ ]` or `- [x]`, followed by a
    /// space or the end of the line. Carries whether the box is ticked.
    ///
    /// Only the two states markdown's task lists actually agree on. Obsidian
    /// lets a theme give `- [/]` or `- [-]` a look of its own; those are a
    /// bullet whose words begin with a bracket here, which is what they are
    /// anywhere the theme is not.
    case taskItem(isDone: Bool)

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
        /// `![words](destination)`, or Obsidian's `![[target]]` — an embed,
        /// and the span the editor draws a picture over. Both spellings are
        /// read wherever they are written: the embed-syntax setting decides
        /// what Aujour *writes*, and a journal shared with Obsidian holds
        /// whatever anything else wrote.
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
    /// `](destination)` — where it points included, because all of it is
    /// punctuation the words are not, and all of it is drawn that way.
    public let closing: NSRange

    /// Where a link or an embed points: what is between `](` and `)`, or a
    /// wiki embed's target up to its `|`. Empty for every other style, and
    /// for a link that points nowhere.
    ///
    /// Inside ``closing`` for a standard link and inside ``content`` for a
    /// wiki one — this is not a fourth part of the span but a reading of the
    /// part it lives in, so that finding the file an embed names is not a
    /// second parse of the same characters.
    public let destination: NSRange

    /// Spans nested inside ``content`` — emphasis within strong, and the
    /// words of a link. Empty inside code, which shields whatever it holds.
    public let inlines: [MarkdownInline]

    /// The punctuation either side of the words: ``opening`` and ``closing``,
    /// whichever of them there are. Both are drawn alike and hidden alike —
    /// a span is never quiet at one end and loud at the other — so what wants
    /// them wants both, and asking for them together is one place to be wrong
    /// rather than two.
    public var delimiters: [NSRange] {
        [opening, closing].filter { $0.length > 0 }
    }
}

// MARK: - Reading lines

extension EntryMarkdown {
    /// How many code units of line break start at `index`, or zero for none.
    ///
    /// The breaks a paragraph can end on, written down once so that the
    /// editor's idea of the stretch to re-read and this model's idea of a line
    /// cannot drift apart. `\r\n` counts once, as one break of two units.
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

    /// Whether a line ends immediately before `index` — the same rule read
    /// backwards, for finding the start of the line an edit landed in. The
    /// `\n` of a `\r\n` is the middle of a break and ends nothing.
    private static func endsALine(_ units: [UInt16], at index: Int) -> Bool {
        guard index > 0 else { return false }
        switch units[index - 1] {
        case Unit.newline, Unit.paragraphSeparator:
            return true
        case Unit.carriageReturn:
            return index >= units.count || units[index] != Unit.newline
        default:
            return false
        }
    }

    /// The whole lines an edit at `edit` reaches — see ``init(_:around:)``.
    private static func wholeLines(of units: [UInt16], around edit: NSRange) -> NSRange {
        func inBounds(_ index: Int) -> Int { min(max(index, 0), units.count) }

        var start = inBounds(edit.location)
        while start > 0, !endsALine(units, at: start) { start -= 1 }

        var end = max(start, inBounds(edit.upperBound))
        while end < units.count {
            let breakLength = lineBreakLength(in: units, at: end)
            guard breakLength == 0 else {
                end += breakLength
                break
            }
            end += 1
        }
        return bounds(start, end)
    }

    private static func readLine(
        _ units: [UInt16],
        from start: Int,
        to end: Int,
        ending breakLength: Int
    ) -> MarkdownLine {
        var cursor = start
        while cursor < end, isSpaceOrTab(units[cursor]) { cursor += 1 }
        let indent = bounds(start, cursor)
        let paragraph = bounds(start, end + breakLength)

        guard cursor < end else {
            // Whitespace and nothing else. The indent holds it all, so the
            // parts still add up to the line.
            return MarkdownLine(
                block: .blank,
                range: bounds(start, end),
                paragraph: paragraph,
                indent: indent,
                marker: bounds(end, end),
                box: bounds(end, end),
                content: bounds(end, end),
                inlines: []
            )
        }

        let marker = readBlock(units, at: cursor, to: end)
        return MarkdownLine(
            block: marker.block,
            range: bounds(start, end),
            paragraph: paragraph,
            indent: indent,
            marker: bounds(cursor, marker.end),
            box: marker.box,
            content: bounds(marker.end, end),
            // A rule has no words, only the characters that draw it.
            inlines: marker.block == .thematicBreak
                ? []
                : inlines(in: units, from: marker.end, to: end)
        )
    }

    /// What a line's opening characters make it: its shape, where those
    /// characters stop and the words start, and — for a task item — where its
    /// box is among them.
    private struct Marker {
        let block: MarkdownBlock
        let end: Int
        let box: NSRange

        init(_ block: MarkdownBlock, end: Int, box: NSRange? = nil) {
            self.block = block
            self.end = end
            // Nothing to draw a box over, said as an empty range where the
            // words begin rather than as an optional every caller unwraps.
            self.box = box ?? bounds(end, end)
        }
    }

    /// What the line is, and where its marker ends.
    private static func readBlock(_ units: [UInt16], at cursor: Int, to end: Int) -> Marker {
        // A rule is checked first because it is spelled out of the same
        // characters as the other shapes: `---` is one dash away from a list
        // item, `***` from emphasis.
        if isThematicBreak(units, from: cursor, to: end) {
            return Marker(.thematicBreak, end: end)
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
        return Marker(.paragraph, end: cursor)
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

    private static func readHeading(_ units: [UInt16], at cursor: Int, to end: Int) -> Marker? {
        var index = cursor
        while index < end, units[index] == Unit.hash { index += 1 }
        let level = index - cursor
        // Seven hashes is not a seventh-level heading, and `#tag` is a word:
        // both are what every other markdown editor does, and the second is
        // what keeps a journal full of tags out of headings.
        guard (1...6).contains(level), index == end || isSpaceOrTab(units[index]) else {
            return nil
        }
        return Marker(.heading(level: level), end: skippingSpaces(units, from: index, to: end))
    }

    private static func readQuote(_ units: [UInt16], at cursor: Int, to end: Int) -> Marker? {
        guard units[cursor] == Unit.greaterThan else { return nil }
        var index = cursor
        var depth = 0
        while index < end, units[index] == Unit.greaterThan {
            depth += 1
            index = skippingSpaces(units, from: index + 1, to: end)
        }
        return Marker(.quote(depth: depth), end: index)
    }

    private static func readBulletItem(_ units: [UInt16], at cursor: Int, to end: Int) -> Marker? {
        let mark = units[cursor]
        guard mark == Unit.hyphen || mark == Unit.asterisk || mark == Unit.plus else { return nil }
        // The space is what separates a bullet from a word that starts with a
        // dash, and `*emphasis*` from a list item.
        guard cursor + 1 == end || isSpaceOrTab(units[cursor + 1]) else { return nil }

        let words = skippingSpaces(units, from: cursor + 1, to: end)
        if let task = readBox(units, at: words, to: end) {
            return task
        }
        return Marker(.bulletItem, end: words)
    }

    /// The `[ ]` or `[x]` that turns a bullet into a task item.
    ///
    /// The box has to be the first thing after the bullet and has to be
    /// followed by a space or by nothing — `- [x]y` is a bullet whose words
    /// start with a bracket, and so is `- the [x] column`. Anything but a
    /// space or an `x` between the brackets is somebody's own notation, and is
    /// left as the words it is.
    private static func readBox(_ units: [UInt16], at cursor: Int, to end: Int) -> Marker? {
        guard cursor + 2 < end, units[cursor] == Unit.leftBracket else { return nil }
        guard units[cursor + 2] == Unit.rightBracket else { return nil }
        guard cursor + 3 == end || isSpaceOrTab(units[cursor + 3]) else { return nil }

        let state = units[cursor + 1]
        let isDone = state == Unit.lowercaseX || state == Unit.uppercaseX
        guard isDone || state == Unit.space else { return nil }

        return Marker(
            .taskItem(isDone: isDone),
            end: skippingSpaces(units, from: cursor + 3, to: end),
            box: bounds(cursor, cursor + 3)
        )
    }

    private static func readNumberedItem(_ units: [UInt16], at cursor: Int, to end: Int) -> Marker? {
        var index = cursor
        while index < end, isDigit(units[index]), index - cursor < 9 { index += 1 }
        guard index > cursor, index < end else { return nil }
        guard units[index] == Unit.period || units[index] == Unit.rightParenthesis else {
            return nil
        }
        guard index + 1 == end || isSpaceOrTab(units[index + 1]) else { return nil }

        let digits = String(decoding: units[cursor..<index], as: UTF16.self)
        guard let number = Int(digits) else { return nil }
        return Marker(
            .numberedItem(number: number),
            end: skippingSpaces(units, from: index + 1, to: end)
        )
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
                // A second bracket is Obsidian's spelling of the same thing,
                // and it is tried first: `![[a]](b)` is a wiki embed of `a`
                // with a stray link after it, not a standard embed of `[a]`.
                if let embed = wikiEmbedSpan(units, at: index, to: end)
                    ?? linkSpan(units, bracket: index + 1, to: end, embedded: true)
                {
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
                    range: bounds(index, cursor + fence),
                    opening: bounds(index, index + fence),
                    content: bounds(index + fence, cursor),
                    closing: bounds(cursor, cursor + fence),
                    destination: bounds(cursor, cursor),
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
                range: bounds(openStart, closeEnd),
                opening: bounds(openStart, openEnd),
                content: bounds(openEnd, closeStart),
                closing: bounds(closeStart, closeEnd),
                destination: bounds(closeEnd, closeEnd),
                inlines: inlines(in: units, from: openEnd, to: closeStart)
            )
        }

        let strong = MarkdownInline(
            style: .strong,
            range: bounds(openStart + 1, closeStart + 2),
            opening: bounds(openStart + 1, openEnd),
            content: bounds(openEnd, closeStart),
            closing: bounds(closeStart, closeStart + 2),
            destination: bounds(closeStart + 2, closeStart + 2),
            inlines: inlines(in: units, from: openEnd, to: closeStart)
        )
        return MarkdownInline(
            style: .emphasis,
            range: bounds(openStart, closeEnd),
            opening: bounds(openStart, openStart + 1),
            content: bounds(openStart + 1, closeStart + 2),
            closing: bounds(closeStart + 2, closeEnd),
            destination: bounds(closeEnd, closeEnd),
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
            range: bounds(start, closeParenthesis + 1),
            opening: bounds(start, bracket + 1),
            content: bounds(bracket + 1, closeBracket),
            // All of `](destination)` is punctuation, and drawn as such.
            closing: bounds(closeBracket, closeParenthesis + 1),
            destination: bounds(closeBracket + 2, closeParenthesis),
            inlines: inlines(in: units, from: bracket + 1, to: closeBracket)
        )
    }

    /// `![[target]]`, and `![[target|however Obsidian was asked to size it]]`
    /// — the embed as an Obsidian vault spells it.
    ///
    /// Read wherever it appears, whatever the embed-syntax setting says: the
    /// setting decides what Aujour writes into an Entry, and a folder shared
    /// with Obsidian holds what Obsidian wrote (`v1-decisions.md`).
    ///
    /// The target is one file name and no markdown — a `*` in it is a
    /// character in a file name — so nothing inside is read as a span, and a
    /// bracket inside ends the search rather than nesting.
    private static func wikiEmbedSpan(
        _ units: [UInt16],
        at index: Int,
        to end: Int
    ) -> MarkdownInline? {
        let contentStart = index + 3
        // Both brackets, and then something that is not a third: `![a](b)` is
        // a standard embed of `a`, and `![[[a]]` is nobody's target.
        guard index + 2 < end, units[index + 2] == Unit.leftBracket else { return nil }
        guard contentStart < end, units[contentStart] != Unit.leftBracket else { return nil }

        var cursor = contentStart
        var pipe: Int?
        while cursor + 1 < end {
            switch units[cursor] {
            case Unit.rightBracket where units[cursor + 1] == Unit.rightBracket:
                guard cursor > contentStart else { return nil }
                return MarkdownInline(
                    style: .image,
                    range: bounds(index, cursor + 2),
                    opening: bounds(index, contentStart),
                    content: bounds(contentStart, cursor),
                    closing: bounds(cursor, cursor + 2),
                    // Everything after the pipe is Obsidian telling itself how
                    // wide to draw the picture. The file is what comes before.
                    destination: bounds(contentStart, pipe ?? cursor),
                    inlines: []
                )
            case Unit.leftBracket, Unit.rightBracket:
                return nil
            case Unit.verticalBar where pipe == nil:
                pipe = cursor
            default:
                break
            }
            cursor += 1
        }
        return nil
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
    static let uppercaseX: UInt16 = 0x58
    static let underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60
    static let lowercaseX: UInt16 = 0x78
    static let verticalBar: UInt16 = 0x7C
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

private func bounds(_ start: Int, _ end: Int) -> NSRange {
    NSRange(location: start, length: end - start)
}
