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
