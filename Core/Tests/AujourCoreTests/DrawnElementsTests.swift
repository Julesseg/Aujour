import Foundation
import Testing

@testable import AujourCore

// The stretches the editor stands something else in front of: a task's box
// and an embed's picture. Which pixels those are is the app's — a box is an SF
// Symbol and a picture is a JPEG off the disk — but *where* they go, what they
// point at, and when they give way to the markdown underneath is a fact about
// the text and the cursor, so it is decided here.

/// A reading of some markdown with a cursor somewhere in it, and the drawings
/// resolved back into the characters they stand in for.
private struct Drawn {
    let source: String
    let elements: [DrawnElements.Element]
    private let units: [UInt16]

    init(_ source: String, cursor: NSRange?) {
        self.source = source
        self.units = Array(source.utf16)
        self.elements = DrawnElements(EntryMarkdown(source), in: source, cursor: cursor).elements
    }

    init(_ source: String, caret: Int) {
        self.init(source, cursor: NSRange(location: caret, length: 0))
    }

    /// The same day with nobody writing in it.
    init(_ source: String) {
        self.init(source, cursor: nil)
    }

    var kinds: [DrawnElements.Element.Kind] { elements.map(\.kind) }

    /// What each drawing covers, as the characters it covers.
    var covered: [String] {
        elements.map {
            String(decoding: units[$0.range.lowerBound..<$0.range.upperBound], as: UTF16.self)
        }
    }
}

@Suite("What the editor draws in place of the text")
struct DrawnElementsTests {
    @Test("a task's marker is drawn as a box, ticked or not")
    func taskBoxes() {
        let list = Drawn("- [ ] milk\n- [x] bread")
        #expect(list.kinds == [.taskBox(isDone: false), .taskBox(isDone: true)])
        // The whole marker, so that the box sits where the bullet was rather
        // than after it.
        #expect(list.covered == ["- [ ] ", "- [x] "])
    }

    // The rule that makes editing safe, and the same one hiding uses: what the
    // cursor is touching is on screen as the characters it really is.
    @Test("the box gives way to its own markdown at the cursor")
    func aTaskAtTheCursor() {
        #expect(Drawn("- [ ] milk\n- [x] bread", caret: 3).covered == ["- [x] "])
        #expect(Drawn("- [ ] milk", caret: 0).elements.isEmpty)
        #expect(Drawn("- [ ] milk", caret: 10).elements.isEmpty)
        // One past the break is the next line, and the task is a box again.
        #expect(Drawn("- [ ] milk\nWoke late.", caret: 11).covered == ["- [ ] "])
    }

    @Test("an embed is drawn as the picture it points at, in either spelling")
    func pictures() {
        let standard = Drawn("![the market](attachments/market.jpg)")
        #expect(standard.kinds == [.picture(target: "attachments/market.jpg")])
        #expect(standard.covered == ["![the market](attachments/market.jpg)"])

        let wiki = Drawn("![[market.jpg]]")
        #expect(wiki.kinds == [.picture(target: "market.jpg")])
        #expect(wiki.covered == ["![[market.jpg]]"])
    }

    // The picture stands in for the alt text as well as the syntax, which is
    // why this is not hiding: everything the embed is made of goes, and one
    // thing comes back.
    @Test("the embed's own words come back at the cursor")
    func anEmbedAtTheCursor() {
        let embed = "![the market](attachments/market.jpg)"
        let source = "\(embed) and then home."
        #expect(Drawn(source, caret: 51).covered == [embed])
        #expect(Drawn(source, caret: 5).elements.isEmpty)
        #expect(Drawn(source, caret: 37).elements.isEmpty)
    }

    @Test("an embed that names nothing is left as the words it is")
    func embedsWithoutATarget() {
        #expect(Drawn("![no target]()").elements.isEmpty)
        #expect(Drawn("![no target](   )").elements.isEmpty)
    }

    // A selection reveals what it covers, for the same reason it reveals
    // marks: what is about to be deleted is on screen before it goes.
    @Test("a selection puts back everything it covers")
    func selections() {
        let source = "- [ ] milk\n\n![a](b.jpg)"
        let whole = NSRange(location: 0, length: (source as NSString).length)
        #expect(Drawn(source, cursor: whole).elements.isEmpty)
        #expect(Drawn(source, cursor: NSRange(location: 12, length: 5)).covered == ["- [ ] "])
    }

    // MARK: - Interactive placeholders

    @Test("an unanswered placeholder is drawn as its widget")
    func placeholderWidgets() {
        let day = Drawn("{{mood}}\n\nWalked home from {{location}}.")
        #expect(day.kinds == [.widget(.mood), .widget(.location)])
        // The whole token, so that answering it takes every character of it
        // away and leaves no brace behind.
        #expect(day.covered == ["{{mood}}", "{{location}}"])
    }

    @Test("the widget gives way to its own markdown at the cursor")
    func aPlaceholderAtTheCursor() {
        #expect(Drawn("{{mood}}", caret: 4).elements.isEmpty)
        #expect(Drawn("{{mood}}", caret: 0).elements.isEmpty)
        #expect(Drawn("{{mood}}", caret: 8).elements.isEmpty)
        #expect(Drawn("{{mood}} {{location}}", caret: 2).covered == ["{{location}}"])
    }

