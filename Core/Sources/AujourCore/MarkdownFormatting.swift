import Foundation

/// A formatting control, said as the edit it makes: bold, a heading, a list, a
/// step further in.
///
/// The whole of what the accessory row above the keyboard *is*. A control is a
/// shortcut for markdown the user could have typed by hand — `**` around a
/// word, `- [ ] ` in front of a line — so every one of them comes out as a
/// rewrite of the characters that are already there, and the Entry is a plain
/// markdown file before and after (ADR 0001). Nothing here knows what a button
/// looks like, and nothing above it knows what bold is spelled.
///
/// ## Where the cursor goes
///
/// Half of what a control does. Bold with a word selected leaves that word
/// selected; bold with a caret in a word leaves the caret in it, a couple of
/// characters along from where it was. A control that moved the caret to the
/// end of the line would be one nobody could use twice in a sentence, so every
/// edit says where to leave it (``MarkdownEdit/selection``).
///
/// ## What a control does when it is already done
///
/// It undoes itself. Bold inside a bold word takes the marks away, a bullet on
/// a list of bullets takes the markers away — the same button, and the way back
/// from a mistake is the button that made it. Three exceptions earn themselves:
/// a heading at another level is re-levelled rather than removed, because
/// nobody presses *Heading 2* meaning "not a heading"; bold at the *end* of a
/// bold word steps the caret out over the closing marks, because that is
/// somebody who has finished writing the bold word rather than somebody who
/// wishes they had not; and the checkbox goes round three states rather than
/// two — a task, a task that is done, and neither — because ticking a box is
/// otherwise something only a finger on the glass can do (``taskList``).
public enum MarkdownFormatting: Equatable, Sendable {
    /// `**two stars**`.
    case strong

    /// `*one star*`.
    case emphasis

    /// `#` to `######`, on every line the selection touches.
    case heading(level: Int)

    /// `- `, on every line the selection touches.
    case bulletList

    /// `1. `, counting down the lines the selection touches.
    case numberedList

    /// `- [ ] `, on every line the selection touches — and then the tick, and
    /// then neither.
    ///
    /// The one control that goes round three states. A box is drawn over
    /// characters rather than being a view, so a finger on the glass is the
    /// only thing that can tick one on the page; this is how a Task is made,
    /// ticked and unmade by somebody who is working by VoiceOver, by Switch
    /// Control, or by a keyboard.
    case taskList

    /// One level further in, on every line the selection touches.
    case indent

    /// One level back out.
    case outdent

    /// The edit this control makes to `source` with the cursor at `selection`,
    /// or `nil` when there is nothing for it to do — an outdent on a line
    /// against the margin, a bold that is already closed at the caret.
    ///
    /// The whole Entry is read rather than the lines around the cursor, unlike
    /// the reading a keystroke pays for (``EntryMarkdown/init(_:around:)``).
    /// A control is a tap rather than a letter — a few of them in a sentence,
    /// not one per character — and two of the answers here are about text the
    /// cursor is not in: which number a list carries on from, and how far a
    /// selection reaches.
    public func edit(_ source: String, over selection: NSRange) -> MarkdownEdit? {
        let text = source as NSString
        let cursor = selection.brought(inside: text.length)
        let reading = EntryMarkdown(source)

        switch self {
        case .strong, .emphasis:
            return wrapping(text, in: reading, over: cursor)
        case .heading, .bulletList, .numberedList, .taskList, .indent, .outdent:
            return rewritingLines(text, in: reading, over: cursor)
        }
    }
}

// MARK: - Bold and italic

extension MarkdownFormatting {
    /// The span this control writes and the marks it is spelled with, for the
    /// two controls that wrap words rather than opening a line.
    ///
    /// The two together, because they are one fact said twice: what is read
    /// back out of the Entry (``AujourCore/MarkdownInline/Style``) is what the
    /// control put in, and a control whose marks and style could disagree
    /// would wrap a word it then could not unwrap.
    private var wraps: (style: MarkdownInline.Style, mark: String)? {
        switch self {
        case .strong: return (.strong, "**")
        case .emphasis: return (.emphasis, "*")
        case .heading, .bulletList, .numberedList, .taskList, .indent, .outdent: return nil
        }
    }

