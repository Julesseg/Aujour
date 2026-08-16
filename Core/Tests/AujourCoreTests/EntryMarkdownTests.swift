import Foundation
import Testing

@testable import AujourCore

// What the editor paints an Entry with. The pixels are the app's, but every
// decision about *what* a stretch of text is — this line is a second-level
// heading, those three characters are its marker, that word is emphasised —
// is here, where it can be read against the text it came from.
//
// The ranges are UTF-16, because that is what a text view addresses its
// storage in; the tests read them back as the text they cover, so that a
// failure says "the marker was `##` " rather than "expected {0, 3}".

/// A read of some markdown, with the ranges resolved back into words.
private struct Read {
    let source: String
    let markdown: EntryMarkdown
    private let units: [UInt16]

    init(_ source: String) {
        self.source = source
        self.markdown = EntryMarkdown(source)
        self.units = Array(source.utf16)
    }

    var lines: [MarkdownLine] { markdown.lines }

    subscript(line: Int) -> MarkdownLine { markdown.lines[line] }

    func text(_ range: NSRange) -> String {
        String(decoding: units[range.lowerBound..<range.upperBound], as: UTF16.self)
    }

    /// Every inline span of a line, outermost first and each one's children
    /// straight after it.
    func inlines(_ line: Int) -> [MarkdownInline] {
        flatten(markdown.lines[line].inlines)
    }

    private func flatten(_ spans: [MarkdownInline]) -> [MarkdownInline] {
        spans.flatMap { [$0] + flatten($0.inlines) }
    }
}

/// The one line of a single-line source.
private func line(_ source: String) -> (read: Read, line: MarkdownLine) {
    let read = Read(source)
    return (read, read[0])
}

