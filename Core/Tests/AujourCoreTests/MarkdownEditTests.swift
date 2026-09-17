import Foundation
import Testing

@testable import AujourCore

// Where an edit leaves the cursor when it has no opinion of its own — which is
// every edit somebody made by tapping something rather than by writing.

@Suite("Where an edit leaves a cursor it says nothing about")
struct MarkdownEditCursorTests {
    private func caret(_ location: Int) -> NSRange {
        NSRange(location: location, length: 0)
    }

    // Ticking a box writes one character over one, so nothing after it moves:
    // a caret three paragraphs down is on the same character afterwards.
    @Test("an edit that changes no lengths leaves the cursor exactly where it was")
    func aTickMovesNothing() {
        let tick = MarkdownEdit(range: NSRange(location: 3, length: 1), replacement: "x")
        #expect(tick.cursorLeftWhere(it: caret(40)) == caret(40))
        #expect(tick.cursorLeftWhere(it: NSRange(location: 40, length: 5))
            == NSRange(location: 40, length: 5))
    }

    // An answered widget writes a sentence where eight characters were, and a
    // caret after it has to move by the difference to stay on the word
    // somebody was writing.
    @Test("an edit before the cursor carries it by what it changed")
    func anAnswerCarriesTheCursor() {
        let answer = MarkdownEdit(
            range: NSRange(location: 0, length: 8), replacement: "Today's mood: 4/5"
        )
        #expect(answer.cursorLeftWhere(it: caret(19)) == caret(28))

        let shorter = MarkdownEdit(range: NSRange(location: 0, length: 8), replacement: "Good")
        #expect(shorter.cursorLeftWhere(it: caret(19)) == caret(15))
    }

    // An edit reaching into the cursor is an edit to the very characters it is
    // on — a formatting control, which always says where it wants the cursor
    // left. Guessing here would be guessing over that.
    @Test("an edit the cursor is in or after leaves it alone")
    func anEditUnderTheCursor() {
        let answer = MarkdownEdit(
            range: NSRange(location: 10, length: 8), replacement: "Today's mood: 4/5"
        )
        #expect(answer.cursorLeftWhere(it: caret(12)) == caret(12))
        #expect(answer.cursorLeftWhere(it: caret(4)) == caret(4))
        // A caret against the edit's closing edge is after it, and moves with
        // everything else that was after it.
        #expect(answer.cursorLeftWhere(it: caret(18)) == caret(27))
    }
}

// One rule for anything that goes into a day on a line of its own — a
// photograph's embed, a meeting's line — so that an event tapped from the
// sheet lands the way a picture does and not by a second reading of "at the
// caret".
@Suite("Putting markdown on a line of its own")
struct MarkdownEditOwnLineTests {
    private let line = "- 09:30 Standup"

    private func caret(_ location: Int, length: Int = 0) -> NSRange {
        NSRange(location: location, length: length)
    }

    @Test("a caret in the middle of a line pushes the rest of it below")
    func caretMidLine() {
        let edit = MarkdownEdit.onItsOwnLine(line, in: "Milk and bread", at: caret(4))

        #expect(edit.range == caret(4))
        #expect(edit.replacement == "\n- 09:30 Standup\n")
        // On the line the rest of the sentence was pushed onto.
        #expect(edit.selection == caret(21))
    }

    @Test("a caret at the start of a line writes no line break before")
    func caretAtLineStart() {
        let edit = MarkdownEdit.onItsOwnLine(line, in: "Milk\nBread", at: caret(5))

        #expect(edit.range == caret(5))
        #expect(edit.replacement == "- 09:30 Standup\n")
        #expect(edit.selection == caret(21))
    }

    @Test("a caret at the end of the file writes no line break after")
    func caretAtEndOfFile() {
        let edit = MarkdownEdit.onItsOwnLine(line, in: "Milk", at: caret(4))

        #expect(edit.range == caret(4))
        #expect(edit.replacement == "\n- 09:30 Standup")
        #expect(edit.selection == caret(20))
    }

    @Test("a caret at the end of a line with text below breaks only before")
    func textFollowingOnTheNextLine() {
        let edit = MarkdownEdit.onItsOwnLine(line, in: "Milk\nBread", at: caret(4))

        #expect(edit.replacement == "\n- 09:30 Standup")
        #expect(edit.selection == caret(20))
    }

    @Test("a caret on an empty line, or in an empty day, writes the line and nothing else")
    func caretOnAnEmptyLine() {
        #expect(MarkdownEdit.onItsOwnLine(line, in: "", at: caret(0)).replacement == line)
        #expect(MarkdownEdit.onItsOwnLine(line, in: "Milk\n", at: caret(5)).replacement == line)
        #expect(MarkdownEdit.onItsOwnLine(line, in: "Milk\n\nBread", at: caret(5)).replacement == line)
    }

    // Nobody inserting a line meant to delete the words they had selected,
    // and no words are ever silently discarded — so it goes in after them.
    @Test("a selection is kept, and the line goes in after it")
    func afterASelection() {
        let edit = MarkdownEdit.onItsOwnLine(line, in: "Milk and bread", at: caret(0, length: 4))

        #expect(edit.range == caret(4))
        #expect(edit.replacement == "\n- 09:30 Standup\n")
        #expect(edit.selection == caret(21))
    }

    // A caret reported past the end of the day is about a version of it that
    // has been replaced since: the end of the Entry, not an exception.
    @Test("a caret past the end of the day writes at the end of it")
    func pastTheEnd() {
        let edit = MarkdownEdit.onItsOwnLine(line, in: "Milk", at: caret(99))

        #expect(edit.range == caret(4))
        #expect(edit.replacement == "\n- 09:30 Standup")
    }
}