    /// Wraps what the cursor is on in this control's marks, or takes the marks
    /// away when it is already inside a pair of them.
    ///
    /// One line at a time, because a span is: `EntryMarkdown` reads emphasis
    /// within a line and never past its ends, so marks either side of a line
    /// break would be marks around nothing. A selection that runs over several
    /// lines is wrapped as far as the first of them goes.
    private func wrapping(
        _ text: NSString,
        in reading: EntryMarkdown,
        over cursor: NSRange
    ) -> MarkdownEdit? {
        guard let wraps, let line = reading.line(holding: cursor.location) else { return nil }
        let within = cursor.brought(inside: line.range)

        if let span = MarkdownFormatting.span(of: wraps.style, in: line.inlines, around: within) {
            return leaving(span, at: within, in: text)
        }

        let words = wordsToWrap(text, at: within, in: line)
        let mark = wraps.mark
        return MarkdownEdit(
            range: words,
            replacement: mark + text.substring(with: words) + mark,
            // The words stay the words that are selected; a caret stays where
            // in them it was, now that there are two more characters in front
            // of it.
            selection: NSRange(
                location: (within.length > 0 ? words.location : within.location) + mark.count,
                length: within.length > 0 ? words.length : 0
            )
        )
    }

    /// What to do about a cursor that is already inside a pair of these marks:
    /// step out over the closing ones, or take both away.
    ///
    /// Which is not symmetrical, deliberately. A caret at the closing end has
    /// somebody behind it who has just written the word; one at the opening
    /// end has somebody who has written nothing, and taking the marks away is
    /// the only thing they could mean. Past the closing marks there is
    /// nothing to do at all and this says so — a second pair of marks against
    /// the first would spell `****`, which is not bold anywhere and is not
    /// what anybody asked for either.
    private func leaving(
        _ span: MarkdownInline,
        at cursor: NSRange,
        in text: NSString
    ) -> MarkdownEdit? {
        // A caret at the closing end is somebody who has finished writing the
        // bold word — pressing bold there means "and the rest is not bold",
        // which is a caret past the marks and not a word stripped of them.
        if cursor.length == 0, cursor.location >= span.content.upperBound {
            let out = NSRange(location: span.range.upperBound, length: 0)
            guard cursor.location < out.location else { return nil }
            return MarkdownEdit(range: out, replacement: "", selection: out)
        }

        // The words, without the marks either side of them — and with whatever
        // was selected of those words still selected.
        let kept =
            cursor.overlap(with: span.content)
            ?? NSRange(location: span.content.location, length: 0)
        return MarkdownEdit(
            range: span.range,
            replacement: text.substring(with: span.content),
            selection: NSRange(
                location: span.range.location + (kept.location - span.content.location),
                length: kept.length
            )
        )
    }

