import AujourCore
import Testing
import UIKit

@testable import Aujour

// The accessory row's half of formatting. What each control writes, and where
// it leaves the cursor, is decided in Core and tested there against the text it
// rewrites; what is left is the part that only exists once there is a text view
// and a row of buttons over it — that pressing a control rewrites the Entry the
// app is saving, that the caret is handed back where the user is writing, that
// a control with nothing to do writes nothing at all, and that every button is
// something a hand and a screen reader can find.

@MainActor
@Suite("The formatting row above the keyboard")
struct MarkdownAccessoryRowTests {

    // MARK: - Pressing a control

    @Test("bold wraps the word being written, and the Entry hears about it")
    func bold() {
        let entry = OpenEditor(holding: "Walked to the market.")
        entry.cursor(at: 17)

        #expect(entry.coordinator.format(.strong, in: entry.textView))
        #expect(entry.textView.text == "Walked to the **market**.")
        // Which is what saves it: the text view announces what it was told to
        // change, and a control tells it directly.
        #expect(entry.written == "Walked to the **market**.")
        // And the caret is still where the writing was, two characters along.
        #expect(entry.textView.selectedRange == NSRange(location: 19, length: 0))
    }

    @Test("the checkbox control makes a task of the line, and unmakes it")
    func checkboxes() {
        let entry = OpenEditor(holding: "Milk")
        entry.cursor(at: 4)

        entry.coordinator.format(.taskList, in: entry.textView)
        #expect(entry.textView.text == "- [ ] Milk")
        #expect(entry.textView.selectedRange == NSRange(location: 10, length: 0))

        entry.coordinator.format(.taskList, in: entry.textView)
        #expect(entry.textView.text == "Milk")
    }

    // A control is an edit, and the day it is in is full of typing: shaking to
    // undo after pressing the wrong one should take back that press — the
    // characters and the cursor — and not the sentence typed before it.
    @Test("a control can be undone, cursor and all")
    func undoing() throws {
        let entry = OpenEditor(holding: "Milk")
        entry.cursor(at: 2)
        entry.coordinator.format(.bulletList, in: entry.textView)
        #expect(entry.textView.text == "- Milk")

        let undo = try #require(entry.textView.undoManager)
        #expect(undo.canUndo)
        undo.undo()

        #expect(entry.textView.text == "Milk")
        #expect(entry.written == "Milk")
        #expect(entry.textView.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("a control with nothing to do leaves the Entry alone")
    func nothingToDo() {
        let entry = OpenEditor(holding: "Milk")
        entry.cursor(at: 0)

        #expect(!entry.coordinator.format(.outdent, in: entry.textView))
        #expect(entry.written == nil)
    }

    // Bold at the end of a bold word means "and the rest is not bold", which is
    // a caret past the marks: no characters change, so there is nothing to save
    // and nothing to undo either.
    @Test("stepping out of a bold word writes nothing at all")
    func steppingOut() {
        let entry = OpenEditor(holding: "**Milk**")
        entry.cursor(at: 6)

        #expect(entry.coordinator.format(.strong, in: entry.textView))
        #expect(entry.textView.text == "**Milk**")
        #expect(entry.written == nil)
        #expect(entry.textView.selectedRange == NSRange(location: 8, length: 0))
        #expect(entry.textView.undoManager?.canUndo == false)
    }

    // MARK: - The row itself

    // Above the keyboard is the text view's own accessory view, which is the
    // whole of how the row comes and goes with it.
    @Test("the editor puts the row above the keyboard, with every control on it")
    func theRow() throws {
        let entry = OpenEditor(holding: "Milk")
        let row = try #require(entry.textView.inputAccessoryView as? MarkdownAccessoryRow)

        #expect(
            controls(of: row).compactMap(\.accessibilityIdentifier) == [
                "formatHeading", "formatBold", "formatItalic", "formatBulletList",
                "formatNumberedList", "formatTaskList", "formatOutdent", "formatIndent",
                "insertPhoto",
            ]
        )
        // A symbol is not something VoiceOver can read out, so every one of
        // them says what it is.
        #expect(controls(of: row).allSatisfy { $0.accessibilityLabel?.isEmpty == false })
    }

    @Test("pressing a control asks for the command it stands for")
    func pressing() throws {
        let pressed = Pressed()
        let row = MarkdownAccessoryRow { pressed.commands.append($0) }

        try control("formatBold", of: row).sendActions(for: .touchUpInside)
        try control("formatTaskList", of: row).sendActions(for: .touchUpInside)
        try control("formatIndent", of: row).sendActions(for: .touchUpInside)

        #expect(pressed.commands == [.strong, .taskList, .indent])
    }

    // Six levels would be a row of nothing else, so the headings are a menu —
    // and one tap opens it, because nobody presses and holds above a keyboard.
    @Test("the heading control offers the levels a journal is written in")
    func headings() throws {
        let heading = try control("formatHeading", of: MarkdownAccessoryRow { _ in })

        #expect(heading.showsMenuAsPrimaryAction)
        let levels = try #require(heading.menu?.children as? [UIAction])
        #expect(levels.map(\.title) == ["Heading 1", "Heading 2", "Heading 3"])
    }

    // The picker, the file copied into the Journal Root, the embed written at
    // the caret — all of it is the attachment pipeline's (issue #22). Until it
    // is there the control is on the row and says it is not ready, which is
    // better than a button that looks live and does nothing.
    @Test("the photo control waits until something has said what it does")
    func photographs() throws {
        #expect(try !control("insertPhoto", of: MarkdownAccessoryRow { _ in }).isEnabled)

        let asked = Pressed()
        let ready = MarkdownAccessoryRow(insertPhoto: { asked.commands.append(.indent) }) { _ in }
        let photo = try control("insertPhoto", of: ready)

        #expect(photo.isEnabled)
        photo.sendActions(for: .touchUpInside)
        #expect(asked.commands.count == 1)
    }

    // MARK: - Reading the row

    /// What a press was heard as. A box rather than a variable, because the
    /// row keeps the closure that writes to it.
    private final class Pressed {
        var commands: [MarkdownFormatting] = []
    }

    /// Every button on the row, left to right.
    private func controls(of row: MarkdownAccessoryRow) -> [UIButton] {
        func buttons(in view: UIView) -> [UIButton] {
            view.subviews.flatMap { subview in
                (subview as? UIButton).map { [$0] } ?? buttons(in: subview)
            }
        }
        return buttons(in: row)
    }

    private func control(_ identifier: String, of row: MarkdownAccessoryRow) throws -> UIButton {
        try #require(controls(of: row).first { $0.accessibilityIdentifier == identifier })
    }
}