    // The picture stands in for the whole embed, alt text and all, and two
    // drawings over the same characters is one of them drawn over nothing.
    @Test("a token inside an embed is part of the picture")
    func placeholdersInsideAnEmbed() {
        let day = Drawn("![{{location}}](market.jpg)")
        #expect(day.kinds == [.picture(target: "market.jpg")])
    }

    @Test("a day nobody is writing in is drawn as a document, all of it")
    func noCursorAtAll() {
        let entry = Drawn("- [x] milk\n\n![a](b.jpg)")
        #expect(entry.kinds == [.taskBox(isDone: true), .picture(target: "b.jpg")])
    }

    @Test("a day with nothing to draw over draws nothing")
    func plainWords() {
        #expect(Drawn("Woke late, and stayed late.").elements.isEmpty)
        #expect(Drawn("- milk\n1. bread\n> quoted\n---").elements.isEmpty)
    }

    // The editor re-reads a paragraph rather than the day, and asks this of
    // the stretch it read — so the answers come back in the whole Entry's
    // coordinates and mean the same thing as reading all of it would.
    @Test("a reading of one paragraph answers for that paragraph")
    func partialReadings() {
        let entry = "# Sunday\n\n- [ ] milk\n"
        let paragraph = EntryMarkdown(entry, around: NSRange(location: 14, length: 0))
        let drawn = DrawnElements(paragraph, in: entry, cursor: NSRange(location: 2, length: 0))

        #expect(drawn.elements.map(\.kind) == [.taskBox(isDone: false)])
        #expect(drawn.elements[0].range == NSRange(location: 10, length: 6))
    }

    @Test("what is drawn is always in order and never overlaps itself")
    func elementsAreOrderly() {
        let entry = """
            - [ ] milk
            - [x] bread, and ![the market](attachments/market.jpg)
            ![[home.jpg]]
            - [ ] {{mood}}, walked home from {{location}}
            """
        for caret in 0...(entry as NSString).length {
            let drawn = DrawnElements(
                EntryMarkdown(entry), in: entry, cursor: NSRange(location: caret, length: 0)
            ).elements
            for (earlier, later) in zip(drawn, drawn.dropFirst()) {
                #expect(
                    earlier.range.upperBound <= later.range.location,
                    "a cursor at \(caret) gave \(earlier.range) before \(later.range)"
                )
            }
        }
    }

    // Nobody ever edits a character they cannot see, here as much as in
    // hiding: whatever the cursor touches is drawn as itself.
    @Test("the cursor is never inside something that was drawn over")
    func theCursorSeesWhereItIs() {
        let entry = "- [x] milk, from ![the market](attachments/market.jpg)\n- [ ] bread"
        for caret in 0...(entry as NSString).length {
            let cursor = NSRange(location: caret, length: 0)
            for element in DrawnElements(EntryMarkdown(entry), in: entry, cursor: cursor).elements {
                #expect(
                    caret <= element.range.location || caret >= element.range.upperBound,
                    "a cursor at \(caret) was inside the drawn \(element.range)"
                )
            }
        }
    }
}

@Suite("Ticking a box")
struct TickingABoxTests {
    private func ticked(_ source: String, at index: Int) -> String? {
        guard let edit = EntryMarkdown(source).tickingTheBox(at: index) else { return nil }
        let rewritten = NSMutableString(string: source)
        rewritten.replaceCharacters(in: edit.range, with: edit.replacement)
        return rewritten as String
    }

    @Test("ticking a box rewrites one character of the line and nothing else")
    func tickingAndUnticking() {
        #expect(ticked("- [ ] milk", at: 2) == "- [x] milk")
        #expect(ticked("- [x] milk", at: 2) == "- [ ] milk")

        let edit = EntryMarkdown("- [ ] milk").tickingTheBox(at: 2)
        #expect(edit == MarkdownEdit(range: NSRange(location: 3, length: 1), replacement: "x"))
    }

    // A tap lands on a box that is drawn over six characters, so anywhere on
    // the line is the same answer — and the line it means is the line the
    // index is on, not the first one that has a box.
    @Test("anywhere on the line ticks that line's box")
    func anywhereOnTheLine() {
        let list = "- [ ] milk\n- [ ] bread\n"
        for index in 0...10 {
            #expect(ticked(list, at: index) == "- [x] milk\n- [ ] bread\n")
        }
        for index in 11...22 {
            #expect(ticked(list, at: index) == "- [ ] milk\n- [x] bread\n")
        }
    }

    @Test("a line with no box is nothing to tick")
    func linesWithoutABox() {
        #expect(ticked("- milk", at: 2) == nil)
        #expect(ticked("Woke late.", at: 4) == nil)
        #expect(ticked("# Sunday\n\n- [ ] milk", at: 3) == nil)
    }

    // Past the end of the text is the last line, which is where a tap below
    // the words lands.
    @Test("an index past the end is the last line")
    func pastTheEnd() {
        #expect(ticked("- [ ] milk", at: 40) == "- [x] milk")
        #expect(ticked("", at: 5) == nil)
    }

    @Test("the entry either side of the box is untouched, byte for byte")
    func nothingElseMoves() {
        let entry = """
            # Sunday

            - [ ] milk
            - [x] **bread**, still warm

            Walked home the *long* way.
            """
        let after = ticked(entry, at: 12)
        #expect(after == entry.replacingOccurrences(of: "- [ ] milk", with: "- [x] milk"))
        #expect(after?.count == entry.count)
    }
}