    /// The characters a control wraps: what is selected, or the word the caret
    /// is standing in.
    ///
    /// A selection's own edges are trimmed of spaces, because a closing mark
    /// with a space in front of it closes nothing — `**the market **` is bold
    /// in no renderer, and the spaces are the user's text either way.
    private func wordsToWrap(_ text: NSString, at cursor: NSRange, in line: MarkdownLine)
        -> NSRange
    {
        guard cursor.length == 0 else {
            var start = cursor.location
            var end = cursor.upperBound
            while start < end, isSpaceOrTab(text.character(at: start)) { start += 1 }
            while end > start, isSpaceOrTab(text.character(at: end - 1)) { end -= 1 }
            return NSRange(location: start, length: end - start)
        }

        // The word the caret is in, either end of it counting as in: a caret
        // against the last letter is somebody who has just typed the word they
        // mean.
        var start = cursor.location
        var end = cursor.location
        while start > line.range.location, isWordUnit(text.character(at: start - 1)) { start -= 1 }
        while end < line.range.upperBound, isWordUnit(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// The innermost span of `style` the cursor is inside, if it is inside one.
    ///
    /// Innermost, so that bold inside `***both***` is the bold rather than the
    /// italic around it — the button acts on the thing it is about, and the
    /// other one is still there afterwards.
    private static func span(
        of style: MarkdownInline.Style,
        in inlines: [MarkdownInline],
        around cursor: NSRange
    ) -> MarkdownInline? {
        for inline in inlines {
            guard inline.range.holds(cursor) else { continue }
            if let inner = span(of: style, in: inline.inlines, around: cursor) { return inner }
            if inline.style == style { return inline }
        }
        return nil
    }
}

// MARK: - Headings, lists and indenting

extension MarkdownFormatting {
    /// Rewrites every line the selection touches, and says where that leaves
    /// the cursor.
    private func rewritingLines(
        _ text: NSString,
        in reading: EntryMarkdown,
        over cursor: NSRange
    ) -> MarkdownEdit? {
        let selected = reading.lines(touchedBy: cursor)
        guard let first = selected.first, let last = selected.last else { return nil }

        // A blank line has nothing to be a list item, and a `- ` on its own is
        // an empty bullet somebody has to delete again. So the blank lines
        // between paragraphs — where most multi-line selections stop — are
        // passed over, and they do not get a say in whether the rest of the
        // selection is already what this control would make it.
        let written = selected.filter { $0.block != .blank }
        guard !written.isEmpty else { return nil }

        let marking = marking(of: written)
        let step = stepIn(under: reading.lines.last { $0.range.upperBound < first.range.location })
        var lines: [RewrittenLine] = []
        var number = firstNumber(before: first, in: reading)
        var lineStart = first.range.location

        for line in selected {
            let rewritten = rewrite(
                line, in: text, marking: marking, number: number, step: step, at: lineStart
            )
            if line.block != .blank, case .numberedList = self { number += 1 }
            lineStart = rewritten.rewritten.upperBound + breakLength(of: line)
            lines.append(rewritten)
        }

        let stretch = NSRange(
            location: first.range.location,
            length: last.range.upperBound - first.range.location
        )
        // Joined back together on the line breaks they were written with, so
        // that a vault holding `\r\n` goes on holding it.
        let replacement = lines.dropLast()
            .map { $0.text + breakText(after: $0.line, in: text) }
            .joined() + (lines.last?.text ?? "")
        guard replacement != text.substring(with: stretch) else { return nil }

        let start = MarkdownFormatting.moved(cursor.location, through: lines)
        let end = MarkdownFormatting.moved(cursor.upperBound, through: lines)
        return MarkdownEdit(
            range: stretch,
            replacement: replacement,
            selection: NSRange(location: start, length: end - start)
        )
    }

    /// One line as this control leaves it: the words it keeps, and what now
    /// comes before them.
    ///
    /// The words are never touched — every control here rewrites punctuation —
    /// which is what lets the cursor be put back among them exactly.
    private struct RewrittenLine {
        let line: MarkdownLine

        /// The characters kept, in the source's own offsets: a line's words,
        /// or — for indenting, which leaves the marker where it is — its
        /// marker and words together.
        let words: NSRange

        /// What goes in front of them now.
        let prefix: String

        /// Where the line has ended up in the rewritten text.
        let rewritten: NSRange

        let text: String
    }

    private func rewrite(
        _ line: MarkdownLine,
        in text: NSString,
        marking: Marking,
        number: Int,
        step: String,
        at start: Int
    ) -> RewrittenLine {
        let (words, prefix) = rewriting(
            line, in: text, marking: marking, number: number, step: step
        )
        let rewritten = prefix + text.substring(with: words)
        return RewrittenLine(
            line: line,
            words: words,
            prefix: prefix,
            rewritten: NSRange(location: start, length: (rewritten as NSString).length),
            text: rewritten
        )
    }

    /// How this control rewrites one line: the characters of it that are kept,
    /// and what now goes in front of them.
    ///
    /// The two answered together because they are one decision — a control
    /// that took a line's marker away in one of them and left the words after
    /// it in the other would write a line that is neither.
    private func rewriting(
        _ line: MarkdownLine,
        in text: NSString,
        marking: Marking,
        number: Int,
        step: String
    ) -> (words: NSRange, prefix: String) {
        // A blank line is kept whole and left as it is: see above.
        guard line.block != .blank else { return (line.range, "") }
        let indent = text.substring(with: line.indent)

        switch self {
        case .indent:
            // The marker goes in with the words: a bullet a step further in is
            // still a bullet. Spelled with a tab where the line is already
            // indented with them, because a vault written in Obsidian is, and
            // one line of spaces among them lines up with nothing.
            return (line.markerAndWords, (indent.contains("\t") ? "\t" : step) + indent)
        case .outdent:
            return (line.markerAndWords, String(steppedBack(indent, by: step)))
        case .strong, .emphasis, .heading, .bulletList, .numberedList, .taskList:
            // A rule is nothing *but* its own characters — there are no words
            // behind `---` for a marker to introduce — so its dashes are kept
            // rather than thrown away.
            //
            // The two that wrap words never reach a line, and a marker they
            // did not ask for is the empty one.
            let words = line.block == .thematicBreak ? line.markerAndWords : line.content
            return (words, indent + (marker(number, marking) ?? ""))
        }
    }

    /// One level of indentation taken off the front — a tab, or as many of the
    /// spaces one is written as there are to take.
    private func steppedBack(_ indent: String, by step: String) -> Substring {
        if indent.hasPrefix("\t") { return indent.dropFirst() }
        var stepped = Substring(indent)
        for _ in 0..<step.count where stepped.hasPrefix(" ") { stepped = stepped.dropFirst() }
        return stepped
    }

    /// One step in, as spaces: the width of the marker on the line above, so
    /// that a line stepped in under `1. ` starts where that item's words do and
    /// is read as nested rather than as the next item along. Two spaces where
    /// there is no list above to nest under, which is what `- ` measures.
    ///
    /// A task's box is not part of the step — `- [ ] milk` is a bullet whose
    /// words happen to begin with a box, and its words start two characters
    /// in like any other bullet's.
    private func stepIn(under previous: MarkdownLine?) -> String {
        let width =
            switch previous?.block {
            case .taskItem:
                previous.map { $0.box.location - $0.indent.upperBound } ?? 2
            case .bulletItem, .numberedItem:
                previous?.marker.length ?? 2
            default:
                2
            }
        return String(repeating: " ", count: max(2, width))
    }

    /// The marker this control puts in front of a line, or `nil` where it is
    /// taking one away or does not deal in markers at all.
    private func marker(_ number: Int, _ marking: Marking) -> String? {
        guard marking != .take else { return nil }
        switch self {
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .bulletList: return "- "
        case .numberedList: return "\(number). "
        case .taskList: return marking == .tick ? "- [x] " : "- [ ] "
        case .strong, .emphasis, .indent, .outdent: return nil
        }
    }

    /// What a control does to the lines it is aimed at, which depends on what
    /// they already are.
    private enum Marking {
        /// Put this control's marker in front of them.
        case put

        /// Tick the boxes: every line is a task, and none of them is done.
        case tick

        /// Take the marker away — every line already has what this control
        /// would give it, which is what makes the control its own way back.
        case take
    }

    /// Which of the three a selection is in for.
    ///
    /// The checkbox has three states rather than two, and it is the one
    /// control that has to: a box is painted glyphs rather than a view, so a
    /// finger is the only thing that can tick one on the page. Cycling here —
    /// a task, then a task that is done, then neither — is what makes a Task
    /// reachable to somebody working by VoiceOver or Switch Control, and it
    /// leaves every state one or two presses away.
    private func marking(of lines: [MarkdownLine]) -> Marking {
        switch self {
        case .taskList:
            if lines.allSatisfy({ $0.block == .taskItem(isDone: false) }) { return .tick }
            if lines.allSatisfy({ $0.block == .taskItem(isDone: true) }) { return .take }
            return .put
        case .heading(let level):
            return lines.allSatisfy { $0.block == .heading(level: level) } ? .take : .put
        case .bulletList:
            return lines.allSatisfy { $0.block == .bulletItem } ? .take : .put
        case .numberedList:
            return lines.allSatisfy { $0.block.isNumbered } ? .take : .put
        // Indenting is the one control with no state to be in: a line that has
        // been stepped in can be stepped in again.
        case .strong, .emphasis, .indent, .outdent:
            return .put
        }
    }

    /// The number a new list carries on from: the one on the line above it,
    /// plus one. The numbers are what the user reads — this editor draws an
    /// Entry's own characters — so a list written under `3.` starts at 4.
    private func firstNumber(before first: MarkdownLine, in reading: EntryMarkdown) -> Int {
        guard case .numberedList = self else { return 1 }
        let above = reading.lines.last { $0.range.upperBound < first.range.location }
        guard case .numberedItem(let number) = above?.block else { return 1 }
        return number + 1
    }

    private func breakLength(of line: MarkdownLine) -> Int {
        line.paragraph.upperBound - line.range.upperBound
    }

    private func breakText(after line: MarkdownLine, in text: NSString) -> String {
        text.substring(
            with: NSRange(location: line.range.upperBound, length: breakLength(of: line))
        )
    }

    /// Where a position in the Entry has ended up once these lines have been
    /// rewritten.
    ///
    /// The words of a line are the same characters in the same order before and
    /// after, so a cursor among them is put back among them exactly — which is
    /// what makes a control usable in the middle of a sentence. A cursor that
    /// was in the punctuation instead — inside the `- ` of a bullet being
    /// turned into a heading — lands at the same place in the new punctuation,
    /// or against the words when there is less of it than there was.
    private static func moved(_ position: Int, through lines: [RewrittenLine]) -> Int {
        guard let first = lines.first, let last = lines.last else { return position }
        // Before what was rewritten it has not moved; after it, it has moved by
        // everything these lines gained or lost between them.
        guard position >= first.line.range.location else { return position }
        guard position <= last.line.range.upperBound else {
            return position + (last.rewritten.upperBound - last.line.range.upperBound)
        }
        guard let line = lines.first(where: { position <= $0.line.range.upperBound }) else {
            return position
        }

        let offset = position - line.line.range.location
        let prefix = line.words.location - line.line.range.location
        let newPrefix = (line.prefix as NSString).length
        if offset >= prefix {
            return line.rewritten.location + newPrefix + (offset - prefix)
        }
        return line.rewritten.location + min(offset, newPrefix)
    }
}

// MARK: - Finding the lines a cursor is on

extension MarkdownBlock {
    /// Whether this line is numbered, whatever number it carries.
    fileprivate var isNumbered: Bool {
        if case .numberedItem = self { return true }
        return false
    }
}

extension MarkdownLine {
    /// Everything on the line but the whitespace it starts with — what a
    /// control keeps when it is rewriting that whitespace rather than the
    /// marker behind it.
    fileprivate var markerAndWords: NSRange {
        NSRange(location: indent.upperBound, length: range.upperBound - indent.upperBound)
    }
}

extension EntryMarkdown {
    /// Every line a cursor reaches — the one a caret is on, or all of those a
    /// selection covers.
    ///
    /// A selection that ends exactly where a line begins does not reach that
    /// line: dragging down to the start of the next paragraph is a selection of
    /// the one above it, and formatting a line the user cannot see selected
    /// would be a control reaching further than the highlight it was aimed at.
    func lines(touchedBy cursor: NSRange) -> [MarkdownLine] {
        guard cursor.length > 0 else {
            return line(holding: cursor.location).map { [$0] } ?? []
        }
        return lines.filter {
            $0.paragraph.location < cursor.upperBound && $0.paragraph.upperBound > cursor.location
        }
    }
}

// MARK: - Ranges

extension NSRange {
    /// This range brought inside a length — a selection the editor is holding
    /// over text that has since become shorter.
    fileprivate func brought(inside length: Int) -> NSRange {
        let start = min(max(location, 0), length)
        return NSRange(location: start, length: min(max(self.length, 0), length - start))
    }

    /// This range brought inside another one — a selection that runs over
    /// several lines, seen from the line it starts in.
    fileprivate func brought(inside other: NSRange) -> NSRange {
        let start = min(max(location, other.location), other.upperBound)
        return NSRange(
            location: start,
            length: min(max(length, 0), other.upperBound - start)
        )
    }

    /// Whether this range holds all of another, its own ends counting as
    /// inside: a caret against a closing mark is a caret in that emphasis.
    fileprivate func holds(_ other: NSRange) -> Bool {
        location <= other.location && other.upperBound <= upperBound
    }

    /// What this range and another have in common, or `nil` for ranges that do
    /// not meet.
    fileprivate func overlap(with other: NSRange) -> NSRange? {
        let start = max(location, other.location)
        let end = min(upperBound, other.upperBound)
        guard start <= end else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
