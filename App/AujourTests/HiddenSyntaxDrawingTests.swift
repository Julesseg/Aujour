import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

// The editor's half of live preview. Which marks the cursor leaves hidden is
// decided in Core and tested there against the text they came from; what is
// left is the part that only exists once there is a font and a line to lay out
// — that a hidden `#` really takes no room on screen, that it comes back the
// moment the cursor arrives, and that all of it still costs a paragraph.
//
// Headless, and no simulator screenshot in sight: a text storage with a layout
// manager attached is enough to ask how wide a line came out.

@MainActor
@Suite("Syntax that hides where the cursor is not")
struct HiddenSyntaxDrawingTests {
    private let styling = MarkdownStyling()

    private func storage(holding source: String, cursor: NSRange) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage(styling: styling)
        storage.setSource(source)
        storage.cursor = cursor
        return storage
    }

    private func storage(holding source: String, caret: Int) -> MarkdownTextStorage {
        storage(holding: source, cursor: NSRange(location: caret, length: 0))
    }

    /// The stretches the storage marked as not to be drawn, as the characters
    /// they cover.
    private func undrawn(in storage: MarkdownTextStorage) -> [String] {
        var marks: [String] = []
        storage.enumerateAttribute(
            .hiddenSyntax,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard value != nil else { return }
            marks.append((storage.string as NSString).substring(with: range))
        }
        return marks
    }

    @Test("markdown away from the cursor is marked as not to be drawn")
    func syntaxHidesAwayFromTheCursor() {
        let entry = storage(holding: "# Sunday\n\nWoke *late*.", caret: 22)
        #expect(undrawn(in: entry) == ["# ", "*", "*"])
    }

    @Test("the element the cursor is in shows its marks")
    func syntaxRevealsAtTheCursor() {
        #expect(undrawn(in: storage(holding: "# Sunday\n\nWoke late.", caret: 3)).isEmpty)
        #expect(undrawn(in: storage(holding: "A *soft* word", caret: 5)).isEmpty)
    }

    // The cursor moving is the whole interaction, and it has to work both
    // ways: what was hidden comes back, and what was shown goes again.
    @Test("moving the cursor reveals where it arrived and hides where it left")
    func movingTheCursor() {
        let entry = storage(holding: "# Sunday\n\nWoke *late*.", caret: 3)
        #expect(undrawn(in: entry) == ["*", "*"])

        entry.cursor = NSRange(location: 17, length: 0)
        #expect(undrawn(in: entry) == ["# "])

        entry.cursor = NSRange(location: 22, length: 0)
        #expect(undrawn(in: entry) == ["# ", "*", "*"])
    }

    // ADR 0001, under the one feature that could break it: what is on screen
    // is a drawing of the file, and drawing it differently is not editing it.
    @Test("hiding and revealing never change a character of the text")
    func theTextIsUntouched() {
        let entry = "# Sunday\n\nWalked to the *market* -- it's **shut**.\n"
        let day = storage(holding: entry, caret: 0)

        for caret in 0...day.length {
            day.cursor = NSRange(location: caret, length: 0)
            #expect(day.string == entry)
        }
    }

    // The other half of the same promise, and the one a reader is most likely
    // to test by accident: a mark that is not drawn is still under the
    // selection that runs over it, so it comes out on the pasteboard and it
    // goes when the selection goes. Nothing is hidden from the hand — only
    // from the eye.
    @Test("a selection reaches the marks it cannot see, and takes them with it")
    func selectingOverAHiddenMark() {
        let entry = storage(holding: "# Sunday\n\nWoke *late*.", caret: 22)
        #expect(undrawn(in: entry) == ["# ", "*", "*"])

        // Selecting the heading reveals it, so that what is about to go is on
        // screen before it goes.
        let heading = NSRange(location: 0, length: 8)
        entry.cursor = heading
        #expect(undrawn(in: entry) == ["*", "*"])

        // And a copy takes the text under the selection, hashes and all —
        // including, on the day the selection was made without ever revealing
        // them, the characters that were never drawn.
        #expect(entry.attributedSubstring(from: heading).string == "# Sunday")

        // What a delete takes is that same stretch: the file loses the hashes
        // and what is left is a plain line, with the emphasis further down
        // still hidden because the cursor is not in it.
        entry.replaceCharacters(in: heading, with: "Sunday")
        entry.cursor = NSRange(location: 6, length: 0)
        #expect(entry.string == "Sunday\n\nWoke *late*.")
        #expect(undrawn(in: entry) == ["*", "*"])
    }

    // Deleting a delimiter leaves markdown that no longer says what it said,
    // and the marks that were hidden on its account have to be drawn again —
    // there is no span left for them to belong to.
    @Test("a mark deleted at the edge of an element leaves nothing hidden behind it")
    func editingAtTheEdgeOfAnElement() {
        let entry = storage(holding: "A *soft* word", caret: 12)
        #expect(undrawn(in: entry) == ["*", "*"])

        entry.replaceCharacters(in: NSRange(location: 7, length: 1), with: "")
        entry.cursor = NSRange(location: 7, length: 0)

        #expect(entry.string == "A *soft word")
        #expect(undrawn(in: entry).isEmpty)
    }

    // Typing the star that closes emphasis is the moment a span comes into
    // existence, and the cursor is against it: nothing may vanish under the
    // hand that just typed it.
    @Test("the marks being typed stay drawn")
    func typingAnElement() {
        let entry = storage(holding: "A *soft word", caret: 7)
        entry.replaceCharacters(in: NSRange(location: 7, length: 0), with: "*")
        entry.cursor = NSRange(location: 8, length: 0)

        #expect(entry.string == "A *soft* word")
        #expect(undrawn(in: entry).isEmpty)
    }

    // The keyboard going down is the cursor leaving the Entry altogether, and
    // the day it leaves behind is one to read.
    @Test("an entry nobody is writing in shows no marks at all")
    func noCursorAtAll() {
        let entry = storage(holding: "# Sunday\n\nWoke *late*.", caret: 3)
        #expect(undrawn(in: entry) == ["*", "*"])

        entry.cursor = nil
        #expect(undrawn(in: entry) == ["# ", "*", "*"])

        entry.cursor = NSRange(location: 3, length: 0)
        #expect(undrawn(in: entry) == ["*", "*"])
    }

    @Test("a selection shows the marks of everything it covers")
    func selections() {
        let entry = storage(
            holding: "# Sunday\n\nWoke *late*.",
            cursor: NSRange(location: 0, length: 22)
        )
        #expect(undrawn(in: entry).isEmpty)
    }

    // What the attribute is *for*, and the only test that can see it: a hidden
    // mark is not drawn faintly or in the background colour, it takes up no
    // room at all, and the words either side of it close up.
    @Test("hidden syntax takes up no room on the line")
    func hiddenSyntaxIsNotLaidOut() {
        let entry = "# Sunday\n\nWoke late."
        let hashes = NSRange(location: 0, length: 2)

        let away = laidOut(entry, caret: 15)
        let onTheHeading = laidOut(entry, caret: 3)

        #expect(away.width(of: hashes) == 0, "the hashes were still taking up room")
        #expect(onTheHeading.width(of: hashes) > 0, "the hashes never came back")

        // And the line closes up by exactly as much: the heading's words start
        // where the hashes were, rather than after a gap where they used to be.
        let hidden = away.lineWidth(atCharacter: 0)
        let shown = onTheHeading.lineWidth(atCharacter: 0)
        #expect(hidden < shown, "hiding the hashes did not narrow the line")
        #expect(
            abs(shown - hidden - onTheHeading.width(of: hashes)) < 1.5,
            "the line lost \(shown - hidden) points for \(onTheHeading.width(of: hashes)) of syntax"
        )
    }

    // The same claim as for a keystroke, for the other thing that happens
    // constantly: a cursor moving restyles the paragraph it left and the one
    // it arrived in, whatever the day weighs.
    @Test("moving the cursor costs the paragraphs at either end of the move")
    func movingCostsTwoParagraphs() {
        let entry = (1...500)
            .map { "Paragraph \($0), with *some* emphasis and a few plain words in it." }
            .joined(separator: "\n\n")
        let day = storage(holding: entry, caret: 0)
        #expect(day.length > 20_000)

        let far = (entry as NSString).range(of: "Paragraph 250,")
        day.cursor = NSRange(location: far.location + 2, length: 0)

        #expect(day.restyledRanges.count == 2)
        for stretch in day.restyledRanges {
            #expect(stretch.length < 200, "restyled \(stretch.length) characters to move a caret")
        }
    }

    @Test("moving the cursor within a paragraph costs that paragraph once")
    func movingInsideOneParagraph() {
        let day = storage(holding: "# Sunday\n\nWoke *late*.", caret: 12)
        day.cursor = NSRange(location: 17, length: 0)

        #expect(day.restyledRanges.count == 1)
    }

    // MARK: - Laying a day out for real

    /// This suite's day: the plain layout manager, because every measurement
    /// here is about the room a character takes rather than about anything
    /// painted over one.
    private func laidOut(_ source: String, caret: Int) -> LaidOutDay {
        LaidOutDay(source, styling: styling, cursor: NSRange(location: caret, length: 0))
    }
}
