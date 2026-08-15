import Foundation
import Testing

@testable import AujourCore

// Which of an Entry's characters the editor draws, and which it leaves out
// while the cursor is elsewhere. The pixels are the app's — a mark that is not
// drawn is a glyph the layout was told to skip — but *which* marks those are
// is a fact about the markdown and where the cursor is in it, so it is decided
// here and read back against the text it came from.
//
// The tests resolve every range into the characters it covers, so a failure
// says "the stars were still drawn" rather than "expected [{2, 1}, {7, 1}]".

/// A reading of some markdown with a cursor somewhere in it.
private struct Cursored {
    let source: String
    let hidden: HiddenSyntax
    private let units: [UInt16]

    init(_ source: String, cursor: NSRange) {
        self.source = source
        self.units = Array(source.utf16)
        self.hidden = HiddenSyntax(EntryMarkdown(source), cursor: cursor)
    }

    init(_ source: String, caret: Int) {
        self.init(source, cursor: NSRange(location: caret, length: 0))
    }

    /// The stretches that are not drawn, as the characters they cover.
    var marks: [String] {
        hidden.ranges.map { String(decoding: units[$0.lowerBound..<$0.upperBound], as: UTF16.self) }
    }

    /// What is left on screen: the Entry with the hidden stretches taken out.
    /// Never written anywhere — this is what the reader sees, and the file
    /// still says ``source``.
    var drawn: String {
        var undrawn = IndexSet()
        for range in hidden.ranges {
            undrawn.insert(integersIn: range.lowerBound..<range.upperBound)
        }
        let kept = units.indices.filter { !undrawn.contains($0) }.map { units[$0] }
        return String(decoding: kept, as: UTF16.self)
    }
}

@Suite("Syntax that hides where the cursor is not")
struct HiddenSyntaxTests {
    // The whole point, in one test: a day reads as a document, and the
    // markdown is still every character of it.
    @Test("an entry away from the cursor is drawn as what it means")
    func aDayReadsAsADocument() {
        let entry = Cursored(
            """
            # Sunday

            Walked to the *market*, and it was **shut**.
            """,
            caret: 0
        )
        // The caret is on the heading's line, so the heading shows its hashes
        // and nothing else shows anything.
        #expect(
            entry.drawn == """
                # Sunday

                Walked to the market, and it was shut.
                """
        )
    }

    @Test("a heading's hashes are not drawn while the cursor is on another line")
    func headingMarkers() {
        let away = Cursored("# Sunday\n\nWoke late.", caret: 12)
        #expect(away.marks == ["# "])
        #expect(away.drawn == "Sunday\n\nWoke late.")

        let onIt = Cursored("# Sunday\n\nWoke late.", caret: 3)
        #expect(onIt.marks.isEmpty)
    }

    // Both ends of the line, because both are places a cursor stands while
    // editing the heading — before the hashes to change the level, after the
    // last word to go on writing it.
    @Test("a cursor at either end of a heading reveals it")
    func headingEnds() {
        for caret in [0, 8] {
            #expect(Cursored("# Sunday\nWoke late.", caret: caret).marks.isEmpty)
        }
        // One past the break is the line below, and no longer the heading.
        #expect(Cursored("# Sunday\nWoke late.", caret: 9).marks == ["# "])
    }

    @Test("emphasis marks are not drawn while the cursor is outside the words they mark")
    func emphasisMarks() {
        let away = Cursored("A *soft* word", caret: 13)
        #expect(away.marks == ["*", "*"])
        #expect(away.drawn == "A soft word")

        #expect(Cursored("A *soft* word", caret: 5).marks.isEmpty)
        // Touching counts: the caret that just typed the closing star is
        // sitting after it.
        #expect(Cursored("A *soft* word", caret: 8).marks.isEmpty)
        #expect(Cursored("A *soft* word", caret: 2).marks.isEmpty)
        #expect(Cursored("A *soft* word", caret: 9).marks == ["*", "*"])
    }

    @Test("bold, struck-through and code marks hide the same way")
    func theOtherInlineMarks() {
        #expect(Cursored("A **loud** word", caret: 15).drawn == "A loud word")
        #expect(Cursored("A ~~struck~~ word", caret: 17).drawn == "A struck word")
        #expect(Cursored("Run `swift test`", caret: 0).drawn == "Run swift test")
    }

    // The one place hiding earns its keep most: a link is three characters of
    // words and forty of address.
    @Test("a link is drawn as its words, and its address comes back at the cursor")
    func links() {
        let away = Cursored("Went to [the market](https://example.com/a/b)", caret: 0)
        #expect(away.drawn == "Went to the market")

        let inIt = Cursored("Went to [the market](https://example.com/a/b)", caret: 12)
        #expect(inIt.marks.isEmpty)
    }

    // Each element answers for itself: standing in the heading does not reveal
    // the emphasis further along it, and standing in the emphasis does not
    // hide the heading's hashes.
    @Test("the cursor reveals the element it is in and not the line it is on")
    func oneElementAtATime() {
        let source = "# A *soft* heading"

        let atTheStart = Cursored(source, caret: 1)
        #expect(atTheStart.marks == ["*", "*"])
        #expect(atTheStart.drawn == "# A soft heading")

        let inTheEmphasis = Cursored(source, caret: 6)
        #expect(inTheEmphasis.marks.isEmpty)

        let onAnotherLine = Cursored("# A *soft* heading\nWoke late.", caret: 22)
        #expect(onAnotherLine.marks == ["# ", "*", "*"])
    }

    @Test("emphasis inside strong hides with its own marks, in the order they are written")
    func nestedMarks() {
        let away = Cursored("***both***, then", caret: 16)
        #expect(away.marks == ["*", "**", "**", "*"])
        #expect(away.drawn == "both, then")

        // Inside the innermost span is inside the outer one too, so all four
        // come back together.
        #expect(Cursored("***both***, then", caret: 5).marks.isEmpty)
    }

    // What is about to be deleted is shown before it goes: a selection over a
    // word takes the marks around it with it, and the user can see them.
    @Test("a selection reveals every element it covers")
    func selections() {
        let source = "# Sunday\n\n*Soft* and **loud**."
        let whole = NSRange(location: 0, length: (source as NSString).length)
        let all = Cursored(source, cursor: whole)
        #expect(all.marks.isEmpty)

        let justTheSoftWord = Cursored(source, cursor: NSRange(location: 10, length: 6))
        #expect(justTheSoftWord.marks == ["# ", "**", "**"])
    }

    // A bullet hidden is a list item drawn as a paragraph, and a rule hidden
    // is nothing at all: these marks are not a spelling of something else on
    // screen, they *are* what is on screen.
    @Test("the marks that are the only sign of what they mark stay drawn")
    func marksThatCarryTheirOwnMeaning() {
        for line in ["- milk", "1. milk", "> Someone said this", "---"] {
            let entry = Cursored("Woke late.\n\n\(line)", caret: 0)
            #expect(entry.marks.isEmpty, "\(line) lost the characters that make it what it is")
        }
    }

    // Until the picture is drawn — a later stage of the editor — the syntax is
    // the only sign that there is a picture at all.
    @Test("an embed keeps its syntax while nothing is drawn in its place")
    func embeds() {
        let entry = Cursored("![sunset](attachments/sunset.jpg) and then bed.", caret: 46)
        #expect(entry.marks.isEmpty)
    }

    @Test("a day with no markdown in it hides nothing")
    func plainWords() {
        #expect(Cursored("Woke late, and stayed late.", caret: 0).marks.isEmpty)
    }

    // The editor re-reads a paragraph rather than the day, and asks this of
    // the stretch it read. A cursor in some other paragraph is in none of
    // these elements, which is exactly what a reading of that stretch says.
    @Test("a reading of one paragraph answers for that paragraph")
    func partialReadings() {
        let entry = "# Sunday\n\nWalked to the *market*.\n"
        let paragraph = EntryMarkdown(entry, around: NSRange(location: 20, length: 0))
        let hidden = HiddenSyntax(paragraph, cursor: NSRange(location: 2, length: 0))

        #expect(hidden.ranges.count == 2)
        #expect(hidden.ranges.allSatisfy { paragraph.range.contains($0.location) })
    }
}

