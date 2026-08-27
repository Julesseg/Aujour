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

    // The control a box would need even if nothing else on the row existed: a
    // box is drawn over characters rather than being a view, so a finger is
    // the only thing that can tick one on the page. Round the three states, a
    // task is made, ticked and unmade without ever being aimed at.
    @Test("the checkbox control makes a task, ticks it, and unmakes it")
    func checkboxes() {
        let entry = OpenEditor(holding: "Milk")
        entry.cursor(at: 4)

        entry.coordinator.format(.taskList, in: entry.textView)
        #expect(entry.textView.text == "- [ ] Milk")
        #expect(entry.textView.selectedRange == NSRange(location: 10, length: 0))

        entry.coordinator.format(.taskList, in: entry.textView)
        #expect(entry.textView.text == "- [x] Milk")
        // Which is the same one character a finger on the box would have
        // changed, so the Entry is the plain task list it was before.
        #expect(entry.written == "- [x] Milk")

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

    // The commonest press there is: return, and then the control, before there
    // is anything on the line to format.
    @Test("a control starts a list on the empty line the return key just made")
    func emptyLines() {
        let entry = OpenEditor(holding: "Milk\n")
        entry.cursor(at: 5)

        entry.coordinator.format(.taskList, in: entry.textView)
        #expect(entry.textView.text == "Milk\n- [ ] ")
        // With the caret where the words go, so the next thing typed is the
        // task rather than something in front of the box.
        #expect(entry.textView.selectedRange == NSRange(location: 11, length: 0))
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

    // MARK: - The return key

    // The one keystroke the editor answers itself. What it writes is decided
    // in Core; what only a text view can show is that the keystroke is
    // intercepted at all, that the Entry hears about what went in, and that
    // the text view did not also write the line break it was asked for.
    @Test("a return in a list opens the next item, and nothing else does")
    func returningInAList() {
        let entry = OpenEditor(holding: "- Milk")
        entry.cursor(at: 6)

        #expect(!entry.typed("\n", at: NSRange(location: 6, length: 0)))
        #expect(entry.textView.text == "- Milk\n- ")
        #expect(entry.written == "- Milk\n- ")
        #expect(entry.textView.selectedRange == NSRange(location: 9, length: 0))

        // A return on the item nobody typed into ends the list — the way out,
        // and the only one that is not deleting what the editor wrote.
        #expect(!entry.typed("\n", at: NSRange(location: 9, length: 0)))
        #expect(entry.textView.text == "- Milk\n")

        // And a return anywhere else is the text view's own business, as is
        // every other key.
        #expect(entry.typed("\n", at: NSRange(location: 7, length: 0)))
        #expect(entry.typed("k", at: NSRange(location: 7, length: 0)))
    }

    // MARK: - The row itself

    // Above the keyboard is the text view's own accessory view, which is the
    // whole of how the row comes and goes with it.
    //
    // Nine controls and these nine. Every one of them writes a mark into the
    // file; how big the Entry's text is is a writing preference and is asked
    // for on the Appearance screen, so nothing here is a size control.
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
        // And every one of them has a symbol to say it with: a name UIKit does
        // not know comes back as no image at all, which is a button that is
        // there, is pressable, and looks like a gap in the row.
        #expect(controls(of: row).allSatisfy { $0.configuration?.image != nil })
    }

    @Test("pressing a control asks for the command it stands for")
    func pressing() throws {
        let pressed = Pressed()
        let row = aRow { pressed.commands.append($0) }

        try control("formatBold", of: row).sendActions(for: .touchUpInside)
        try control("formatTaskList", of: row).sendActions(for: .touchUpInside)
        try control("formatIndent", of: row).sendActions(for: .touchUpInside)

        #expect(pressed.commands == [.strong, .taskList, .indent])
    }

    // Six levels would be a row of nothing else, so the headings are a menu —
    // and one tap opens it, because nobody presses and holds above a keyboard.
    @Test("the heading control offers the levels a journal is written in")
    func headings() throws {
        let heading = try control("formatHeading", of: aRow { _ in })

        #expect(heading.showsMenuAsPrimaryAction)
        let levels = try #require(heading.menu?.children as? [UIAction])
        #expect(levels.map(\.title) == ["Heading 1", "Heading 2", "Heading 3"])
    }

    // What the menu is for. Which level a line comes out at is Core's, and a
    // menu whose items were built at the wrong level would be wrong in the one
    // place nothing else looks: the three items are asked for one at a time,
    // and each is the level it is named after.
    @Test("picking a level asks for a heading at that level")
    func headingLevels() throws {
        let pressed = Pressed()
        let heading = try control(
            "formatHeading", of: aRow { pressed.commands.append($0) }
        )
        let levels = try #require(heading.menu?.children as? [UIAction])

        for level in levels { level.performWithSender(nil, target: nil) }

        #expect(
            pressed.commands == [.heading(level: 1), .heading(level: 2), .heading(level: 3)]
        )
    }

    // MARK: - The pane it is drawn on

    // The platform's glass, tinted to the identity's paper rather than painted
    // over with it — and shaped as a pill inset from both edges, because the
    // chrome sits over the paper rather than across the bottom of it.
    @Test("the row is a pill of the platform's glass, tinted and inset")
    func theGlass() throws {
        let row = aRow { _ in }
        row.frame = CGRect(x: 0, y: 0, width: 390, height: row.intrinsicContentSize.height)
        row.layoutIfNeeded()

        let pane = try #require(glass(of: row))
        let seeThrough = !UIAccessibility.isReduceTransparencyEnabled
        if seeThrough {
            let glass = try #require(pane.effect as? UIGlassEffect)
            #expect(glass.tintColor == Palette.glass)
            // Glass draws its own edge and its own lift; a second of either is
            // two rims that do not agree.
            #expect(pane.layer.borderWidth == 0)
            #expect(shadows(under: pane).allSatisfy { $0.isHidden })
        } else {
            #expect(pane.effect == nil)
            #expect(pane.contentView.backgroundColor == Palette.glassSolid)
            #expect(pane.layer.borderWidth == 0.5)
            #expect(shadows(under: pane).allSatisfy { !$0.isHidden })
        }

        // A capsule, which is what `Rounding` says a pill is — it has no entry
        // there because it is half its own height at whatever size it came out.
        #expect(pane.layer.cornerRadius == pane.bounds.height / 2)

        // Off both edges and off the keyboard. Measured in the row's own
        // coordinates, because the pane sits inside the view that lifts it.
        let pill = row.convert(pane.bounds, from: pane)
        #expect(pill.minX > 0)
        #expect(pill.maxX < row.bounds.width)
        #expect(pill.height < row.bounds.height)

        // And the shadows are shaped, whether or not they are showing: a
        // shadow with no path casts nothing, and one with no mask would lay
        // its own outline down under the pane.
        #expect(shadows(under: pane).count == Elevation.floating.layers.count)
        #expect(shadows(under: pane).allSatisfy { $0.shadowPath != nil && $0.mask != nil })
    }

    // The width the identity draws a key at, asserted directly rather than
    // through whether they all fit a screen.
    //
    // Because the way this goes wrong is silent: a configured button pads its
    // own image, and that padding sets the width before the constraint here
    // gets a say. The keys came out half as wide again as they should be, the
    // row went on working, and every other test in this file went on passing
    // — it only showed up in a photograph of the thing.
    //
    // Nine of them at this width need 398 points, which the widest iPhones
    // have and the narrower ones do not: the row scrolls there, as it is built
    // to, and the control that goes under is the photograph.
    @Test("a key is the width the identity draws it at")
    func keyWidths() {
        let row = aRow { _ in }
        row.frame = CGRect(x: 0, y: 0, width: 420, height: row.intrinsicContentSize.height)
        row.layoutIfNeeded()

        let keys = controls(of: row)
        #expect(keys.count == 9)
        #expect(keys.allSatisfy { $0.bounds.width == 38 })

        // Which puts the last of them 386 points in, and asks 398 of the row
        // once the gap and the inset past it are counted — more than a phone
        // narrower than an Air has, so the row scrolls there as it is built to
        // and the control that goes under is the photograph.
        let photograph = keys.last
        #expect(photograph.map { row.convert($0.bounds, from: $0).maxX } == 386)
    }

    // The row knows there is a photograph control and nothing about what one
    // is: the picker, the file written into the Journal Root and the embed at
    // the caret are `InsertedPhotographs`'s. Handed nothing, the control is on
    // the row and says it is not ready, which is better than a button that
    // looks live and does nothing.
    @Test("the photo control is offered exactly when something can answer it")
    func photographs() throws {
        #expect(try !control("insertPhoto", of: aRow { _ in }).isEnabled)

        let pressed = Pressed()
        let ready = aRow(insertPhoto: { pressed.photographs += 1 }) { _ in }
        let photo = try control("insertPhoto", of: ready)

        #expect(photo.isEnabled)
        photo.sendActions(for: .touchUpInside)
        #expect(pressed.photographs == 1)
    }

    // MARK: - Reading the row

    /// What a press was heard as. A box rather than a variable, because the
    /// row keeps the closure that writes to it.
    private final class Pressed {
        var commands: [MarkdownFormatting] = []
        var photographs = 0
    }

    /// A row, with an accent for the pressed key. Terracotta rather than the
    /// default, so that a key drawn in the wrong colour is a key drawn in a
    /// colour no test asked for.
    private func aRow(
        insertPhoto: (() -> Void)? = nil,
        format: @escaping (MarkdownFormatting) -> Void
    ) -> MarkdownAccessoryRow {
        MarkdownAccessoryRow(
            accent: Accent.terracotta.uiColor, insertPhoto: insertPhoto, format: format
        )
    }

    /// The shadows the pill casts, which live on the view the pane sits in.
    private func shadows(under pane: UIView) -> [CALayer] {
        (pane.superview?.layer.sublayers ?? []).filter { $0.shadowOpacity > 0 }
    }

    /// The pane the keys sit on, found the way anything private is: by looking.
    private func glass(of row: MarkdownAccessoryRow) -> UIVisualEffectView? {
        func pane(in view: UIView) -> UIVisualEffectView? {
            for subview in view.subviews {
                if let pane = subview as? UIVisualEffectView { return pane }
                if let pane = pane(in: subview) { return pane }
            }
            return nil
        }
        return pane(in: row)
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