@Suite("Markdown blocks")
struct EntryMarkdownBlockTests {
    @Test("a heading is its level, its hashes, and the words after them")
    func headings() {
        let (read, heading) = line("## Morning")
        #expect(heading.block == .heading(level: 2))
        #expect(read.text(heading.marker) == "## ")
        #expect(read.text(heading.content) == "Morning")

        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            #expect(line("\(hashes) Title").line.block == .heading(level: level))
        }
    }

    // Obsidian and every other markdown editor agree on both of these, and a
    // journal is full of the second: a tag is not a heading.
    @Test("hashes that head nothing are ordinary words")
    func notHeadings() {
        #expect(line("#hashtag").line.block == .paragraph)
        #expect(line("####### seven").line.block == .paragraph)
        #expect(line("Not a # heading").line.block == .paragraph)
    }

    @Test("a heading with no words is still a heading")
    func emptyHeading() {
        let (read, heading) = line("###")
        #expect(heading.block == .heading(level: 3))
        #expect(read.text(heading.marker) == "###")
        #expect(read.text(heading.content) == "")
    }

    @Test("a bullet is any of markdown's three bullets, and keeps its indent")
    func bullets() {
        for bullet in ["-", "*", "+"] {
            let (read, item) = line("\(bullet) milk")
            #expect(item.block == .bulletItem)
            #expect(read.text(item.marker) == "\(bullet) ")
            #expect(read.text(item.content) == "milk")
        }

        let (read, nested) = line("    - and cream")
        #expect(nested.block == .bulletItem)
        #expect(read.text(nested.indent) == "    ")
        #expect(read.text(nested.marker) == "- ")
        #expect(read.text(nested.content) == "and cream")
    }

    @Test("a bullet needs the space after it")
    func bulletsNeedTheirSpace() {
        #expect(line("-milk").line.block == .paragraph)
        #expect(line("*emphasis* first").line.block == .paragraph)
    }

    @Test("a numbered item carries the number the user wrote")
    func numberedItems() {
        let (read, first) = line("1. Woke early")
        #expect(first.block == .numberedItem(number: 1))
        #expect(read.text(first.marker) == "1. ")
        #expect(read.text(first.content) == "Woke early")

        #expect(line("12) Twelfth").line.block == .numberedItem(number: 12))
        #expect(line("1.No space").line.block == .paragraph)
    }

    @Test("a quote is as deep as its angle brackets")
    func quotes() {
        let (read, quoted) = line("> Someone said this")
        #expect(quoted.block == .quote(depth: 1))
        #expect(read.text(quoted.marker) == "> ")
        #expect(read.text(quoted.content) == "Someone said this")

        #expect(line(">> Deeper").line.block == .quote(depth: 2))
        #expect(line("> > Deeper").line.block == .quote(depth: 2))
    }

    @Test("a bullet whose first word is a box is a task")
    func taskItems() {
        let (unticked, todo) = line("- [ ] buy milk")
        #expect(todo.block == .taskItem(isDone: false))
        #expect(unticked.text(todo.marker) == "- [ ] ")
        #expect(unticked.text(todo.box) == "[ ]")
        #expect(unticked.text(todo.content) == "buy milk")

        let (ticked, done) = line("- [x] bought milk")
        #expect(done.block == .taskItem(isDone: true))
        #expect(ticked.text(done.box) == "[x]")
        #expect(ticked.text(done.content) == "bought milk")

        // Obsidian ticks with either case, and a task written on another
        // device is still this device's task.
        #expect(line("- [X] shouted").line.block == .taskItem(isDone: true))
        // Any of the three bullets, and however deeply nested.
        #expect(line("* [ ] a").line.block == .taskItem(isDone: false))
        #expect(line("+ [x] a").line.block == .taskItem(isDone: true))
        #expect(line("    - [ ] a").line.block == .taskItem(isDone: false))
    }

    @Test("a task with nothing left to say is still a task")
    func emptyTask() {
        let (read, empty) = line("- [ ]")
        #expect(empty.block == .taskItem(isDone: false))
        #expect(read.text(empty.marker) == "- [ ]")
        #expect(read.text(empty.box) == "[ ]")
        #expect(read.text(empty.content) == "")
    }

    // A journal is full of brackets, and none of them should turn a line into
    // something the user can tick.
    @Test("brackets that are not a box leave a bullet a bullet")
    func bracketsThatAreNotBoxes() {
        for notATask in ["- [ ]x", "- [/] half", "- [] nothing", "- [xx] two", "- the [x] column"] {
            let (read, item) = line(notATask)
            #expect(item.block == .bulletItem, "expected \(notATask) to stay a plain bullet")
            #expect(read.text(item.box) == "")
        }
        // A box needs a bullet in front of it: a paragraph that opens with one
        // is a paragraph.
        #expect(line("[ ] buy milk").line.block == .paragraph)
        #expect(line("1. [ ] buy milk").line.block == .numberedItem(number: 1))
    }

    @Test("three or more of one mark across a line is a rule, not a list")
    func thematicBreaks() {
        for rule in ["---", "***", "___", "- - -", "-----"] {
            let (read, broken) = line(rule)
            #expect(broken.block == .thematicBreak, "expected \(rule) to be a rule")
            #expect(read.text(broken.marker) == rule)
            #expect(read.text(broken.content) == "")
        }
        #expect(line("--").line.block == .paragraph)
    }

    @Test("a line with nothing on it is blank, whitespace and all")
    func blankLines() {
        #expect(line("").line.block == .blank)
        let (read, spaces) = line("   ")
        #expect(spaces.block == .blank)
        #expect(read.text(spaces.indent) == "   ")
    }

    @Test("an entry is read as one line per line, blank ones included")
    func lineSplitting() {
        let read = Read("# Sunday\n\nWoke late.\n")
        #expect(read.lines.count == 4)
        #expect(read.lines.map(\.block) == [.heading(level: 1), .blank, .paragraph, .blank])
        #expect(read.text(read[2].range) == "Woke late.")
    }

    // Windows line endings and the paragraph separator arrive with pasted
    // text, and a text view breaks lines at all of them — so this model has
    // to as well, or the editor would restyle a stretch that is not a line.
    @Test("lines break wherever a text view breaks them")
    func lineBreaks() {
        #expect(Read("a\r\nb").lines.count == 2)
        #expect(Read("a\rb").lines.count == 2)
        #expect(Read("a\u{2029}b").lines.count == 2)
        #expect(Read("a\r\nb").text(Read("a\r\nb")[0].range) == "a")
    }

    // The editor paints a line by painting its parts, so a gap between them
    // would be a stretch of text with no styling at all.
    @Test("a line is exactly its indent, its marker and its content")
    func linesArePartitioned() {
        let read = Read(
            """
            # Sunday

              - milk
            - [x] bought milk
            1. first
            > quoted
            ---
            Just words, and *some* of them emphasised.
            """
        )
        for line in read.lines {
            #expect(line.indent.location == line.range.location)
            #expect(line.marker.location == line.indent.upperBound)
            #expect(line.content.location == line.marker.upperBound)
            #expect(line.content.upperBound == line.range.upperBound)
            // A box is part of the marker rather than a fourth part beside it.
            #expect(line.box.location >= line.marker.location)
            #expect(line.box.upperBound <= line.marker.upperBound)
        }
    }
}

@Suite("Markdown inline spans")
struct EntryMarkdownInlineTests {
    @Test("one star each side is emphasis, two are strong")
    func emphasisAndStrong() {
        let read = Read("A *soft* word")
        let emphasis = read.inlines(0)
        #expect(emphasis.map(\.style) == [.emphasis])
        #expect(read.text(emphasis[0].range) == "*soft*")
        #expect(read.text(emphasis[0].opening) == "*")
        #expect(read.text(emphasis[0].content) == "soft")
        #expect(read.text(emphasis[0].closing) == "*")

        let loud = Read("A **loud** word")
        #expect(loud.inlines(0).map(\.style) == [.strong])
        #expect(loud.text(loud.inlines(0)[0].content) == "loud")

        #expect(Read("_soft_").inlines(0).map(\.style) == [.emphasis])
        #expect(Read("__loud__").inlines(0).map(\.style) == [.strong])
    }

