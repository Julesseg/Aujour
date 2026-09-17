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
    // Nine formatting controls, and Suggestions apart from them. How big the
    // Entry's text is is a writing preference and is asked for on the
    // Appearance screen, so nothing here is a size control.
    @Test("the editor puts the row above the keyboard, with every control on it")
    func theRow() throws {
        let entry = OpenEditor(holding: "Milk")
        let row = try #require(entry.textView.inputAccessoryView as? MarkdownAccessoryRow)

        #expect(
            controls(of: row).compactMap(\.accessibilityIdentifier) == [
                "formatHeading", "formatBold", "formatItalic", "formatBulletList",
                "formatNumberedList", "formatTaskList", "formatOutdent", "formatIndent",
                "insertPhoto", "openSuggestions",
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

    // MARK: - The panes it is drawn on

    // The same platform glass for both panes, tinted to the identity's paper
    // rather than painted over with it.
    @Test("both panes use the same glass recipe and sit inside the row")
    func theGlass() throws {
        let row = aRow { _ in }
        row.frame = CGRect(x: 0, y: 0, width: 390, height: row.intrinsicContentSize.height)
        row.layoutIfNeeded()

        let panes = glasses(of: row)
        #expect(panes.count == 2)
        let seeThrough = !UIAccessibility.isReduceTransparencyEnabled
        for pane in panes {
            if seeThrough {
                let glass = try #require(pane.effect as? UIGlassEffect)
                #expect(glass.tintColor == Palette.glass)
                #expect(pane.layer.borderWidth == 0)
                #expect(shadows(under: pane).allSatisfy { $0.isHidden })
            } else {
                #expect(pane.effect == nil)
                #expect(pane.contentView.backgroundColor == Palette.glassSolid)
                #expect(pane.layer.borderWidth == 0.5)
                #expect(shadows(under: pane).allSatisfy { !$0.isHidden })
            }

            #expect(pane.effectiveRadius(corner: .allCorners) == pane.bounds.height / 2)

            let pill = row.convert(pane.bounds, from: pane)
            #expect(pill.minX > 0)
            #expect(pill.maxX < row.bounds.width)
            #expect(pill.height < row.bounds.height)

            #expect(shadows(under: pane).count == Elevation.floating.layers.count)
            #expect(shadows(under: pane).allSatisfy { $0.shadowPath != nil && $0.mask != nil })
        }
    }

    // On a phone the formatting strip gives way and scrolls, while Suggestions
    // remains fully visible on its own pane.
    @Test("phone widths keep Suggestions visible and let the formatting strip scroll")
    func keyWidths() throws {
        for screen in [375.0, 393.0, 440.0] as [CGFloat] {
            let row = aRow { _ in }
            row.frame = CGRect(
                x: 0, y: 0, width: screen, height: row.intrinsicContentSize.height
            )
            row.layoutIfNeeded()

            let keys = controls(of: row)
            #expect(keys.count == 10)
            let formatting = Array(keys.dropLast())
            let suggestion = try #require(keys.last)

            let key = try #require(formatting.first).bounds.size
            #expect(formatting.allSatisfy { abs($0.bounds.width - key.width) <= 1 })

            #expect(key.width >= 34)
            #expect(key.width <= key.height)
            #expect(abs(suggestion.bounds.width - suggestion.bounds.height) < 0.5)

            let lastFormatting = try #require(formatting.last)
            let strip = try #require(glass(containing: lastFormatting))
            let apart = try #require(glass(containing: suggestion))
            if screen == 375 {
                #expect(
                    row.convert(lastFormatting.bounds, from: lastFormatting).maxX
                        > row.convert(strip.bounds, from: strip).maxX
                )
            }
            let suggestionFrame = row.convert(suggestion.bounds, from: suggestion)
            let apartFrame = row.convert(apart.bounds, from: apart)
            #expect(suggestionFrame.minX >= apartFrame.minX)
            #expect(suggestionFrame.maxX <= apartFrame.maxX)
            #expect(apartFrame.maxX < row.bounds.maxX)
        }
    }

    // A mark leaves most of its key clear around it.
    //
    // A mark is a label for the key, not a word in the Entry, and at body size
    // it was not drawn like one: the widest of the nine — the photograph —
    // came out 26 points across a 37-point key, which is seven tenths of it
    // and reads as a symbol somebody forgot to leave room around. At footnote
    // it is 20, and this is the line between the two.
    //
    // The sort of thing that otherwise only shows up in a photograph, which is
    // how this one was found.
    @Test("a mark leaves three fifths of its key clear around it")
    func markSizes() throws {
        let row = aRow { _ in }
        row.frame = CGRect(x: 0, y: 0, width: 393, height: row.intrinsicContentSize.height)
        row.layoutIfNeeded()

        for key in controls(of: row) {
            let symbol = try #require(key.configuration?.image)
            let sizing = try #require(key.configuration?.preferredSymbolConfigurationForImage)
            let drawn = try #require(symbol.applyingSymbolConfiguration(sizing)).size

            #expect(drawn.width <= key.bounds.width * 0.6 + 0.5)
            #expect(drawn.height <= key.bounds.height * 0.4)
        }
    }

    // An iPad has more room than nine keys should take. They stop at square,
    // because past that a key stops reading as a key.
    @Test("the keys stop growing at square")
    func wideScreens() throws {
        let row = aRow { _ in }
        row.frame = CGRect(x: 0, y: 0, width: 1024, height: row.intrinsicContentSize.height)
        row.layoutIfNeeded()

        let keys = controls(of: row)
        #expect(keys.count == 10)
        #expect(keys.allSatisfy { abs($0.bounds.width - $0.bounds.height) < 0.5 })
    }

    // And once the keys have stopped, so does the pane: it is as wide as the
    // nine of them and not as wide as the screen.
    //
    // Because a pane that reaches both edges of an iPad is the bar this row
    // is not — glass across the top of the keyboard rather than a pill over
    // the paper. It went wrong silently and intermittently: the pane's edges
    // and the keys' width were two wishes of the same priority that could not
    // both come true on a wide row, so Auto Layout picked one, and it picked
    // the bar on the first keyboard of a session and the pill on every
    // keyboard after.
    @Test("on a screen with room to spare the pane stops where the keys do")
    func wideScreenPanes() throws {
        for screen in [834.0, 1024.0, 1366.0] as [CGFloat] {
            let row = aRow { _ in }
            // Laid out at no width first, which is the life an accessory view
            // actually has: it is built before the keyboard has said how wide
            // it is, and the width arrives on a second pass.
            row.layoutIfNeeded()
            row.frame = CGRect(
                x: 0, y: 0, width: screen, height: row.intrinsicContentSize.height
            )
            row.layoutIfNeeded()

            let controls = controls(of: row)
            let suggestion = try #require(controls.last)
            let formatting = controls.dropLast()
            let firstControl = try #require(formatting.first)
            let pane = try #require(glass(containing: firstControl))
            let apart = try #require(glass(containing: suggestion))
            let pill = row.convert(pane.bounds, from: pane)
            let keys = formatting.map { row.convert($0.bounds, from: $0) }
            let first = try #require(keys.first)
            let last = try #require(keys.last)

            // The keys are on it, with the same room left of the first as
            // right of the last — and that room is a gap, not a half of the
            // screen.
            let before = first.minX - pill.minX
            let after = pill.maxX - last.maxX
            #expect(before > 0)
            #expect(abs(after - before) <= 1)
            #expect(after < first.width)

            // So the row goes on past the pane, and what it goes on as is
            // paper rather than more glass.
            let apartFrame = row.convert(apart.bounds, from: apart)
            #expect(apartFrame.minX > pill.maxX)
            #expect(row.bounds.width - apartFrame.maxX > first.width)

            // And it is the width, rather than a width: a key with no width
            // of its own leaves Auto Layout to pick one, and a layout that is
            // picked is a layout that comes out differently on the next
            // keyboard than on this one.
            #expect(unsettled(in: row).isEmpty)

            // The other half of that, which a frame cannot show. The pane's
            // far edge is a limit and not a position — on a row this wide the
            // keys are what says where it stops, and the row only says where
            // it may not go past.
            //
            // Asked of the constraint because the frame comes out right here
            // either way: laid out on its own, an equal-priority tug of war
            // between the pane's edges and the keys' width settles the same
            // way every time, and it was only in the keyboard's own window
            // that it settled differently on the first keyboard of a session
            // than on the second — a pill over the paper once the row had
            // been up before, and a bar across the whole iPad the first time.
            let far = try #require(
                row.constraints.first { constraint in
                    constraint.firstItem === apart.superview
                        && constraint.firstAttribute == .trailing
                }
            )
            #expect(far.relation == .lessThanOrEqual)
        }
    }

    // And the other end of it: a row with less room than nine formatting keys
    // can shrink to. The formatting keys run off their pane, while the pane
    // apart remains fully on screen.
    //
    // 200 points is narrower than any phone, and the arithmetic is the same:
    // nine keys at their floor are wider than the pane can be.
    @Test("a row too narrow for nine keys gives way before Suggestions does")
    func narrowScreens() throws {
        let row = aRow { _ in }
        row.frame = CGRect(x: 0, y: 0, width: 200, height: row.intrinsicContentSize.height)
        row.layoutIfNeeded()

        let controls = controls(of: row)
        let suggestion = try #require(controls.last)
        let photograph = try #require(controls.dropLast().last)
        let pane = try #require(glass(containing: photograph))
        let apart = try #require(glass(containing: suggestion))
        let pill = row.convert(pane.bounds, from: pane)
        let apartFrame = row.convert(apart.bounds, from: apart)
        #expect(pill.minX > 0)
        #expect(apartFrame.minX > pill.maxX)
        #expect(apartFrame.maxX < row.bounds.maxX)

        // The keys keep their floor rather than being squeezed under it, and
        // the last of them is off the pane, where the scroller can reach it.
        let keys = Array(controls.dropLast())
        #expect(keys.allSatisfy { $0.bounds.width >= 34 })
        #expect(row.convert(photograph.bounds, from: photograph).maxX > pill.maxX)
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

    @Test("Suggestions is offered exactly when something can answer it")
    func suggestions() throws {
        #expect(try !control("openSuggestions", of: aRow { _ in }).isEnabled)

        let pressed = Pressed()
        let ready = aRow(openSuggestions: { pressed.suggestions += 1 }) { _ in }
        let suggestions = try control("openSuggestions", of: ready)

        #expect(suggestions.isEnabled)
        #expect(suggestions.accessibilityLabel == "Suggestions")
        suggestions.sendActions(for: .touchUpInside)
        #expect(pressed.suggestions == 1)
    }

    // MARK: - Reading the row

    /// What a press was heard as. A box rather than a variable, because the
    /// row keeps the closure that writes to it.
    private final class Pressed {
        var commands: [MarkdownFormatting] = []
        var photographs = 0
        var suggestions = 0
    }

    /// A row, with an accent for the pressed key. Terracotta rather than the
    /// default, so that a key drawn in the wrong colour is a key drawn in a
    /// colour no test asked for.
    private func aRow(
        insertPhoto: (() -> Void)? = nil,
        openSuggestions: (() -> Void)? = nil,
        format: @escaping (MarkdownFormatting) -> Void
    ) -> MarkdownAccessoryRow {
        MarkdownAccessoryRow(
            accent: Accent.terracotta.uiColor,
            insertPhoto: insertPhoto,
            openSuggestions: openSuggestions,
            format: format
        )
    }

    /// The shadows the pill casts, which live on the view the pane sits in.
    private func shadows(under pane: UIView) -> [CALayer] {
        (pane.superview?.layer.sublayers ?? []).filter { $0.shadowOpacity > 0 }
    }

    /// The panes the keys sit on, found the way anything private is: by looking.
    private func glasses(of row: MarkdownAccessoryRow) -> [UIVisualEffectView] {
        func panes(in view: UIView) -> [UIVisualEffectView] {
            view.subviews.flatMap { subview in
                (subview as? UIVisualEffectView).map { [$0] } ?? panes(in: subview)
            }
        }
        return panes(in: row)
    }

    private func glass(containing view: UIView) -> UIVisualEffectView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let pane = current as? UIVisualEffectView { return pane }
            ancestor = current.superview
        }
        return nil
    }

    /// Every view under this one whose frame Auto Layout could have laid out
    /// somewhere else and been just as right — which is a view laid out
    /// differently the next time something asks.
    private func unsettled(in view: UIView) -> [UIView] {
        (view.hasAmbiguousLayout ? [view] : []) + view.subviews.flatMap { unsettled(in: $0) }
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
