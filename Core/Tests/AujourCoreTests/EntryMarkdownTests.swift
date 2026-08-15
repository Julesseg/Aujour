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
        #expect(read.text(spans[0].destination ?? NSRange()) == "https://example.com")
        #expect(read.text(spans[0].closing) == "](https://example.com)")
    }

    @Test("an embed is a link with a bang in front of it")
    func embeds() {
        let read = Read("![the market](attachments/2026/03/market.jpg)")
        let spans = read.inlines(0)
        #expect(spans.map(\.style) == [.image])
        #expect(read.text(spans[0].opening) == "![")
        #expect(read.text(spans[0].destination ?? NSRange()) == "attachments/2026/03/market.jpg")
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
// restyles the lines a keystroke touched and nothing else, which is only
// correct if a line's styling is a fact about that line.
@Suite("Styling is a fact about one line")
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

    @Test("a stretch of lines reads the same alone as it does in the entry")
    func readingAStretchOfLines() {
        let whole = EntryMarkdown(entry)
        let units = Array(entry.utf16)

        for first in whole.lines.indices {
            for last in first..<whole.lines.count {
                let from = whole.lines[first].range.location
                let to = whole.lines[last].range.upperBound
                let stretch = String(decoding: units[from..<to], as: UTF16.self)

                #expect(
                    EntryMarkdown(stretch).shifted(by: from).lines
                        == Array(whole.lines[first...last]),
                    "lines \(first)…\(last) read differently on their own"
                )
            }
        }
    }

    @Test("shifting moves every range by the same amount")
    func shifting() {
        let read = Read("- milk, **two** bottles")
        let shifted = read.markdown.shifted(by: 100)

        #expect(shifted.lines[0].range == NSRange(location: 100, length: read[0].range.length))
        #expect(shifted.lines[0].marker.location == read[0].marker.location + 100)
        #expect(
            shifted.lines[0].inlines[0].range.location
                == read[0].inlines[0].range.location + 100
        )
        #expect(shifted.shifted(by: -100) == read.markdown)
    }
}