    @Test("three stars are emphasis around strong")
    func strongEmphasis() {
        let read = Read("***both***")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.emphasis, .strong])
        #expect(read.text(spans[0].range) == "***both***")
        #expect(read.text(spans[1].range) == "**both**")
        #expect(read.text(spans[1].content) == "both")
    }

    @Test("emphasis inside strong is found inside it")
    func nestedEmphasis() {
        let read = Read("**loud with _a soft bit_ in it**")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.strong, .emphasis])
        #expect(read.text(spans[1].range) == "_a soft bit_")
    }

    // The one rule that matters in a journal full of file names and code.
    @Test("underscores inside a word are part of the word")
    func underscoresDoNotSplitWords() {
        #expect(Read("snake_case_name").inlines(0).isEmpty)
        #expect(Read("a_b_c").inlines(0).isEmpty)
    }

    @Test("a mark with nothing after it emphasises nothing")
    func danglingMarks() {
        #expect(Read("2 * 3 * 4").inlines(0).isEmpty)
        #expect(Read("An unmatched * star").inlines(0).isEmpty)
        #expect(Read("*").inlines(0).isEmpty)
    }

    @Test("a mark the user escaped is a mark, not a delimiter")
    func escapedMarks() {
        #expect(Read(#"\*not emphasis\*"#).inlines(0).isEmpty)
    }

    @Test("backticks are code, and nothing inside them is anything else")
    func codeSpans() {
        let read = Read("Run `swift test *now*` again")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.code])
        #expect(read.text(spans[0].content) == "swift test *now*")
        #expect(read.text(spans[0].opening) == "`")
    }

    @Test("emphasis does not close inside a code span")
    func codeSpansShieldTheirContents() {
        let read = Read("*soft `a*b` still soft*")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.emphasis, .code])
        #expect(read.text(spans[0].range) == "*soft `a*b` still soft*")
    }

    @Test("two tildes are a strikethrough, one is a tilde")
    func strikethrough() {
        let read = Read("~~gone~~ and ~kept~")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.strikethrough])
        #expect(read.text(spans[0].content) == "gone")
    }

    @Test("a link is its words, its destination, and the punctuation between")
    func links() {
        let read = Read("Walked to [the market](https://example.com) again")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.link])
        #expect(read.text(spans[0].range) == "[the market](https://example.com)")
        #expect(read.text(spans[0].content) == "the market")
        #expect(read.text(spans[0].closing) == "](https://example.com)")
    }

    @Test("an embed is a link with a bang in front of it")
    func embeds() {
        let read = Read("![the market](attachments/2026/03/market.jpg)")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.image])
        #expect(read.text(spans[0].opening) == "![")
        #expect(read.text(spans[0].closing) == "](attachments/2026/03/market.jpg)")
        #expect(read.text(spans[0].destination) == "attachments/2026/03/market.jpg")
    }

    // Both spellings are read wherever they are written: the embed-syntax
    // setting decides what Aujour writes, and a folder shared with Obsidian
    // holds whatever Obsidian wrote.
    @Test("an embed written Obsidian's way is the same embed")
    func wikiEmbeds() {
        let read = Read("![[market.jpg]] and then home.")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.image])
        #expect(read.text(spans[0].range) == "![[market.jpg]]")
        #expect(read.text(spans[0].opening) == "![[")
        #expect(read.text(spans[0].content) == "market.jpg")
        #expect(read.text(spans[0].closing) == "]]")
        #expect(read.text(spans[0].destination) == "market.jpg")
    }

    // Obsidian's way of saying how wide to draw it. The file is what comes
    // before the pipe, and the rest is somebody else's instruction.
    @Test("a wiki embed's size hint is not part of the file it names")
    func wikiEmbedSizeHints() {
        let read = Read("![[attachments/market.jpg|300]]")
        let spans = read.inlines(0)
        #expect(read.text(spans[0].content) == "attachments/market.jpg|300")
        #expect(read.text(spans[0].destination) == "attachments/market.jpg")
    }

    @Test("brackets that never close are not an embed")
    func wikiEmbedsThatAreNot() {
        #expect(Read("![[unfinished").inlines(0).isEmpty)
        #expect(Read("![[]] nothing").inlines(0).isEmpty)
        // A wiki *link* is not an embed, and v1 draws nothing over it.
        #expect(Read("[[a note]]").inlines(0).isEmpty)
    }

    @Test("a span that points nowhere says so with an empty destination")
    func destinationsOfEverythingElse() {
        for source in ["A *soft* word", "A **loud** word", "Run `swift test`", "A ~~struck~~ one"] {
            let spans = Read(source).inlines(0)
            #expect(spans.allSatisfy { $0.destination.length == 0 }, "\(source) pointed somewhere")
        }
        let link = Read("Went to [the market](https://example.com)")
        #expect(link.text(link.inlines(0)[0].destination) == "https://example.com")
    }

    @Test("brackets that lead nowhere are brackets")
    func bracketsThatAreNotLinks() {
        #expect(Read("[just a note]").inlines(0).isEmpty)
        #expect(Read("[a] [b]").inlines(0).isEmpty)
    }

    @Test("a marker's words are styled like any others")
    func inlinesInsideBlocks() {
        let heading = Read("# A *soft* heading")
        #expect(heading.inlines(0).map(\.style) == [.emphasis])

        let item = Read("- milk, **two** bottles")
        #expect(item.inlines(0).map(\.style) == [.strong])

        // And the marker itself is never mistaken for one: the `-` that makes
        // this a list item cannot also open emphasis.
        #expect(item.text(item[0].marker) == "- ")
    }

    @Test("spans never reach past the end of their line")
    func spansStayOnTheirLine() {
        let read = Read("*not emphasis\nbecause it never closes*")
        #expect(read.inlines(0).isEmpty)
        #expect(read.inlines(1).isEmpty)
    }
}