// Hiding is drawing, and drawing may not change the words. These are the tests
// that say so — for every place a cursor can be in an entry that has one of
// everything in it.
@Suite("Hiding never touches the words")
struct HiddenSyntaxSafetyTests {
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

    /// Every character that is a mark rather than a word, wherever it is: the
    /// only characters hiding is ever allowed to reach.
    private var marks: IndexSet {
        var marks = IndexSet()
        func note(_ range: NSRange) {
            marks.insert(integersIn: range.lowerBound..<range.upperBound)
        }
        func note(_ inlines: [MarkdownInline]) {
            for inline in inlines {
                note(inline.opening)
                note(inline.closing)
                note(inline.inlines)
            }
        }
        for line in EntryMarkdown(entry).lines {
            note(line.marker)
            note(line.inlines)
        }
        return marks
    }

    @Test("nothing but syntax is ever left undrawn, wherever the cursor is")
    func onlyMarksHide() {
        let syntax = marks
        for caret in 0...(entry as NSString).length {
            let hidden = HiddenSyntax(
                EntryMarkdown(entry), cursor: NSRange(location: caret, length: 0)
            )
            for range in hidden.ranges {
                #expect(
                    syntax.contains(integersIn: range.lowerBound..<range.upperBound),
                    "a cursor at \(caret) hid \(range), which is not all syntax"
                )
            }
        }
    }

    // The rule that makes editing safe: whatever the cursor is touching is on
    // screen. Nobody ever deletes a character they could not see, because
    // there is no such character where they are.
    @Test("the cursor is never inside something that is not drawn")
    func theCursorSeesWhereItIs() {
        for caret in 0...(entry as NSString).length {
            let cursor = NSRange(location: caret, length: 0)
            let hidden = HiddenSyntax(EntryMarkdown(entry), cursor: cursor)
            for range in hidden.ranges {
                #expect(
                    caret <= range.location || caret >= range.upperBound,
                    "a cursor at \(caret) was inside the hidden \(range)"
                )
            }
        }
    }

    @Test("a selection is never partly undrawn either")
    func aSelectionSeesWhatItCovers() {
        let length = (entry as NSString).length
        for location in 0...length {
            for width in [1, 4, 30] where location + width <= length {
                let cursor = NSRange(location: location, length: width)
                let hidden = HiddenSyntax(EntryMarkdown(entry), cursor: cursor)
                for range in hidden.ranges {
                    #expect(
                        NSIntersectionRange(range, cursor).length == 0,
                        "the selection \(cursor) covered the hidden \(range)"
                    )
                }
            }
        }
    }

    @Test("what is not drawn is always in order and never overlaps itself")
    func rangesAreOrderly() {
        for caret in 0...(entry as NSString).length {
            let ranges = HiddenSyntax(
                EntryMarkdown(entry), cursor: NSRange(location: caret, length: 0)
            ).ranges
            for (earlier, later) in zip(ranges, ranges.dropFirst()) {
                #expect(
                    earlier.upperBound <= later.location,
                    "a cursor at \(caret) gave \(earlier) before \(later)"
                )
            }
            #expect(ranges.allSatisfy { $0.length > 0 })
        }
    }
}