// The whole reason blocks are one line and spans never cross one: the editor
// re-reads the lines a keystroke touched and nothing else, which is only
// correct if a line's shape is a fact about that line. These are the tests
// that licence it.
@Suite("Reading around an edit")
struct EntryMarkdownLocalityTests {
    private let entry = """
        # Sunday 1 March

        Woke late, and *stayed* late.

        ## What happened
        - walked to [the market](https://example.com)
        - came back the **long** way

        > Someone said something worth keeping.

        ---
        `swift test`, and then bed.
        """

    @Test("a whole entry is covered end to end")
    func theWholeEntry() {
        let whole = EntryMarkdown(entry)
        #expect(whole.range == NSRange(location: 0, length: entry.utf16.count))
        #expect(whole.lines.first?.range.location == 0)
        #expect(whole.lines.last?.range.upperBound == entry.utf16.count)
    }

    // The claim in full: every edit anywhere reads back exactly the lines the
    // whole entry has there, so re-reading a stretch can never disagree with
    // re-reading everything.
    @Test("the lines around an edit are the lines the entry has there")
    func readingAroundAnEdit() {
        let whole = EntryMarkdown(entry)

        for location in 0...entry.utf16.count {
            for length in [0, 1, 5] where location + length <= entry.utf16.count {
                let edit = NSRange(location: location, length: length)
                let read = EntryMarkdown(entry, around: edit)

                // By paragraph rather than by line: a stretch ending at a
                // break holds the line above it and not the one below, whose
                // own break is past the end of what was read.
                let expected = whole.lines.filter {
                    $0.paragraph.location >= read.range.location
                        && $0.paragraph.upperBound <= read.range.upperBound
                }
                #expect(read.lines == expected, "reading around \(edit) disagreed with the entry")
                #expect(!read.lines.isEmpty, "reading around \(edit) found no line at all")
            }
        }
    }

    @Test("an edit reaches back to the start of its line and on to the end of it")
    func anEditReadsWholeLines() {
        let read = EntryMarkdown("# Sunday\nWoke late.\n", around: NSRange(location: 4, length: 0))
        #expect(read.range == NSRange(location: 0, length: 9))
        #expect(read.lines.map(\.block) == [.heading(level: 1)])
    }

    // A return typed into the middle of a line: the half below the break is
    // the half that stops being a heading, and the edit never touched it.
    @Test("an edit that ends on a line break reads the line after it too")
    func aBreakReadsTheLineBelowIt() {
        let split = "# Sunday\n and more"
        let read = EntryMarkdown(split, around: NSRange(location: 8, length: 1))

        #expect(read.range == NSRange(location: 0, length: split.utf16.count))
        #expect(read.lines.map(\.block) == [.heading(level: 1), .paragraph])
    }

    @Test("a line's paragraph is the line and the break that ended it")
    func paragraphsIncludeTheirBreak() {
        let read = Read("# Sunday\r\nWoke late.\n")
        #expect(read[0].range == NSRange(location: 0, length: 8))
        #expect(read[0].paragraph == NSRange(location: 0, length: 10))
        #expect(read[1].paragraph == NSRange(location: 10, length: 11))
        // Nothing left over: the paragraphs tile the entry exactly.
        #expect(read[2].paragraph == NSRange(location: 21, length: 0))
    }
}
